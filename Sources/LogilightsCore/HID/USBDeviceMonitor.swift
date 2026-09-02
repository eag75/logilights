import Foundation
import IOKit
import IOKit.usb

/// Watches USB attach/detach events for supported Logitech keyboards.
///
/// This deliberately uses IOKit's USB notifications rather than
/// `IOHIDManager`: the LED writes go over `USBLEDTransport` anyway, and
/// staying on the USB stack means Logilights needs no Input Monitoring
/// (TCC) authorization at all.
public final class USBDeviceMonitor {
    public struct Device: Equatable {
        public let vendorID: UInt16
        public let productID: UInt16
        public let model: LogitechKeyboardModel
        public let name: String
    }

    public var onDeviceAttached: ((Device) -> Void)?
    public var onDeviceDetached: ((Device) -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var isRunning = false

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // Match every USB device and filter in `makeDevice` instead of
        // putting idVendor into the matching dictionary: IOKit only honors
        // those USB property filters when idVendor *and* idProduct are both
        // present, and silently matches nothing with idVendor alone.
        let matching = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary

        // The matching dictionary is consumed by each call, so pass a copy.
        IOServiceAddMatchingNotification(
            port, kIOMatchedNotification,
            (matching.copy() as! NSDictionary),
            { context, iterator in
                guard let context else { return }
                let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.drain(iterator, attached: true)
            },
            context, &matchedIterator)

        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification,
            (matching.copy() as! NSDictionary),
            { context, iterator in
                guard let context else { return }
                let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.drain(iterator, attached: false)
            },
            context, &terminatedIterator)

        // Both iterators must be drained once to arm the notifications; this
        // also delivers the devices that are already connected.
        drain(matchedIterator, attached: true)
        drain(terminatedIterator, attached: false)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if matchedIterator != 0 { IOObjectRelease(matchedIterator); matchedIterator = 0 }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator); terminatedIterator = 0 }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        notificationPort = nil
    }

    /// Currently connected supported keyboards.
    public func connectedDevices() -> [Device] {
        // Filtering happens in `makeDevice`; see `start()` for why the
        // matching dictionary carries no idVendor filter.
        let matching = IOServiceMatching(kIOUSBDeviceClassName)

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [Device] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let device = makeDevice(from: service) { devices.append(device) }
            IOObjectRelease(service)
        }
        return devices
    }

    private func drain(_ iterator: io_iterator_t, attached: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let device = makeDevice(from: service) {
                if attached {
                    onDeviceAttached?(device)
                } else {
                    onDeviceDetached?(device)
                }
            }
            IOObjectRelease(service)
        }
    }

    private func makeDevice(from service: io_service_t) -> Device? {
        guard let vendorID = numberProperty(service, kUSBVendorID).map({ UInt16(truncatingIfNeeded: $0) }),
              let productID = numberProperty(service, kUSBProductID).map({ UInt16(truncatingIfNeeded: $0) }),
              let model = LogitechDevices.model(vendorID: vendorID, productID: productID)
        else { return nil }

        let name = stringProperty(service, "USB Product Name") ?? model.rawValue
        return Device(vendorID: vendorID, productID: productID, model: model, name: name)
    }

    private func numberProperty(_ service: io_service_t, _ key: String) -> Int? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? NSNumber)?.intValue
    }

    private func stringProperty(_ service: io_service_t, _ key: String) -> String? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }
}
