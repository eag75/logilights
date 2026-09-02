import Foundation
import IOKit.hid
import LogilightsCore

// A small diagnostics/test tool for verifying Logilights against real
// hardware without launching the menu bar app. Mirrors the parts of
// g810-led's CLI that matter for our v1 scope.
//
//   swift run LogilightsCLI list
//   swift run LogilightsCLI set ff0000
//   swift run LogilightsCLI dump ff0000

func usage() -> Never {
    print("""
    Usage:
      LogilightsCLI list             List all Logitech HID interfaces and whether they can be opened
      LogilightsCLI set <rrggbb>     Set every supported connected keyboard to that color
      LogilightsCLI dump <rrggbb>    Print the reports that would be sent, without touching hardware
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

/// Enumerates matching devices synchronously, without needing a run loop.
func logitechDevices() -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [kIOHIDVendorIDKey: Int(LogitechDevices.logitechVendorID)]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

func hex(_ value: Int?) -> String {
    guard let value else { return "?" }
    return "0x" + String(format: "%04x", value)
}

func describe(_ device: IOHIDDevice) -> String {
    let name = device.productName ?? "unknown"
    let vid = device.vendorID.map { "0x" + String(format: "%04x", $0) } ?? "?"
    let pid = device.productID.map { "0x" + String(format: "%04x", $0) } ?? "?"
    let model = device.logitechModel?.rawValue ?? "unsupported"
    return "\(name)  vid=\(vid) pid=\(pid)  usagePage=\(hex(device.primaryUsagePage)) usage=\(hex(device.primaryUsage))  model=\(model)"
}

func runList() {
    let devices = logitechDevices()
    guard !devices.isEmpty else {
        print("No Logitech HID devices found.")
        return
    }
    print("Found \(devices.count) Logitech HID interface(s):\n")
    for device in devices {
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let openState: String
        if openResult == kIOReturnSuccess {
            openState = "open: ok"
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        } else {
            openState = "open: FAILED (0x" + String(format: "%08x", UInt32(bitPattern: openResult)) + ")"
        }
        print("  \(describe(device))  \(openState)")
    }
}

func runSet(_ color: LogitechColor) {
    let devices = logitechDevices().filter { $0.logitechModel != nil }
    guard !devices.isEmpty else {
        print("No supported Logitech keyboard connected.")
        exit(1)
    }

    var anySucceeded = false
    for device in devices {
        guard let model = device.logitechModel else { continue }
        print("\n→ \(describe(device))")

        // If opening fails (typically kIOReturnNotPermitted = 0xe00002e2,
        // meaning Input Monitoring hasn't been granted), still try the
        // reports: SetReport does not strictly require an open device on
        // every macOS version, and knowing that is useful diagnostics.
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            print("   open: ok")
        } else {
            print("   open failed: 0x" + String(format: "%08x", UInt32(bitPattern: openResult))
                  + " — trying reports anyway")
        }
        defer {
            if openResult == kIOReturnSuccess {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }

        let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: color)
        var deviceOK = true
        for (index, report) in reports.enumerated() {
            let result = report.bytes.withUnsafeBufferPointer { buffer -> IOReturn in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(report.reportID),
                    buffer.baseAddress!,
                    buffer.count
                )
            }
            let status = result == kIOReturnSuccess
                ? "ok"
                : "FAILED 0x" + String(format: "%08x", UInt32(bitPattern: result))
            print("   report \(index + 1)/\(reports.count) id=0x\(String(report.reportID, radix: 16)) len=\(report.bytes.count): \(status)")
            if result != kIOReturnSuccess { deviceOK = false }
        }
        if deviceOK { anySucceeded = true }
    }

    print(anySucceeded
        ? "\nAt least one interface accepted every report."
        : "\nNo interface accepted the reports.")
    exit(anySucceeded ? 0 : 1)
}

func runDump(_ color: LogitechColor) {
    for device in logitechDevices() {
        guard let model = device.logitechModel else { continue }
        let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: color)
        print("\(model.rawValue): \(reports.count) report(s)")
        for report in reports {
            let bytes = report.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("  \(bytes)")
        }
        return
    }
    print("No supported Logitech keyboard connected.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
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
