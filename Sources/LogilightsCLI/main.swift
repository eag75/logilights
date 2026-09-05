import Foundation
import LogilightsCore

// Diagnostics/test tool for verifying Logilights against real hardware
// without launching the menu bar app. Mirrors the parts of g810-led's CLI
// that matter for our v1 scope.
//
//   swift run LogilightsCLI list
//   swift run LogilightsCLI set ff0000
//   swift run LogilightsCLI dump ff0000

func usage() -> Never {
    print("""
    Usage:
      LogilightsCLI list             List connected supported Logitech keyboards
      LogilightsCLI set <rrggbb>     Set every connected supported keyboard to that color
      LogilightsCLI dump <rrggbb>    Print the reports that would be sent, without touching hardware

    HID++ experiments (mouse support, work in progress):
      LogilightsCLI hidpp-features <vid> <pid>       Ask via control pipe (no permissions, replies unusable)
      LogilightsCLI hidpp-features-hid <vid> <pid>   Ask via the HID stack (needs a signed bundle)
      LogilightsCLI hidpp-raw <vid> <pid> <hex...>   Send one hand-written HID++ report
    """)
    exit(1)
}

func parseColor(_ string: String) -> LogitechColor? {
    let hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    return LogitechColor(
        red: UInt8((value >> 16) & 0xff),
        green: UInt8((value >> 8) & 0xff),
        blue: UInt8(value & 0xff)
    )
}

func runList() {
    let devices = USBDeviceMonitor().connectedDevices()
    guard !devices.isEmpty else {
        print("No supported Logitech keyboard connected.")
        return
    }
    print("Connected supported keyboards:\n")
    for device in devices {
        print(String(format: "  %@  vid=0x%04x pid=0x%04x  model=%@",
                     device.name, device.vendorID, device.productID, device.model.rawValue))
    }
}

/// Sets the color over the USB control-transfer path (`USBLEDTransport`).
/// The HID path is not usable: macOS rejects IOHIDDeviceSetReport on these
/// keyboards with kIOReturnNotPermitted, regardless of Input Monitoring
/// or root.
func runSet(_ color: LogitechColor) {
    let transport = USBLEDTransport()
    var succeeded = 0

    for entry in LogitechDevices.supportedKeyboards {
        let reports = LogitechColorProtocol.setAllKeysReports(model: entry.model, color: color)
        do {
            try transport.send(reports: reports, vendorID: entry.vendorID, productID: entry.productID)
            succeeded += 1
            print(String(format: "%@ (0x%04x:0x%04x): %d report(s) sent OK",
                         entry.model.rawValue, entry.vendorID, entry.productID, reports.count))
        } catch USBLEDTransport.TransportError.deviceNotFound {
            continue // not plugged in
        } catch {
            print(String(format: "%@ (0x%04x:0x%04x): %@",
                         entry.model.rawValue, entry.vendorID, entry.productID,
                         String(describing: error)))
        }
    }

    if succeeded == 0 {
        print("No supported Logitech keyboard responded.")
        exit(1)
    }
    exit(0)
}

func runDump(_ color: LogitechColor) {
    let devices = USBDeviceMonitor().connectedDevices()
    let models = devices.isEmpty ? LogitechKeyboardModel.allCases : devices.map(\.model)
    if devices.isEmpty {
        print("(nothing connected — dumping all supported models)\n")
    }
    for model in models {
        let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: color)
        print("\(model.rawValue): \(reports.count) report(s)")
        for report in reports {
            print("  " + report.bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        print("")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

func parseID(_ string: String) -> UInt16? {
    let hex = string.hasPrefix("0x") ? String(string.dropFirst(2)) : string
    return UInt16(hex, radix: 16)
}

switch command {
case "hidpp-features-hidwrite":
    guard arguments.count == 3,
          let vid = parseID(arguments[1]), let pid = parseID(arguments[2]) else { usage() }
    HIDPPProbe.featuresViaHID(vendorID: vid, productID: pid)
case "hidpp-listen":
    guard arguments.count >= 3,
          let vid = parseID(arguments[1]), let pid = parseID(arguments[2]) else { usage() }
    let seconds = arguments.count > 3 ? (Double(arguments[3]) ?? 3) : 3
    HIDPPProbe.listen(vendorID: vid, productID: pid, seconds: seconds)
case "hidpp-features-hid":
    // Reads replies through the HID stack, which needs Input Monitoring and
    // therefore a signed bundle — see scripts/build-probe-app.sh.
    guard arguments.count == 3,
          let vid = parseID(arguments[1]), let pid = parseID(arguments[2]) else { usage() }
    HIDPPProbe.features(vendorID: vid, productID: pid)
case "hidpp-features":
    guard arguments.count == 3,
          let vid = parseID(arguments[1]), let pid = parseID(arguments[2]) else { usage() }
    HIDPPProbe.featuresViaControl(vendorID: vid, productID: pid)
case "hidpp-raw":
    guard arguments.count >= 4,
          let vid = parseID(arguments[1]), let pid = parseID(arguments[2]) else { usage() }
    let bytes = arguments.dropFirst(3).compactMap { UInt8($0, radix: 16) }
    guard bytes.count == arguments.count - 3 else {
        print("Report bytes must be hex, e.g. 11 ff 0e 3b 00 01 ff 00 00 02\n")
        usage()
    }
    HIDPPProbe.raw(vendorID: vid, productID: pid, bytes: bytes)
case "list":
    runList()
case "set", "dump":
    guard arguments.count == 2, let color = parseColor(arguments[1]) else {
        print("Expected a color like ff0000\n")
        usage()
    }
    if command == "set" { runSet(color) } else { runDump(color) }
default:
    usage()
}
