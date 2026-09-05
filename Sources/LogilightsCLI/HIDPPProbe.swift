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

    private static func accessName(_ value: IOHIDAccessType) -> String {
        switch value {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        case kIOHIDAccessTypeUnknown: return "unknown (not yet asked)"
        default: return "\(value.rawValue)"
        }
    }

    // MARK: - Reading replies

    final class Listener {
        private var manager: IOHIDManager?
        private var devices: [IOHIDDevice] = []
        private var buffers: [UnsafeMutablePointer<UInt8>] = []
        private(set) var received: [[UInt8]] = []

        func start(vendorID: UInt16, productID: UInt16) -> Bool {
            print("Input Monitoring: \(accessName(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)))")

            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [String: Any] = [
                kIOHIDVendorIDKey: Int(vendorID),
                kIOHIDProductIDKey: Int(productID),
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                print(String(format: "IOHIDManagerOpen failed: 0x%08x", UInt32(bitPattern: openResult)))
                return false
            }
            self.manager = manager

            devices = Array((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
            let context = Unmanaged.passUnretained(self).toOpaque()

            // The manager-level callback does not deliver anything on its own;
            // each device needs its own registration and its own buffer, which
            // has to stay alive for as long as the callback is registered.
            for device in devices {
                let size = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
                buffer.initialize(repeating: 0, count: size)
                buffers.append(buffer)

                IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDDeviceRegisterInputReportCallback(
                    device, buffer, size,
                    { context, _, _, _, reportID, report, length in
                        guard let context else { return }
                        let listener = Unmanaged<Listener>.fromOpaque(context).takeUnretainedValue()
                        var bytes = [UInt8(truncatingIfNeeded: reportID)]
                        bytes.append(contentsOf: UnsafeBufferPointer(start: report, count: length))
                        listener.received.append(bytes)
                    },
                    context)
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }

            print("Listening on \(devices.count) device(s)")
            return !devices.isEmpty
        }

        /// The device carrying the 20-byte HID++ long report.
        var hidppDevice: IOHIDDevice? {
            devices.first { device in
                (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) == 20
            }
        }

        /// Writes an output report through the HID stack instead of the USB
        /// control pipe. `report.bytes` includes the report ID as byte 0,
        /// while IOHIDDeviceSetReport takes it separately.
        func setReport(_ report: HIDOutputReport) -> IOReturn {
            guard let device = hidppDevice else { return kIOReturnNoDevice }
            let payload = Array(report.bytes.dropFirst())
            return payload.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(report.reportID),
                    buffer.baseAddress!,
                    buffer.count)
            }
        }

        /// Runs the run loop briefly so callbacks can fire.
        func pump(seconds: TimeInterval) {
            CFRunLoopRunInMode(.defaultMode, seconds, false)
        }

        func stop() {
            for device in devices {
                IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            devices = []
            for buffer in buffers { buffer.deallocate() }
            buffers = []
            if let manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                self.manager = nil
            }
        }
    }

    // MARK: - Request/response over the control pipe

    /// Sends one HID++ request and reads the reply with GET_REPORT, bypassing
    /// the HID stack entirely (no Input Monitoring needed).
    static func exchange(
        vendorID: UInt16,
        productID: UInt16,
        request: HIDOutputReport
    ) -> [UInt8]? {
        do {
            return try USBLEDTransport().exchange(
                report: request,
                replyReportID: request.reportID,
                replyLength: request.bytes.count,
                vendorID: vendorID,
                productID: productID)
        } catch {
            print("exchange failed: \(error)")
            return nil
        }
    }

    /// Walks the HID++ feature table, writing the requests through the HID
    /// stack (IOHIDDeviceSetReport) rather than the USB control pipe.
    static func featuresViaHID(vendorID: UInt16, productID: UInt16) {
        let interesting: [(UInt16, String)] = [
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

        for (feature, name) in interesting {
            let before = listener.received.count
            let request = longReport(
                featureIndex: 0x00,
                function: 0x0a,  // getFeature(featureId), software id 0xa
                params: [UInt8(feature >> 8), UInt8(feature & 0xff)])

            let result = listener.setReport(request)
            guard result == kIOReturnSuccess else {
                print(String(format: "0x%04x %-18@ setReport failed: 0x%08x",
                             feature, name as NSString, UInt32(bitPattern: result)))
                continue
            }
            listener.pump(seconds: 0.4)

            // Ignore the mouse movement reports that keep streaming in.
            let replies = listener.received.dropFirst(before).filter { $0.first == 0x11 || $0.first == 0x10 }
            if replies.isEmpty {
                print(String(format: "0x%04x %-18@ -> (no reply)", feature, name as NSString))
            } else {
                for reply in replies {
                    print(String(format: "0x%04x %-18@ -> %@", feature, name as NSString, hex(reply) as NSString))
                }
            }
        }
    }

    /// Listens for input reports without sending anything, to verify the
    /// callback plumbing works at all (mouse movement alone produces reports).
    static func listen(vendorID: UInt16, productID: UInt16, seconds: TimeInterval) {
        let listener = Listener()
        guard listener.start(vendorID: vendorID, productID: productID) else { return }
        defer { listener.stop() }

        print("Listening for \(Int(seconds))s — move the device to generate reports…")
        listener.pump(seconds: seconds)

        print("Received \(listener.received.count) report(s)")
        for reply in listener.received.prefix(8) {
            print("  " + hex(reply))
        }
    }

    /// Walks the HID++ feature table over the control pipe.
    static func featuresViaControl(vendorID: UInt16, productID: UInt16) {
        let interesting: [(UInt16, String)] = [
            (0x0000, "IRoot"),
            (0x0001, "IFeatureSet"),
            (0x0003, "DeviceInformation"),
            (0x8070, "ColorLedEffects"),
            (0x8071, "RGBEffects"),
            (0x8060, "ReportRate"),
            (0x8100, "OnboardProfiles"),
        ]

        for (feature, name) in interesting {
            let request = longReport(
                featureIndex: 0x00,
                function: 0x0a,  // getFeature(featureId), software id 0xa
                params: [UInt8(feature >> 8), UInt8(feature & 0xff)])
            guard let reply = exchange(vendorID: vendorID, productID: productID, request: request) else {
                return
            }
            print(String(format: "0x%04x %-18@ <- %@", feature, name as NSString, hex(reply) as NSString))
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

    /// Sends one hand-written HID++ report over the control pipe and prints
    /// whatever the device answers on the HID input reports.
    ///
    /// This is the only combination that can work here: writes through the
    /// HID stack are refused with kIOReturnNotPermitted, and replies are not
    /// readable over the control pipe.
    static func raw(vendorID: UInt16, productID: UInt16, bytes: [UInt8]) {
        var padded = bytes
        let size = bytes.first == 0x10 ? 7 : 20
        if padded.count < size {
            padded.append(contentsOf: [UInt8](repeating: 0, count: size - padded.count))
        }
        let report = HIDOutputReport(reportID: padded[0], bytes: padded)

        let listener = Listener()
        guard listener.start(vendorID: vendorID, productID: productID) else { return }
        defer { listener.stop() }
        listener.pump(seconds: 0.2)
        let before = listener.received.count

        print("-> " + hex(padded))
        USBLEDTransport.verbose = true
        defer { USBLEDTransport.verbose = false }
        do {
            try USBLEDTransport().send(reports: [report], vendorID: vendorID, productID: productID)
        } catch {
            print("send failed: \(error)")
            return
        }
        listener.pump(seconds: 0.6)

        // Mouse movement keeps producing reports; only HID++ ones matter.
        let replies = listener.received.dropFirst(before).filter { $0.first == 0x10 || $0.first == 0x11 }
        if replies.isEmpty {
            print("<- (no HID++ reply; \(listener.received.count - before) other report(s) seen)")
        } else {
            for reply in replies { print("<- " + hex(reply)) }
        }
    }
}
