import SwiftUI
import LogilightsCore

@main
struct LogilightsApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        // Line-buffer stdout so `swift run Logilights > log` shows progress
        // live instead of only flushing when the process exits.
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Logilights", systemImage: "keyboard") {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
