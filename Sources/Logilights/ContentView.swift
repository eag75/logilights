import SwiftUI
import LogilightsCore

struct ContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logilights")
                .font(.headline)

            if coordinator.connectedModels.isEmpty {
                Text("No devices detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(coordinator.connectedModels).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { model in
                    DeviceColorRow(model: model, coordinator: coordinator)
                }
            }

            Divider()

            Button("Apply now") {
                coordinator.applyAllStoredColors()
            }
            .disabled(coordinator.connectedModels.isEmpty)

            LoginItemRow(coordinator: coordinator)

            Divider()

            Button("Quit") {
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
                "Start at login",
                isOn: Binding(
                    get: { coordinator.loginItemState.isOn },
                    set: { coordinator.setLaunchAtLogin($0) }
                )
            )
            .disabled(coordinator.loginItemState == .unavailable)

            if let error = coordinator.loginItemError {
                Hint("Failed: \(error)")
            } else {
                switch coordinator.loginItemState {
                case .requiresApproval:
                    Hint("Still needs to be approved under System Settings → "
                         + "General → Login Items.")
                case .unavailable:
                    Hint("Only available when Logilights runs as an app bundle.")
                case .enabled, .notRegistered:
                    EmptyView()
                }
            }
        }
    }
}

private struct Hint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
