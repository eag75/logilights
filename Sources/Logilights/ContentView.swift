import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logilights")
                .font(.headline)

            if coordinator.connectedModels.isEmpty {
                Text("Keine Geräte erkannt.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(coordinator.connectedModels).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { model in
                    DeviceColorRow(model: model, coordinator: coordinator)
                }
            }

            Divider()

            Button("Jetzt anwenden") {
                coordinator.applyAllStoredColors()
            }
            .disabled(coordinator.connectedModels.isEmpty)

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }
}

private struct DeviceColorRow: View {
    let model: LogitechKeyboardModel
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ColorPicker(
            model.rawValue,
            selection: Binding(
                get: { coordinator.profileStore.color(for: model).swiftUIColor },
                set: { coordinator.setColor(LogitechColor($0), for: model) }
            ),
            supportsOpacity: false
        )
    }
}
