import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var accessibilityTimer: Timer?
    private var welcome: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DTLog.line("launch bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath) axAPI=\(AXIsProcessTrusted()) ax=\(AX.isTrusted(prompt: false)) listen=\(CGPreflightListenEventAccess())")

        buildStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .dtSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enabledChanged), name: .dtEnabledChanged, object: nil)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handlePing),
            name: Notification.Name("com.astucore.docktap.ping"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSelfTest(_:)),
            name: Notification.Name("com.astucore.docktap.selftest"),
            object: nil
        )

        if SettingsStore.shared.settings.launchAtLogin {
            LaunchAtLogin.ensureInstalled()
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        startEngine()
        if AX.isTrusted(prompt: false) {
            if !UserDefaults.standard.bool(forKey: "DTDidShowWelcome") {
                showWelcome()
            }
        } else {
            showAccessibilityHelp()
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.startEngine()
                if AX.isTrusted(prompt: false) {
                    self?.accessibilityTimer?.invalidate()
                    self?.accessibilityTimer = nil
                    self?.welcome?.orderOut(nil)
                    if !UserDefaults.standard.bool(forKey: "DTDidShowWelcome") {
                        self?.showWelcome()
                    }
                    self?.rebuildMenu()
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClickMonitor.shared.stop()
        DTLog.line("terminate")
    }

    private func startEngine() {
        if SettingsStore.shared.settings.enabled {
            ClickMonitor.shared.start()
        }
        rebuildMenu()
    }

    @objc private func enabledChanged() {
        if SettingsStore.shared.settings.enabled {
            ClickMonitor.shared.start()
        } else {
            ClickMonitor.shared.stop()
        }
        rebuildMenu()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Docktap")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Docktap"
        }
        statusItem = item
        rebuildMenu()
    }

    @objc private func rebuildMenu() {
        let menu = NSMenu()
        let enabled = SettingsStore.shared.settings.enabled
        let toggle = NSMenuItem(
            title: enabled ? "Docktap is On" : "Docktap is Off",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.state = enabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)

        let ax = AX.isTrusted(prompt: false)
        if !ax {
            let item = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !CGPreflightListenEventAccess() {
            let item = NSMenuItem(title: "Grant Input Monitoring Permission…", action: #selector(openInputMonitoring), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if ax && !ClickMonitor.shared.isTapInstalled && enabled {
            let item = NSMenuItem(title: "Waiting for event tap…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login (Keep Alive)", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SettingsStore.shared.settings.launchAtLogin ? .on : .off
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Stop until next login", action: #selector(stopUntilLogin), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit (LaunchAgent will restart)", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        if let button = statusItem?.button {
            button.appearsDisabled = !enabled || !ax
        }
    }

    @objc private func toggleEnabled() {
        SettingsStore.shared.update { $0.enabled.toggle() }
        enabledChanged()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleLogin() {
        let next = !SettingsStore.shared.settings.launchAtLogin
        SettingsStore.shared.update { $0.launchAtLogin = next }
        LaunchAtLogin.setEnabled(next)
        rebuildMenu()
    }

    @objc private func stopUntilLogin() {
        LaunchAtLogin.stopUntilNextLogin()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibility() {
        _ = AX.isTrusted(prompt: true)
        openPrivacyPane("Privacy_Accessibility")
    }

    @objc private func openInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handlePing() {
        StatusStore.write(
            state: ClickMonitor.shared.isTapInstalled ? "OK" : "NO_TAP",
            eventTapCreated: ClickMonitor.shared.isTapInstalled,
            dockItemCount: DockCache.shared.currentItems.count,
            lastAction: "pong"
        )
        DTLog.line("ping → pong tap=\(ClickMonitor.shared.isTapInstalled)")
    }

    @objc private func handleSelfTest(_ note: Notification) {
        let bundle = note.object as? String ?? "com.apple.TextEdit"
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        guard let app = apps.first else {
            DTLog.line("selftest: no running app \(bundle)")
            return
        }
        let n = WindowActions.minimize(pid: app.processIdentifier, scope: SettingsStore.shared.settings.scope)
        DTLog.line("selftest minimize \(bundle) → \(n)")
        StatusStore.write(
            state: ClickMonitor.shared.isTapInstalled ? "OK" : "NO_TAP",
            eventTapCreated: ClickMonitor.shared.isTapInstalled,
            dockItemCount: DockCache.shared.currentItems.count,
            lastAction: "selftest \(bundle) minimize \(n)"
        )
    }

    private func showAccessibilityHelp() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Docktap needs Accessibility"
        win.center()
        let view = NSView(frame: win.contentView!.bounds)
        let text = NSTextField(wrappingLabelWithString: "Docktap needs Accessibility (and Input Monitoring on some Macs) so it can see Dock clicks and minimize windows.\n\n1. Open System Settings → Privacy & Security → Accessibility\n2. Enable Docktap\n3. This window closes once permission is granted.")
        text.frame = NSRect(x: 20, y: 70, width: 500, height: 150)
        let button = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibility))
        button.frame = NSRect(x: 150, y: 20, width: 240, height: 32)
        view.addSubview(text)
        view.addSubview(button)
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcome = win
        _ = AX.isTrusted(prompt: true)
    }

    private func showWelcome() {
        UserDefaults.standard.set(true, forKey: "DTDidShowWelcome")
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Docktap is running"
        win.center()
        let text = NSTextField(wrappingLabelWithString: "Click a Dock icon the Windows way:\n\n• Focused app, windows visible → minimize\n• Click the same icon again → restore\n• Any other app’s icon → switch as usual\n\n⌘ / ⌥ / ⌃ / ⇧ clicks still go to the Dock. Docktap lives in the menu bar.")
        text.frame = NSRect(x: 20, y: 60, width: 500, height: 160)
        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSettings))
        button.frame = NSRect(x: 170, y: 16, width: 200, height: 32)
        let view = NSView(frame: win.contentView!.bounds)
        view.addSubview(text)
        view.addSubview(button)
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcome = win
    }
}
