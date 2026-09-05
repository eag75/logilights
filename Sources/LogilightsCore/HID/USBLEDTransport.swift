import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

/// Sends the LED reports over a USB control transfer to endpoint 0, which is
/// exactly what g810-led does on Linux via libusb.
///
/// Why not the HID API? macOS refuses `IOHIDDeviceSetReport` on these devices
/// with `kIOReturnNotPermitted` (0xe00002e2), because the keyboard's first
/// top-level collection is a keyboard — an anti-keylogger hardening that
/// neither Input Monitoring nor running as root lifts.
///
/// Going through `IOUSBDeviceInterface.DeviceRequest` sidesteps that: the
/// request targets endpoint 0 of the *device* and merely names interface 1 in
/// wIndex, so we never claim the HID interface that AppleUserHIDDriver owns.
/// It needs no special privileges and no TCC authorization.
public final class USBLEDTransport {

    public enum TransportError: Error, CustomStringConvertible {
        case deviceNotFound
        case openFailed(IOReturn)
        case requestFailed(IOReturn)

        public var description: String {
            switch self {
            case .deviceNotFound:
                return "USB device not found"
            case .openFailed(let code):
                return "USBDeviceOpen failed: 0x" + String(format: "%08x", UInt32(bitPattern: code))
            case .requestFailed(let code):
                return "DeviceRequest failed: 0x" + String(format: "%08x", UInt32(bitPattern: code))
            }
        }
    }

    /// g810-led addresses interface 1 on every supported keyboard.
    private static let ledInterfaceIndex: UInt16 = 1

    // The CFUUIDs below are spelled out because their SDK definitions are
    // C macros, which Swift cannot import.
    private static let deviceUserClientTypeID = makeUUID(
        [0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
         0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61])
    private static let plugInInterfaceID = makeUUID(
        [0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
         0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F])
    private static let deviceInterfaceID100 = makeUUID(
        [0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
         0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61])

    private static func makeUUID(_ b: [UInt8]) -> CFUUID {
        CFUUIDGetConstantUUIDWithBytes(nil, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }

    /// Prints how the device was opened. Diagnostics for the HID++ work,
    /// where seizing the device from the HID driver would cost us the
    /// interrupt-endpoint replies we are trying to read.
    public static var verbose = false

    public init() {}

    /// Applies `color` to every connected keyboard of a supported model.
    /// Returns the models it successfully wrote to.
    @discardableResult
    public func applyToAllConnected(color: LogitechColor) -> [LogitechKeyboardModel] {
        var applied: [LogitechKeyboardModel] = []
        for entry in LogitechDevices.supportedKeyboards {
            let reports = LogitechColorProtocol.setAllKeysReports(model: entry.model, color: color)
            if (try? send(reports: reports, vendorID: entry.vendorID, productID: entry.productID)) != nil {
                applied.append(entry.model)
            }
        }
        return applied
    }

    /// Applies `color` to one specific model, if a matching device is connected.
    public func apply(color: LogitechColor, to model: LogitechKeyboardModel) throws {
        let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: color)
        for entry in LogitechDevices.supportedKeyboards where entry.model == model {
            if (try? send(reports: reports, vendorID: entry.vendorID, productID: entry.productID)) != nil {
                return
            }
        }
        throw TransportError.deviceNotFound
    }

    /// Sends the given reports to the first matching USB device.
    public func send(reports: [HIDOutputReport], vendorID: UInt16, productID: UInt16) throws {
        try withOpenDevice(vendorID: vendorID, productID: productID) { device, api in
            for report in reports {
                try send(report: report, to: device, api: api)
                // g810-led sleeps 1 ms after every control transfer (and drains
                // the interrupt endpoint). Without a pause the keyboard silently
                // drops reports even though the transfer itself reports success
                // — observed on a G213, where region 1 kept its previous color
                // while regions 2-5 updated.
                usleep(Self.interReportDelayMicroseconds)
            }
        }
    }

