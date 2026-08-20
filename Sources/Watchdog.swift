import AppKit
import CoreGraphics

final class Watchdog {
    static let shared = Watchdog()
    private var timer: Timer?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if SettingsStore.shared.settings.launchAtLogin {
            if !LaunchAtLogin.isLoaded() {
                DTLog.line("watchdog: LaunchAgent missing — reinstalling")
                LaunchAtLogin.install()
            }
        }
        if SettingsStore.shared.settings.enabled, AX.isTrusted(prompt: false) {
            ClickMonitor.shared.start()
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }
}
