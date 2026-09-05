import Foundation
import IOKit
import IOKit.hid
import LogilightsCore

/// Experimental HID++ 2.0 probe, used to work out how a given Logitech device
/// wants its LEDs addressed without guessing.
///
/// Writing goes over the proven USB control-transfer path (`USBLEDTransport`).
/// Reading the device's *replies* is the new part: HID++ answers arrive as HID
/// **input** reports, and unlike `IOHIDDeviceSetReport` those are not blocked
/// by the anti-keylogger hardening — they only need Input Monitoring.
enum HIDPPProbe {

    /// HID++ long report: 0x11, device index, feature index, function|swId,
    /// then 16 parameter bytes.
    static func longReport(featureIndex: UInt8, function: UInt8, params: [UInt8]) -> HIDOutputReport {
        var bytes: [UInt8] = [0x11, 0xff, featureIndex, function]
        bytes.append(contentsOf: params)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 20 - bytes.count))
        return HIDOutputReport(reportID: 0x11, bytes: bytes)
    }

    /// HID++ short report: 0x10 + device index + feature + function + 3 params.
    static func shortReport(featureIndex: UInt8, function: UInt8, params: [UInt8]) -> HIDOutputReport {
        var bytes: [UInt8] = [0x10, 0xff, featureIndex, function]
        bytes.append(contentsOf: params)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 7 - bytes.count))
        return HIDOutputReport(reportID: 0x10, bytes: bytes)
    }

    // MARK: - Reading replies

    final class Listener {
        private var manager: IOHIDManager?
        private(set) var received: [[UInt8]] = []
        private var buffer = [UInt8](repeating: 0, count: 64)

        func start(vendorID: UInt16, productID: UInt16) -> Bool {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [String: Any] = [
                kIOHIDVendorIDKey: Int(vendorID),
                kIOHIDProductIDKey: Int(productID),
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                print(String(format: "IOHIDManagerOpen failed: 0x%08x", UInt32(bitPattern: openResult)))
                return false
            }

            // The manager-level callback takes no buffer of its own; each
            // enumerated device needs one registered individually.
            IOHIDManagerRegisterInputReportCallback(
                manager,
                { context, _, _, _, reportID, report, length in
                    guard let context else { return }
                    let listener = Unmanaged<Listener>.fromOpaque(context).takeUnretainedValue()
                    var bytes = [UInt8(truncatingIfNeeded: reportID)]
                    bytes.append(contentsOf: UnsafeBufferPointer(start: report, count: length))
                    listener.received.append(bytes)
                },
                Unmanaged.passUnretained(self).toOpaque())

            self.manager = manager
            return true
        }

        /// Runs the run loop briefly so callbacks can fire.
        func pump(seconds: TimeInterval) {
            CFRunLoopRunInMode(.defaultMode, seconds, false)
        }

        func stop() {
            guard let manager else { return }
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
    }

    // MARK: - Commands

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Asks the device's HID++ root feature (index 0x00, function 0x00) for the
    /// index of each interesting feature, and prints whatever comes back.
    static func features(vendorID: UInt16, productID: UInt16) {
        let interesting: [(UInt16, String)] = [
            (0x0000, "IRoot"),
            (0x0001, "IFeatureSet"),
            (0x0003, "DeviceInformation"),
            (0x8070, "ColorLedEffects"),
            (0x8071, "RGBEffects"),
            (0x8060, "ReportRate"),
            (0x8100, "OnboardProfiles"),
        ]

        let listener = Listener()
        guard listener.start(vendorID: vendorID, productID: productID) else { return }
        defer { listener.stop() }
        listener.pump(seconds: 0.2)

        let transport = USBLEDTransport()

        for (feature, name) in interesting {
            let before = listener.received.count
            let request = longReport(
                featureIndex: 0x00,
                function: 0x0a,  // getFeature(featureId), software id 0xa
                params: [UInt8(feature >> 8), UInt8(feature & 0xff)])
            do {
                try transport.send(reports: [request], vendorID: vendorID, productID: productID)
            } catch {
                print("send failed for \(name): \(error)")
                continue
            }
            listener.pump(seconds: 0.4)

            let replies = Array(listener.received.dropFirst(before))
            if replies.isEmpty {
                print(String(format: "0x%04x %-18@ -> (no reply)", feature, name as NSString))
            } else {
                for reply in replies {
                    print(String(format: "0x%04x %-18@ -> %@", feature, name as NSString, hex(reply) as NSString))
                }
            }
        }
    }

    /// Sends one hand-written HID++ report and prints any reply, so a candidate
    /// LED command can be tried against the hardware directly.
    static func raw(vendorID: UInt16, productID: UInt16, bytes: [UInt8]) {
        let listener = Listener()
        _ = listener.start(vendorID: vendorID, productID: productID)
        defer { listener.stop() }
        listener.pump(seconds: 0.2)

        var padded = bytes
        let size = bytes.first == 0x10 ? 7 : 20
        if padded.count < size {
            padded.append(contentsOf: [UInt8](repeating: 0, count: size - padded.count))
        }
        let report = HIDOutputReport(reportID: padded[0], bytes: padded)

        print("-> " + hex(padded))
        do {
            try USBLEDTransport().send(reports: [report], vendorID: vendorID, productID: productID)
        } catch {
            print("send failed: \(error)")
            return
        }
        listener.pump(seconds: 0.5)

        if listener.received.isEmpty {
            print("<- (no reply)")
        } else {
            for reply in listener.received {
                print("<- " + hex(reply))
            }
        }
    }
}
