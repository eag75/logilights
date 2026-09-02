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

    /// Whether Logilights is registered to start at login.
    @Published private(set) var loginItemState: LoginItem.State = .unavailable

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
        loginItemState = LoginItem.state
        triggerCoordinator.start()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemState = LoginItem.setEnabled(enabled)
    }

    private func handleDeviceAttached(_ device: USBDeviceMonitor.Device) {
        Log.devices.info("Attached: \(device.name, privacy: .public) (\(device.model.rawValue, privacy: .public))")
        connectedModels.insert(device.model)
        apply(to: device.model)
    }

    private func handleDeviceDetached(_ device: USBDeviceMonitor.Device) {
        Log.devices.info("Removed: \(device.name, privacy: .public)")
        refreshConnectedModels()
    }

    private func refreshConnectedModels() {
        connectedModels = Set(deviceMonitor.connectedDevices().map(\.model))
    }

    private func apply(to model: LogitechKeyboardModel) {
        do {
            try transport.apply(color: profileStore.color(for: model), to: model)
            Log.lighting.info("Applied color to \(model.rawValue, privacy: .public)")
        } catch {
            Log.lighting.error("Could not set color on \(model.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
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
