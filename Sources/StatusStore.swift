import Foundation
import CoreGraphics

struct DTStatus: Codable {
    var state: String
    var pid: Int32
    var version: String
    var accessibilityTrusted: Bool
    var inputMonitoringGranted: Bool
    var eventTapCreated: Bool
    var dockItemCount: Int
    var lastError: String?
    var lastAction: String?
    var lastUpdatedAt: String
}

enum StatusStore {
    static var url: URL {
        SettingsStore.shared.supportDirectory.appendingPathComponent("status.json")
    }

    static func write(
        state: String,
        eventTapCreated: Bool,
        dockItemCount: Int = 0,
        lastError: String? = nil,
        lastAction: String? = nil
    ) {
        let payload = DTStatus(
            state: state,
            pid: ProcessInfo.processInfo.processIdentifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            accessibilityTrusted: AX.isTrusted(prompt: false),
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            eventTapCreated: eventTapCreated,
            dockItemCount: dockItemCount,
            lastError: lastError,
            lastAction: lastAction,
            lastUpdatedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try FileManager.default.createDirectory(
                at: SettingsStore.shared.supportDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            DTLog.line("failed to write status: \(error)")
        }
    }
}
