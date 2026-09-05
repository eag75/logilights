import AppKit
import Foundation
import LogilightsCore

/// Wires up the moments lighting should be (re)applied, beyond the device
/// attach trigger `AppCoordinator` already handles directly:
///
/// - App launch — "at computer start" in the sense agreed with the user:
///   after login, once Logilights starts (see `LoginItem`).
/// - Wake from sleep (`NSWorkspace.didWakeNotification`).
///
/// Registering as a login item is *not* done here — that is a user-facing
/// setting, toggled in the menu (`LoginItem`), so the app doesn't silently
/// add itself to the user's login items on first launch.
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
        Log.lifecycle.info("Applying colors on launch")
        onTrigger()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [onTrigger] _ in
            Log.lifecycle.info("Woke from sleep — reapplying colors")
            onTrigger()
        }
    }
}
