import AppKit
import Foundation
import ServiceManagement

/// Wires up the moments lighting should be (re)applied, beyond the device
/// attach trigger `AppCoordinator` already handles directly:
///
/// - App launch, i.e. "beim Rechnerstart" in the sense agreed with the user:
///   after login, once `Logilights` (registered as a login item) starts.
///   IOHIDManager actually delivers a "matched" callback for already-
///   connected devices too when the manager is opened, so this is largely
///   covered by the attach path already — calling `onTrigger` here as well
///   just makes it explicit and resilient to IOKit timing quirks.
/// - Wake from sleep (`NSWorkspace.didWakeNotification`).
final class TriggerCoordinator {
    private let onTrigger: () -> Void
    private var wakeObserver: NSObjectProtocol?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func start() {
        registerAsLoginItem()
        onTrigger()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [onTrigger] _ in
            onTrigger()
        }
    }

    /// Only takes effect once the app is packaged/signed as a proper .app
    /// bundle (SMAppService needs that); running via `swift run` during
    /// development will log and no-op here, which is expected.
    private func registerAsLoginItem() {
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Logilights: could not register as login item: \(error)")
        }
    }
}
