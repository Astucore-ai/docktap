import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var excludeField: NSTextField?

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        persistExclude()
        window = nil
    }

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Docktap Settings"
        win.delegate = self
        win.center()
        win.contentView = makeContent()
        window = win
    }

    private func makeContent() -> NSView {
        let s = SettingsStore.shared.settings
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))

        var y: CGFloat = 390
        func heading(_ text: String) {
            let f = NSTextField(labelWithString: text)
            f.font = .systemFont(ofSize: 15, weight: .semibold)
            f.frame = NSRect(x: 24, y: y, width: 470, height: 22)
            root.addSubview(f)
            y -= 32
        }
        func note(_ text: String) {
            let f = NSTextField(wrappingLabelWithString: text)
            f.font = .systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            f.frame = NSRect(x: 24, y: y - 16, width: 470, height: 36)
            root.addSubview(f)
            y -= 44
        }

        heading("Behavior")
        let enabled = NSButton(checkboxWithTitle: "Enable Docktap", target: nil, action: nil)
        enabled.state = s.enabled ? .on : .off
        enabled.frame = NSRect(x: 24, y: y, width: 470, height: 22)
        enabled.target = self
        enabled.action = #selector(toggleEnabled(_:))
        root.addSubview(enabled)
        y -= 28

        let login = NSButton(checkboxWithTitle: "Launch at login (keep alive)", target: nil, action: nil)
        login.state = s.launchAtLogin ? .on : .off
        login.frame = NSRect(x: 24, y: y, width: 470, height: 22)
        login.target = self
        login.action = #selector(toggleLogin(_:))
        root.addSubview(login)
        y -= 40

        heading("Click action")
        let action = NSPopUpButton(frame: NSRect(x: 24, y: y, width: 320, height: 26))
        action.addItems(withTitles: [
            "Minimize windows (Windows-like)",
            "Hide the application"
        ])
        action.selectItem(at: s.action == .minimize ? 0 : 1)
        action.target = self
        action.action = #selector(changeAction(_:))
        root.addSubview(action)
        y -= 36
        note("Minimize uses the yellow traffic-light action so the next Dock click restores. Hide is Command-H.")

        heading("When several windows are open")
        let scope = NSPopUpButton(frame: NSRect(x: 24, y: y, width: 320, height: 26))
        scope.addItems(withTitles: [
            "Minimize all visible windows",
            "Minimize only the focused window"
        ])
        scope.selectItem(at: s.scope == .allVisibleWindows ? 0 : 1)
        scope.target = self
        scope.action = #selector(changeScope(_:))
        root.addSubview(scope)
        y -= 48

        heading("Ignore these apps")
        let field = NSTextField(string: s.excludedApps.joined(separator: ", "))
        field.placeholderString = "Finder, com.apple.mail"
        field.frame = NSRect(x: 24, y: y, width: 470, height: 24)
        field.delegate = self
        root.addSubview(field)
        excludeField = field
        y -= 28
        note("Comma-separated names or bundle identifiers. Modifier-clicks (⌘ ⌥ ⌃ ⇧) always pass through to the Dock.")

        return root
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        persistExclude()
    }

    private func persistExclude() {
        let raw = excludeField?.stringValue ?? ""
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        SettingsStore.shared.update { $0.excludedApps = parts }
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        SettingsStore.shared.update { $0.enabled = sender.state == .on }
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        let on = sender.state == .on
        SettingsStore.shared.update { $0.launchAtLogin = on }
        LaunchAtLogin.setEnabled(on)
    }

    @objc private func changeAction(_ sender: NSPopUpButton) {
        SettingsStore.shared.update { $0.action = sender.indexOfSelectedItem == 0 ? .minimize : .hide }
    }

    @objc private func changeScope(_ sender: NSPopUpButton) {
        SettingsStore.shared.update { $0.scope = sender.indexOfSelectedItem == 0 ? .allVisibleWindows : .focusedWindow }
    }
}
