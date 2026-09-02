import Foundation
import LogilightsCore

/// Owns the app's long-lived background state: watches for supported
/// Logitech keyboards on the USB bus, keeps track of which models are
/// currently connected (for the UI), and applies each model's stored color
/// whenever a device for it is (re)connected — plus, via
/// `TriggerCoordinator`, on launch (after login) and on wake from sleep.
final class AppCoordinator: ObservableObject {
    let deviceMonitor = USBDeviceMonitor()
    let profileStore = ColorProfileStore()

    /// Models currently connected, for display in the UI.
    @Published private(set) var connectedModels: Set<LogitechKeyboardModel> = []

    private let transport = USBLEDTransport()
    private lazy var triggerCoordinator = TriggerCoordinator { [weak self] in
        self?.applyAllStoredColors()
    }

    init() {
        deviceMonitor.onDeviceAttached = { [weak self] device in
            self?.handleDeviceAttached(device)
        }
        deviceMonitor.onDeviceDetached = { [weak self] device in
            self?.handleDeviceDetached(device)
        }
        deviceMonitor.start()
        refreshConnectedModels()
        triggerCoordinator.start()
    }

    private func handleDeviceAttached(_ device: USBDeviceMonitor.Device) {
        print("Logilights: device attached: \(device.name) (\(device.model.rawValue))")
        connectedModels.insert(device.model)
        apply(to: device.model)
    }

    private func handleDeviceDetached(_ device: USBDeviceMonitor.Device) {
        print("Logilights: device removed: \(device.name)")
        refreshConnectedModels()
    }

    private func refreshConnectedModels() {
        connectedModels = Set(deviceMonitor.connectedDevices().map(\.model))
    }

    private func apply(to model: LogitechKeyboardModel) {
        do {
            try transport.apply(color: profileStore.color(for: model), to: model)
        } catch {
            print("Logilights: could not set color on \(model.rawValue): \(error)")
        }
    }

    /// Re-applies each connected model's stored color. Used after the user
    /// changes a color in the UI, and by `TriggerCoordinator` for the
    /// launch/wake triggers.
    func applyAllStoredColors() {
        for device in deviceMonitor.connectedDevices() {
            apply(to: device.model)
        }
    }

    func setColor(_ color: LogitechColor, for model: LogitechKeyboardModel) {
        profileStore.setColor(color, for: model)
        applyAllStoredColors()
    }
}
