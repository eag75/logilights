import IOKit.hid
import Foundation

/// Watches USB HID device attach/detach events for a given vendor, using
/// IOKit's `IOHIDManager`. This is the macOS-native equivalent of what
/// g810-led does with libusb hotplug callbacks on Linux — IOHIDManager is
/// used here instead of libusb because macOS's built-in HID driver already
/// owns these interfaces, and libusb can't reliably claim them on macOS
/// (see plan notes / README for details).
public final class HIDDeviceMonitor {
    public var onDeviceMatched: ((IOHIDDevice) -> Void)?
    public var onDeviceRemoved: ((IOHIDDevice) -> Void)?

    private let manager: IOHIDManager
    private var isRunning = false

    public init(vendorID: UInt16) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey: Int(vendorID)]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().onDeviceMatched?(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().onDeviceRemoved?(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// All currently connected devices matching the vendor filter, e.g. to
    /// (re-)apply lighting right after login or after waking from sleep.
    public func connectedDevices() -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }
}
