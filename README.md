# Logilights

Eine native macOS-Menüleisten-App, die die RGB-Beleuchtung unterstützter
Logitech-G-Serie-Tastaturen setzt — automatisch beim Anstecken, nach dem
Login und beim Aufwachen aus dem Schlafmodus.

## Status

Funktioniert: gegen eine echte **Logitech G213** verifiziert — Farben werden
gesetzt, und die App wendet sie beim Anstecken automatisch an.

## Unterstützte Geräte

Tastaturen: G213, G410, G413, G512, G513, G610, G810, G815, G910, G Pro —
dieselbe Modell-Liste wie [g810-led](https://github.com/MatMoul/g810-led).

**Mäuse werden nicht unterstützt.** g810-led deckt nur Tastaturen ab;
Logitech-Maus-RGB läuft über das separate, proprietäre HID++-Protokoll.
Mögliche spätere Referenzen dafür: [Solaar](https://github.com/pwr-solaar/Solaar),
[libratbag](https://github.com/libratbag/libratbag),
[logiops](https://github.com/PixlOne/logiops). Beachte außerdem: viele als
„Gaming Mouse" verkaufte Geräte sind gar keine Logitech-Geräte (andere
Vendor-ID) und damit über keinen dieser Wege ansteuerbar.

## Warum USB-Control-Transfer statt HID-API?

Der naheliegende macOS-Weg wäre `IOHIDDeviceSetReport`. Der funktioniert
hier **nicht**: macOS lehnt ihn auf diesen Tastaturen mit
`kIOReturnNotPermitted` (`0xe00002e2`) ab, weil ihre erste HID-Collection
eine Keyboard-Collection ist. Das ist eine Anti-Keylogger-Härtung — und sie
lässt sich **weder** mit der Berechtigung „Eingabeüberwachung" (getestet:
`granted`, ändert nichts) **noch** mit `sudo` umgehen.

Stattdessen sendet `USBLEDTransport` denselben Control-Transfer, den
g810-led unter Linux via libusb nutzt:

| Feld | Wert |
|---|---|
| `bmRequestType` | `0x21` (Host→Device, Class, Interface) |
| `bRequest` | `0x09` (SET_REPORT) |
| `wValue` | `0x02<ReportID>` — `0x0211` (20 Byte) / `0x0212` (64 Byte) |
| `wIndex` | `1` (Interface 1) |

Das läuft über `IOUSBDeviceInterface.DeviceRequest` an Endpoint 0 des
Geräts und benennt Interface 1 nur in `wIndex`. Dadurch bleibt das
HID-Interface bei `AppleUserHIDDriver` — es muss nichts verdrängt werden,
und die App braucht **weder Root-Rechte noch irgendeine TCC-Berechtigung**.

Der Report-Descriptor der G213 bestätigt die portierten Werte: Interface 1
deklariert unter Logitechs Vendor-Usage-Page `0xFF43` genau die Report-IDs
`0x11` (19+1 = 20 Byte) und `0x12` (63+1 = 64 Byte) als Output-Reports.

### Zwei Fallstricke

- **Reports brauchen Abstand.** Ohne g810-leds `usleep(1000)` zwischen den
  Transfers verschluckt die Tastatur einzelne Reports, *obwohl der Transfer
  Erfolg meldet* — konkret blieb Region 1 der G213 auf ihrer alten Farbe,
  während Regionen 2–5 umschalteten.
- **IOKit-Matching.** USB-Property-Filter im Matching-Dictionary greifen nur,
  wenn `idVendor` **und** `idProduct` gesetzt sind; mit `idVendor` allein
  matcht IOKit stillschweigend gar nichts. Deshalb enumeriert der Code alle
  USB-Geräte und filtert selbst.

## Architektur

- **`Protocol/`** — reine, hardwarefreie Byte-Kodierung
  (`LogitechColorProtocol`), 1:1 aus g810-leds `LedKeyboard`-Klasse
  (`src/classes/Keyboard.cpp`) portiert. Unit-getestet ohne angeschlossenes
  Gerät.
- **`HID/USBDeviceMonitor`** — IOKit-USB-Notifications, meldet Attach/Detach
  unterstützter Logitech-Tastaturen (kein HID-Stack, daher keine
  TCC-Berechtigung nötig).
- **`HID/USBLEDTransport`** — sendet die kodierten Reports als
  USB-Control-Transfer (siehe oben).
- **`ColorProfileStore`** — persistiert eine Farbe pro Modell unter
  `~/Library/Application Support/Logilights/profile.json`.
- **`AppCoordinator`** — verbindet alles: reagiert auf Attach-Events, hält
  die Liste verbundener Modelle für die UI vor.
- **`TriggerCoordinator`** — registriert die App als Login Item
  (`SMAppService`) und wendet beim Start (= nach Login) sowie beim Aufwachen
  (`NSWorkspace.didWakeNotification`) alle gespeicherten Farben erneut an.
- **SwiftUI-Menüleisten-UI** (`LogilightsApp`, `ContentView`) — Farbwähler
  pro verbundenem Modell.

## Verwendete Frameworks

Alle Apple-nativ, keine Drittanbieter-Laufzeitabhängigkeit:

- Swift Package Manager (Build-System)
- SwiftUI (`MenuBarExtra`, `ColorPicker`)
- AppKit (`NSApplication`, `NSWorkspace`, `NSColor`)
- IOKit / `IOUSBLib` (Geräteerkennung via USB-Notifications + Control-Transfer)
- ServiceManagement (`SMAppService`, Login Item)
- XCTest

## Bauen & Ausführen

Mit Xcode 27+ oder direkt per CLI (funktioniert identisch in VSCodium mit
SourceKit-LSP, da reines SPM-Package ohne `.xcodeproj`):

```sh
swift build
swift run Logilights          # Menüleisten-App
swift test                    # Protokoll-Unit-Tests, ohne Hardware
```

Zum Testen gegen echte Hardware gibt es ein CLI-Werkzeug:

```sh
swift run LogilightsCLI list          # verbundene unterstützte Tastaturen
swift run LogilightsCLI set ff0000    # ganze Tastatur rot
swift run LogilightsCLI dump ff0000   # Reports anzeigen, ohne Hardware anzufassen
```

Die App läuft als Menüleisten-Symbol ohne Dock-Icon (`NSApplication`-
Activation-Policy `.accessory`).

**Hinweis:** Login-Item-Registrierung (`SMAppService`) greift erst, wenn die
App als signiertes `.app`-Bundle läuft — unter `swift run` wird ein Fehler
geloggt und übersprungen, das ist normal während der Entwicklung.

## Lizenz

[GPLv3](LICENSE) — passend zur Herkunft der Protokolldaten aus g810-led
(ebenfalls GPLv3). Farbcode-Tabellen und Report-Layouts sind aus
[g810-led](https://github.com/MatMoul/g810-led) von MatMoul und
Contributors portiert; vielen Dank dafür.

## Git-Workflow

Die gesamte Entwicklung findet auf dem `develop`-Branch statt, `main` ist
für Releases vorgesehen.
