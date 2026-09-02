import Foundation
import IOKit.hid

extension IOHIDDevice {
    public var vendorID: UInt16? {
        (IOHIDDeviceGetProperty(self, kIOHIDVendorIDKey as CFString) as? NSNumber)?.uint16Value
    }

    public var productID: UInt16? {
        (IOHIDDeviceGetProperty(self, kIOHIDProductIDKey as CFString) as? NSNumber)?.uint16Value
    }

    public var productName: String? {
        IOHIDDeviceGetProperty(self, kIOHIDProductKey as CFString) as? String
    }

    /// A single physical Logitech keyboard exposes several IOHIDDevice
    /// instances (one per HID interface) that share the same vendor/product
    /// ID; only the vendor-specific one (usage page 0xFF00) accepts the LED
    /// reports, so this is useful for diagnostics.
    public var primaryUsagePage: Int? {
        (IOHIDDeviceGetProperty(self, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
    }

    public var primaryUsage: Int? {
        (IOHIDDeviceGetProperty(self, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
    }

    public var logitechModel: LogitechKeyboardModel? {
        guard let vendorID, let productID else { return nil }
        return LogitechDevices.model(vendorID: vendorID, productID: productID)
    }
}
