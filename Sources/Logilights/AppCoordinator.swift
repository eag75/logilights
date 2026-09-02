import Foundation
import IOKit.hid
import LogilightsCore

/// Owns the app's long-lived background state: watches for Logitech HID
/// devices, keeps track of which supported models are currently connected
/// (for the UI), and applies each model's stored color whenever a device
/// for it is (re)connected — plus, via `TriggerCoordinator`, on launch
/// (after login) and on wake from sleep.
final class AppCoordinator: ObservableObject {
    let deviceMonitor = HIDDeviceMonitor(vendorID: LogitechDevices.logitechVendorID)
    let profileStore = ColorProfileStore()

    /// Models currently seen connected, for display in the UI. A model can
    /// appear more than once transiently (one physical keyboard exposes
    /// several HID interfaces); we only care about presence, not count.
    @Published private(set) var connectedModels: Set<LogitechKeyboardModel> = []

    private let lightingApplier = LightingApplier()
    private lazy var triggerCoordinator = TriggerCoordinator { [weak self] in
        self?.applyAllStoredColors()
    }

    init() {
        deviceMonitor.onDeviceMatched = { [weak self] device in
            self?.handleDeviceMatched(device)
        }
        deviceMonitor.onDeviceRemoved = { [weak self] device in
            self?.handleDeviceRemoved(device)
        }
        deviceMonitor.start()
        refreshConnectedModels()
        triggerCoordinator.start()
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        let name = device.productName ?? "unknown"
        guard let model = device.logitechModel else {
            print("Logilights: device attached: \(name) (unsupported model, ignoring)")
            return
        }
        print("Logilights: device attached: \(name) (\(model.rawValue))")
        connectedModels.insert(model)
        applyStoredColor(to: device, model: model)
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        print("Logilights: device removed: \(device.productName ?? "unknown")")
        refreshConnectedModels()
    }

    private func refreshConnectedModels() {
        connectedModels = Set(deviceMonitor.connectedDevices().compactMap(\.logitechModel))
    }

    private func applyStoredColor(to device: IOHIDDevice, model: LogitechKeyboardModel) {
        let color = profileStore.color(for: model)
        lightingApplier.apply(color: color, to: device)
    }

    /// Re-applies each connected model's stored color to every matching
    /// device. Used after the user changes a color in the UI, and by
    /// `TriggerCoordinator` for the launch/wake triggers.
    func applyAllStoredColors() {
        for device in deviceMonitor.connectedDevices() {
            guard let model = device.logitechModel else { continue }
            applyStoredColor(to: device, model: model)
        }
    }

    func setColor(_ color: LogitechColor, for model: LogitechKeyboardModel) {
        profileStore.setColor(color, for: model)
        applyAllStoredColors()
    }
}
