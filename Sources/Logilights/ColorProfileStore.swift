import Foundation

/// The persisted set of per-model colors, stored as JSON.
struct ColorProfile: Codable {
    var colorsByModel: [String: LogitechColor] = [:]
}

/// Reads/writes the user's chosen LED color per keyboard model to
/// `~/Library/Application Support/Logilights/profile.json`. Colors are keyed
/// by model (not device serial number), matching g810-led's own model-based
/// granularity — the practical unit for "one color for the whole keyboard".
final class ColorProfileStore: ObservableObject {
    static let defaultColor = LogitechColor(red: 0x00, green: 0x80, blue: 0xff)

    @Published private(set) var profile: ColorProfile

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.profile = Self.load(from: url)
    }

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Logilights", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("profile.json")
    }

    private static func load(from url: URL) -> ColorProfile {
        guard let data = try? Data(contentsOf: url) else { return ColorProfile() }
        return (try? JSONDecoder().decode(ColorProfile.self, from: data)) ?? ColorProfile()
    }

    func color(for model: LogitechKeyboardModel) -> LogitechColor {
        profile.colorsByModel[model.rawValue] ?? Self.defaultColor
    }

    func setColor(_ color: LogitechColor, for model: LogitechKeyboardModel) {
        profile.colorsByModel[model.rawValue] = color
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
