import Foundation
import IOKit.hid

/// Sends the byte-encoded reports from `LogitechColorProtocol` to an actual
/// HID device via `IOHIDDeviceSetReport`. This is the only place that
/// touches real hardware; everything upstream of it (`LogitechColorProtocol`)
/// is pure and unit-tested without a device attached.
///
/// Note: a single physical keyboard exposes multiple HID interfaces that all
/// share the same vendor/product ID, so `HIDDeviceMonitor` will hand us one
/// `IOHIDDevice` per interface. Only the vendor-specific interface accepts
/// these reports — sending to the wrong interface fails harmlessly (logged,
/// not thrown), so it's safe to call `apply` on every matched device.
public final class LightingApplier {
    public init() {}

    @discardableResult
    public func apply(color: LogitechColor, to device: IOHIDDevice) -> Bool {
        guard let model = device.logitechModel else { return false }

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            // Expected on interfaces this app doesn't need (e.g. the boot
            // keyboard interface), and possibly on all interfaces if the
            // user hasn't granted Input Monitoring permission yet.
            return false
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: color)
        var allSucceeded = !reports.isEmpty
        for report in reports {
            // report.bytes is always non-empty (padded to 20/64 bytes), so
            // baseAddress is never nil here.
            let result = report.bytes.withUnsafeBufferPointer { buffer -> IOReturn in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(report.reportID),
                    buffer.baseAddress!,
                    buffer.count
                )
            }
            if result != kIOReturnSuccess {
                print("Logilights: report 0x\(String(report.reportID, radix: 16)) failed (IOReturn \(result))")
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}
