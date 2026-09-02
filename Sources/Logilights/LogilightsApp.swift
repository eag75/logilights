import SwiftUI

@main
struct LogilightsApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Logilights", systemImage: "keyboard") {
            ContentView()
        }
    }
}
