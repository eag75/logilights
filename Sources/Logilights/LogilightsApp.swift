import SwiftUI
import LogilightsCore

@main
struct LogilightsApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        // Line-buffer stdout so `swift run Logilights > log` shows progress
        // live instead of only flushing when the process exits. (A bundled
        // .app has no stdout to speak of — that path uses os_log, see `Log`.)
        setvbuf(stdout, nil, _IOLBF, 0)
        LogilightsApp.handleLoginItemFlags()
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Logilights", systemImage: "keyboard") {
            ContentView()
                .environmentObject(coordinator)
        }
        // Without this the content is rendered as an AppKit *menu*, which can
        // only show menu-shaped items: Text, Button, Toggle and Divider come
        // out fine, but a ColorPicker or any custom-drawn view silently
        // occupies blank space. The window style gives a real popover where
        // arbitrary SwiftUI works.
        .menuBarExtraStyle(.window)
    }

    /// Lets the login item registration be driven from the command line,
    /// which is both scriptable and the only way to exercise this path in
    /// automated testing (SMAppService acts on the running bundle itself,
    /// so a separate CLI tool cannot stand in for it).
    ///
    ///   Logilights.app/Contents/MacOS/Logilights --login-item status
    ///   …                                        --login-item enable
    ///   …                                        --login-item disable
    private static func handleLoginItemFlags() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--login-item") else { return }

        let action = index + 1 < arguments.count ? arguments[index + 1] : "status"
        let state: LoginItem.State
        switch action {
        case "enable":
            state = LoginItem.setEnabled(true)
        case "disable":
            state = LoginItem.setEnabled(false)
        default:
            state = LoginItem.state
        }

        print("login-item: \(state.rawValue)")
        Log.lifecycle.info("login-item \(action, privacy: .public) -> \(state.rawValue, privacy: .public)")
        exit(0)
    }
}
