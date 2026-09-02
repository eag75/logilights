import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logilights")
                .font(.headline)
            Text("Keine Geräte erkannt.")
                .foregroundStyle(.secondary)
            Divider()
            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 220)
    }
}
