import SwiftUI

@main
struct LogilightsApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Logilights", systemImage: "keyboard") {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
