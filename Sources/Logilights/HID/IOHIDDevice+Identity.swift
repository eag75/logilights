import Foundation
import IOKit.hid

extension IOHIDDevice {
    var vendorID: UInt16? {
        (IOHIDDeviceGetProperty(self, kIOHIDVendorIDKey as CFString) as? NSNumber)?.uint16Value
    }

    var productID: UInt16? {
        (IOHIDDeviceGetProperty(self, kIOHIDProductIDKey as CFString) as? NSNumber)?.uint16Value
    }

    var productName: String? {
        IOHIDDeviceGetProperty(self, kIOHIDProductKey as CFString) as? String
    }

    /// The USB interface number this HID device instance represents. A
    /// single physical Logitech keyboard exposes several IOHIDDevice
    /// instances (one per HID interface) that share the same vendor/product
    /// ID; only one of them accepts the vendor-specific LED reports.
    var primaryUsagePage: Int? {
        (IOHIDDeviceGetProperty(self, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
    }

    var logitechModel: LogitechKeyboardModel? {
        guard let vendorID, let productID else { return nil }
        return LogitechDevices.model(vendorID: vendorID, productID: productID)
    }
}
