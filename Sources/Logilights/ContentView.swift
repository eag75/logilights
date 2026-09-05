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
        .frame(width: 260)
    }
}

private struct DeviceColorRow: View {
    let model: LogitechKeyboardModel
    @ObservedObject var coordinator: AppCoordinator

    /// One-click colors, so the common cases do not need the system color
    /// panel. Deliberately saturated: the keyboard's LEDs wash out pastels.
    private static let presets: [LogitechColor] = [
        LogitechColor(red: 0xff, green: 0x00, blue: 0x00),
        LogitechColor(red: 0xff, green: 0x60, blue: 0x00),
        LogitechColor(red: 0xff, green: 0xd0, blue: 0x00),
        LogitechColor(red: 0x00, green: 0xd0, blue: 0x20),
        LogitechColor(red: 0x00, green: 0x80, blue: 0xff),
        LogitechColor(red: 0x80, green: 0x00, blue: 0xff),
        LogitechColor(red: 0xff, green: 0x00, blue: 0x90),
        LogitechColor(red: 0xff, green: 0xff, blue: 0xff),
    ]

    private var current: LogitechColor {
        coordinator.profileStore.color(for: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.rawValue.uppercased())
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(current.hexString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            ColorPicker(
                "Custom color",
                selection: Binding(
                    get: { current.swiftUIColor },
                    set: { coordinator.setColor(LogitechColor($0), for: model) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.self) { preset in
                    PresetSwatch(
                        color: preset,
                        isSelected: preset == current,
                        action: { coordinator.setColor(preset, for: model) })
                }
            }
        }
    }
}

/// A single tappable color square.
private struct PresetSwatch: View {
    let color: LogitechColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.swiftUIColor)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.15),
                                      lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(color.hexString)
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
