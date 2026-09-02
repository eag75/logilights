import Foundation
import IOKit.hid

/// Owns the app's long-lived background state. For now this just logs
/// Logitech HID attach/detach events; `LightingApplier` will hook into
/// `deviceMonitor` once it exists to actually set colors on these events.
final class AppCoordinator: ObservableObject {
    let deviceMonitor = HIDDeviceMonitor(vendorID: LogitechDevices.logitechVendorID)

    init() {
        deviceMonitor.onDeviceMatched = { device in
            let name = device.productName ?? "unknown"
            if let model = device.logitechModel {
                print("Logilights: device attached: \(name) (\(model.rawValue))")
            } else {
                print("Logilights: device attached: \(name) (unsupported model, ignoring)")
            }
        }
        deviceMonitor.onDeviceRemoved = { device in
            print("Logilights: device removed: \(device.productName ?? "unknown")")
        }
        deviceMonitor.start()
    }
}
