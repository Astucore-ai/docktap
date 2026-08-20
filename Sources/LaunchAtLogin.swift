import AppKit

enum LaunchAtLogin {
    static let label = "com.astucore.docktap"
    static let appPath = "/Applications/Docktap.app"
    static let binaryPath = appPath + "/Contents/MacOS/Docktap"
    static let helperPath = appPath + "/Contents/Resources/keep-alive.sh"
    static let processName = "Docktap"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled { install() } else { uninstall() }
    }

    static func ensureInstalled() {
        install()
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func writePlist() {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let args: [String]
        if FileManager.default.fileExists(atPath: helperPath) {
            args = [helperPath, processName, binaryPath]
        } else {
            args = [binaryPath]
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": args,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 3,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "AssociatedBundleIdentifiers": ["com.astucore.docktap"],
            "StandardOutPath": logs.appendingPathComponent("Docktap.log").path,
            "StandardErrorPath": logs.appendingPathComponent("Docktap.err.log").path
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
    }

    static func install() {
        writePlist()
        let uid = getuid()
        let domain = "gui/\(uid)"
        _ = run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
        if !isLoaded() {
            let status = run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            if status != 0 {
                DTLog.line("launchctl bootstrap failed status=\(status)")
            }
        }
    }

    static func isLoaded() -> Bool {
        let uid = getuid()
        return run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"]) == 0
    }

    static func uninstall() {
        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static func stopUntilNextLogin() {
        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)", plistURL.path])
        NSApp.terminate(nil)
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
