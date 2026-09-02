import Foundation
import LogilightsCore
import ServiceManagement

/// Wraps `SMAppService.mainApp` for "start at login".
///
/// This only works from a real, signed .app bundle — under `swift run` the
/// status stays `.notFound`. macOS may also report `.requiresApproval`,
/// meaning the item is registered but the user still has to enable it under
/// System Settings → General → Login Items.
enum LoginItem {
    enum State: String {
        case enabled
        case requiresApproval
        case notRegistered
        case unavailable

        var isOn: Bool { self == .enabled }
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> State {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.lifecycle.error("Login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        let result = state
        Log.lifecycle.info("Login item state: \(result.rawValue, privacy: .public)")
        return result
    }
}