    /// Sends `report`, then asks the device for an input report of
    /// `replyReportID` over a GET_REPORT control transfer, in the same open
    /// session.
    ///
    /// Experimental, for HID++ feature discovery: those devices answer a
    /// request on an *input* report, which normally has to be read from the
    /// interrupt endpoint. Reading it through the control pipe instead — if
    /// the device honors that — avoids the HID stack, which macOS blocks on
    /// devices that carry a keyboard collection.
    public func exchange(
        report: HIDOutputReport,
        replyReportID: UInt8,
        replyLength: Int,
        vendorID: UInt16,
        productID: UInt16
    ) throws -> [UInt8] {
        var reply = [UInt8](repeating: 0, count: replyLength)
        try withOpenDevice(vendorID: vendorID, productID: productID) { device, api in
            try send(report: report, to: device, api: api)
            usleep(Self.interReportDelayMicroseconds)

            let result = reply.withUnsafeMutableBufferPointer { buffer -> IOReturn in
                var request = IOUSBDevRequest(
                    bmRequestType: 0xa1,  // device->host | class | interface
                    bRequest: 0x01,       // GET_REPORT
                    // High byte 0x01 selects an Input report.
                    wValue: 0x0100 | UInt16(replyReportID),
                    wIndex: Self.ledInterfaceIndex,
                    wLength: UInt16(buffer.count),
                    pData: buffer.baseAddress,
                    wLenDone: 0)
                return api.DeviceRequest(device, &request)
            }
            guard result == kIOReturnSuccess else { throw TransportError.requestFailed(result) }
        }
        return reply
    }

    /// Opens the matching device, runs `body`, and closes it again.
    private func withOpenDevice(
        vendorID: UInt16,
        productID: UInt16,
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>, IOUSBDeviceInterface) throws -> Void
    ) throws {
        guard let service = findDevice(vendorID: vendorID, productID: productID) else {
            throw TransportError.deviceNotFound
        }
        defer { IOObjectRelease(service) }

        guard let device = deviceInterface(for: service) else {
            throw TransportError.deviceNotFound
        }
        defer { _ = device.pointee?.pointee.Release(device) }
        guard let api = device.pointee?.pointee else { throw TransportError.deviceNotFound }

        var openResult = api.USBDeviceOpen(device)
        if openResult != kIOReturnSuccess {
            // Another process (or a driver) holds it — take it over.
            if Self.verbose {
                print(String(format: "[transport] USBDeviceOpen failed (0x%08x), seizing",
                             UInt32(bitPattern: openResult)))
            }
            openResult = api.USBDeviceOpenSeize(device)
        } else if Self.verbose {
            print("[transport] USBDeviceOpen succeeded, no seize needed")
        }
        guard openResult == kIOReturnSuccess else { throw TransportError.openFailed(openResult) }
        defer { _ = api.USBDeviceClose(device) }

        try body(device, api)
    }

    /// Matches g810-led's `usleep(1000)` between transfers.
    private static let interReportDelayMicroseconds: UInt32 = 1000

    private func send(
        report: HIDOutputReport,
        to device: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>,
        api: IOUSBDeviceInterface
    ) throws {
        var bytes = report.bytes
        let result = bytes.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            var request = IOUSBDevRequest(
                bmRequestType: 0x21,  // host->device | class | interface
                bRequest: 0x09,       // SET_REPORT
                // High byte 0x02 selects an Output report, low byte is the
                // report ID (0x11 for the 20-byte, 0x12 for the 64-byte one).
                wValue: 0x0200 | UInt16(report.reportID),
                wIndex: Self.ledInterfaceIndex,
                wLength: UInt16(buffer.count),
                pData: buffer.baseAddress,
                wLenDone: 0)
            return api.DeviceRequest(device, &request)
        }
        guard result == kIOReturnSuccess else { throw TransportError.requestFailed(result) }
    }

    // MARK: - IOKit plumbing

    /// Enumerates all USB devices and filters by vendor/product ourselves:
    /// IOKit only honors USB property filters in the matching dictionary
    /// when idVendor *and* idProduct are both set, and silently matches
    /// nothing with idVendor alone — so self-filtering is the reliable route.
    private func findDevice(vendorID: UInt16, productID: UInt16) -> io_service_t? {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let vid = numberProperty(service, kUSBVendorID).map { UInt16(truncatingIfNeeded: $0) }
            let pid = numberProperty(service, kUSBProductID).map { UInt16(truncatingIfNeeded: $0) }
            if vid == vendorID && pid == productID {
                return service // caller releases it
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private func numberProperty(_ service: io_service_t, _ key: String) -> Int? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? NSNumber)?.intValue
    }

    private func deviceInterface(
        for service: io_service_t
    ) -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>? {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let result = IOCreatePlugInInterfaceForService(
            service, Self.deviceUserClientTypeID, Self.plugInInterfaceID, &plugIn, &score)
        guard result == KERN_SUCCESS, let plugIn, let plugInAPI = plugIn.pointee else { return nil }
        defer { _ = plugInAPI.pointee.Release(plugIn) }

        var raw: LPVOID?
        let query = plugInAPI.pointee.QueryInterface(
            plugIn, CFUUIDGetUUIDBytes(Self.deviceInterfaceID100), &raw)
        guard query == S_OK, let raw else { return nil }

        return raw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface>?.self)
    }
}
