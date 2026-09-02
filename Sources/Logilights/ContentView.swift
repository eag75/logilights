import SwiftUI
import LogilightsCore

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

            LoginItemRow(coordinator: coordinator)

            Divider()

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
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

private struct LoginItemRow: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Beim Anmelden starten",
                isOn: Binding(
                    get: { coordinator.loginItemState.isOn },
                    set: { coordinator.setLaunchAtLogin($0) }
                )
            )
            .disabled(coordinator.loginItemState == .unavailable)

            switch coordinator.loginItemState {
            case .requiresApproval:
                Text("Muss noch unter Systemeinstellungen → Allgemein → "
                     + "Anmeldeobjekte freigegeben werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Text("Nur verfügbar, wenn Logilights als App-Bundle läuft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .enabled, .notRegistered:
                EmptyView()
            }
        }
    }
}
