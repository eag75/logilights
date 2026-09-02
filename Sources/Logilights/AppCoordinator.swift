import Foundation
import IOKit.hid

/// Owns the app's long-lived background state: watches for Logitech HID
/// devices and applies the configured color whenever one is (re)connected.
///
/// The hardcoded `placeholderColor` is temporary — `ColorProfileStore` will
/// replace it with a per-device, user-configured color, and
/// `TriggerCoordinator` will add the login/wake triggers on top of the
/// attach trigger already wired up here.
final class AppCoordinator: ObservableObject {
    let deviceMonitor = HIDDeviceMonitor(vendorID: LogitechDevices.logitechVendorID)
    private let lightingApplier = LightingApplier()
    private let placeholderColor = LogitechColor(red: 0x00, green: 0x80, blue: 0xff)

    init() {
        deviceMonitor.onDeviceMatched = { [lightingApplier, placeholderColor] device in
            let name = device.productName ?? "unknown"
            guard let model = device.logitechModel else {
                print("Logilights: device attached: \(name) (unsupported model, ignoring)")
                return
            }
            print("Logilights: device attached: \(name) (\(model.rawValue))")
            lightingApplier.apply(color: placeholderColor, to: device)
        }
        deviceMonitor.onDeviceRemoved = { device in
            print("Logilights: device removed: \(device.productName ?? "unknown")")
        }
        deviceMonitor.start()
    }
}
