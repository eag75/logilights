import Foundation
import LogilightsCore
import ServiceManagement

/// Wraps `SMAppService.mainApp` for "start at login".
///
/// This only means anything when we actually run from a .app bundle — under
/// `swift run` the executable sits loose in `.build`, and there is nothing
/// for `SMAppService` to register. macOS may also report `.requiresApproval`,
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

    /// Whether we are running from a real .app bundle at all. Checked
    /// explicitly rather than inferred from `SMAppService`'s status, because
    /// that status alone cannot tell the two situations apart (see below).
    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var state: State {
        guard isBundled else { return .unavailable }

        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        // A bundle that has never been registered reports `.notFound` rather
        // than `.notRegistered` (and keeps doing so for a while after an
        // unregister). From a real .app that simply means "off" — calling
        // `register()` from here works. Only the non-bundled case above is
        // genuinely unavailable.
        case .notFound: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    /// Set when the last `setEnabled` call failed, so the UI can say why
    /// instead of just silently snapping the toggle back.
    private(set) static var lastError: String?

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> State {
        lastError = nil
        guard isBundled else { return .unavailable }

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
            Log.lifecycle.error("Login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }

        let result = state
        Log.lifecycle.info("Login item state: \(result.rawValue, privacy: .public)")
        return result
    }
}
