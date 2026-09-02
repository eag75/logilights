# Logilights

Eine native macOS-Menüleisten-App, die die RGB-Beleuchtung unterstützter
Logitech-G-Serie-Tastaturen setzt — automatisch beim Anstecken, nach dem
Login und beim Aufwachen aus dem Schlafmodus.

## Status

Frühes Entwicklungsstadium (siehe `develop`-Branch). Der komplette
Farb-Kodierungspfad (`LogitechColorProtocol`) ist unit-getestet, aber noch
**nicht gegen echte Hardware verifiziert** — bitte beim ersten Test mit
angeschlossener Tastatur die Konsolenausgabe (`swift run`) beobachten.

## Unterstützte Geräte

Tastaturen: G213, G410, G413, G512, G513, G610, G810, G815, G910, G Pro —
dieselbe Modell-Liste wie [g810-led](https://github.com/MatMoul/g810-led).

**Mäuse werden aktuell nicht unterstützt.** g810-led deckt nur Tastaturen ab;
Maus-RGB läuft über das separate, proprietäre Logitech-HID++-Protokoll.
Mögliche spätere Referenzen dafür: [Solaar](https://github.com/pwr-solaar/Solaar),
[libratbag](https://github.com/libratbag/libratbag),
[logiops](https://github.com/PixlOne/logiops).

## Warum IOKit/IOHIDManager statt libusb?

g810-led nutzt auf Linux libusb, um die Reports direkt an die Tastatur zu
schreiben. Auf macOS hält der eingebaute HID-Treiber das Interface exklusiv,
sodass libusb es i.d.R. nicht claimen kann. Der macOS-native Weg für diese
Vendor-Reports ist `IOHIDManager`/`IOHIDDeviceSetReport` — genau das nutzt
diese App (`HIDDeviceMonitor`, `LightingApplier`).

## Architektur

- **`Protocol/`** — reine, hardwarefreie Byte-Kodierung
  (`LogitechColorProtocol`), 1:1 aus g810-leds `LedKeyboard`-Klasse
  (`src/classes/Keyboard.cpp`) portiert. Unit-getestet ohne angeschlossenes
  Gerät.
- **`HID/HIDDeviceMonitor`** — IOHIDManager-Wrapper, meldet Attach/Detach für
  Logitech-Geräte (Vendor-ID `0x046d`).
- **`HID/LightingApplier`** — sendet die kodierten Reports per
  `IOHIDDeviceSetReport` an ein konkretes `IOHIDDevice`.
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
- IOKit / `IOHIDManager` (Geräteerkennung + Reports)
- ServiceManagement (`SMAppService`, Login Item)
- XCTest

## Bauen & Ausführen

Mit Xcode 27+ oder direkt per CLI (funktioniert identisch in VSCodium mit
SourceKit-LSP, da reines SPM-Package ohne `.xcodeproj`):

```sh
swift build
swift run Logilights
swift test
```

Die App läuft als Menüleisten-Symbol ohne Dock-Icon (`NSApplication`-
Activation-Policy `.accessory`).

**Hinweis:** Login-Item-Registrierung (`SMAppService`) greift erst, wenn die
App als signiertes `.app`-Bundle läuft — unter `swift run` wird ein Fehler
geloggt und übersprungen, das ist normal während der Entwicklung.

Falls `IOHIDDeviceOpen` fehlschlägt: unter Systemeinstellungen →
Datenschutz & Sicherheit → Eingabeüberwachung könnte die App freigeschaltet
werden müssen.

## Lizenz

[GPLv3](LICENSE) — passend zur Herkunft der Protokolldaten aus g810-led
(ebenfalls GPLv3). Farbcode-Tabellen und Report-Layouts sind aus
[g810-led](https://github.com/MatMoul/g810-led) von MatMoul und
Contributors portiert; vielen Dank dafür.

## Git-Workflow

Die gesamte Entwicklung findet auf dem `develop`-Branch statt, `main` ist
für Releases vorgesehen.
