import Foundation

enum DTAction: String, Codable, CaseIterable {
    case minimize
    case hide
}

enum DTScope: String, Codable, CaseIterable {
    case allVisibleWindows
    case focusedWindow
}

struct DTSettings: Codable, Equatable {
    var enabled: Bool = true
    var launchAtLogin: Bool = true
    var action: DTAction = .minimize
    var scope: DTScope = .allVisibleWindows
    var excludedApps: [String] = []

    static let `default` = DTSettings()
}

extension Notification.Name {
    static let dtSettingsChanged = Notification.Name("com.astucore.docktap.settingsChanged")
    static let dtEnabledChanged = Notification.Name("com.astucore.docktap.enabledChanged")
}

final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var settings: DTSettings
    private let url: URL
    private let queue = DispatchQueue(label: "com.astucore.docktap.settings")

    var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Docktap", isDirectory: true)
    }

    private init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Docktap/config.json")
        settings = Self.load(from: url) ?? .default
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        save()
    }

    func update(_ mutate: (inout DTSettings) -> Void) {
        let before = settings
        mutate(&settings)
        if settings == before { return }
        save()
        NotificationCenter.default.post(name: .dtSettingsChanged, object: nil)
        if before.enabled != settings.enabled {
            NotificationCenter.default.post(name: .dtEnabledChanged, object: nil)
        }
    }

    func isExcluded(name: String?, bundleId: String?) -> Bool {
        let tokens = settings.excludedApps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return false }
        let name = (name ?? "").lowercased()
        let bid = (bundleId ?? "").lowercased()
        return tokens.contains { token in
            name == token || bid == token || name.contains(token) || bid.contains(token)
        }
    }

    private func save() {
        queue.sync {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(settings) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func load(from url: URL) -> DTSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DTSettings.self, from: data)
    }
}
