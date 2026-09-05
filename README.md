# Logilights

A native macOS menu bar app that sets the RGB lighting on supported Logitech
G-series keyboards — automatically on plug-in, after login, and on wake from
sleep.

## Status

Verified against a real **Logitech G213**:

| | |
|---|---|
| Setting a color | ✅ |
| Automatically on plug and unplug | ✅ |
| Automatically on app launch (i.e. after login) | ✅ |
| On wake from sleep | ✅ |
| After a reboot | ✅ (via the login item) |
| Registering as a login item | ✅ (menu toggle and `enable`/`disable`) |

## Supported devices

Keyboards: G213, G410, G413, G512, G513, G610, G810, G815, G910, G Pro — the
same model list as [g810-led](https://github.com/MatMoul/g810-led).

**Mice are not supported.** g810-led covers keyboards only; Logitech mouse
RGB goes through the separate, proprietary HID++ protocol. Possible
references for that later on:
[Solaar](https://github.com/pwr-solaar/Solaar),
[libratbag](https://github.com/libratbag/libratbag),
[logiops](https://github.com/PixlOne/logiops). Also note that many devices
sold as a "gaming mouse" are not Logitech hardware at all (different vendor
ID), which puts them out of reach of any of those.

## Why a USB control transfer instead of the HID API?

The obvious route on macOS would be `IOHIDDeviceSetReport`. It does **not**
work here: macOS rejects it on these keyboards with `kIOReturnNotPermitted`
(`0xe00002e2`), because their first HID collection is a keyboard collection.
This is anti-keylogger hardening, and it can be lifted **neither** by the
"Input Monitoring" permission (tested: `granted`, makes no difference)
**nor** by `sudo`.

Instead, `USBLEDTransport` sends the same control transfer that g810-led
uses on Linux via libusb:

| Field | Value |
|---|---|
| `bmRequestType` | `0x21` (host→device, class, interface) |
| `bRequest` | `0x09` (SET_REPORT) |
| `wValue` | `0x02<report ID>` — `0x0211` (20 bytes) / `0x0212` (64 bytes) |
| `wIndex` | `1` (interface 1) |

This goes through `IOUSBDeviceInterface.DeviceRequest` to endpoint 0 of the
device and merely names interface 1 in `wIndex`. The HID interface therefore
stays with `AppleUserHIDDriver` — nothing has to be seized, and the app needs
**neither root privileges nor any TCC authorization**.

The G213's report descriptor confirms the ported values: interface 1
declares exactly the report IDs `0x11` (19+1 = 20 bytes) and `0x12`
(63+1 = 64 bytes) as output reports, under Logitech's vendor usage page
`0xFF43`.

### Two pitfalls

- **Reports need spacing.** Without g810-led's `usleep(1000)` between
  transfers the keyboard silently drops individual reports, *even though the
  transfer reports success* — concretely, region 1 of the G213 kept its old
  color while regions 2–5 changed.
- **IOKit matching.** USB property filters in a matching dictionary only take
  effect when `idVendor` **and** `idProduct` are both set; with `idVendor`
  alone IOKit silently matches nothing. The code therefore enumerates all USB
  devices and filters them itself.

## Architecture

- **`Protocol/`** — pure, hardware-free byte encoding
  (`LogitechColorProtocol`), ported 1:1 from g810-led's `LedKeyboard` class
  (`src/classes/Keyboard.cpp`). Unit-tested with no device attached.
- **`HID/USBDeviceMonitor`** — IOKit USB notifications reporting attach and
  detach of supported Logitech keyboards (no HID stack, hence no TCC
  authorization needed).
- **`HID/USBLEDTransport`** — sends the encoded reports as a USB control
  transfer (see above).
- **`ColorProfileStore`** — persists one color per model in
  `~/Library/Application Support/Logilights/profile.json`.
- **`AppCoordinator`** — ties it together: reacts to attach events and keeps
  the list of connected models for the UI.
- **`TriggerCoordinator`** — reapplies all stored colors on launch (i.e.
  after login) and on wake (`NSWorkspace.didWakeNotification`). It
  deliberately does *not* register the login item; that is a user-facing
  setting, see below.
- **SwiftUI menu bar UI** (`LogilightsApp`, `ContentView`) — a color picker
  per connected model.

## Frameworks used

All Apple-native, no third-party runtime dependency:

- Swift Package Manager (build system)
- SwiftUI (`MenuBarExtra`, `ColorPicker`)
- AppKit (`NSApplication`, `NSWorkspace`, `NSColor`)
- IOKit / `IOUSBLib` (device discovery via USB notifications + control transfer)
- ServiceManagement (`SMAppService`, login item)
- XCTest

## Building and running

With Xcode 27+ or straight from the command line (identical in VSCodium with
SourceKit-LSP, since this is a plain SPM package with no `.xcodeproj`):

```sh
swift build
swift run Logilights          # menu bar app
swift test                    # protocol unit tests, no hardware needed
```

There is a CLI tool for testing against real hardware:

```sh
swift run LogilightsCLI list          # connected supported keyboards
swift run LogilightsCLI set ff0000    # whole keyboard red
swift run LogilightsCLI dump ff0000   # show the reports without touching hardware
```

The app runs as a menu bar icon with no dock icon (`LSUIElement`).

### Building the app bundle

`swift run` is enough for development, but "start at login"
(`SMAppService`) only works from a real, signed bundle:

```sh
./scripts/build-app.sh              # -> build/Logilights.app (ad-hoc signed)
./scripts/build-app.sh --install    # also copy it to /Applications
```

No prebuilt binaries are distributed: the bundle is only ad-hoc signed, so a
downloaded copy would be blocked by Gatekeeper. Build it yourself with the
script above. With an Apple Developer ID, a distributable version can be
signed like this:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

Because macOS ties login items to the bundle's path, the app should live in a
fixed location (e.g. `/Applications`) rather than in the `build/` directory.

### Start at login

The toggle sits in the menu bar popover. Logilights does **not** add itself.
It is scriptable too:

```sh
/Applications/Logilights.app/Contents/MacOS/Logilights --login-item status
/Applications/Logilights.app/Contents/MacOS/Logilights --login-item enable
/Applications/Logilights.app/Contents/MacOS/Logilights --login-item disable
```

If the status comes back as `requiresApproval`, the entry still has to be
approved under System Settings → General → Login Items.

### Logs

A bundled `.app` has no usable stdout, so everything goes through `os_log`:

```sh
log stream --level info --predicate 'subsystem == "io.github.eag75.Logilights"'
```

## License

[GPLv3](LICENSE) — matching the origin of the protocol data in g810-led
(also GPLv3). Color tables and report layouts are ported from
[g810-led](https://github.com/MatMoul/g810-led) by MatMoul and contributors;
many thanks for that work.

## Git workflow

All development happens on the `develop` branch; `main` is reserved for
releases.
