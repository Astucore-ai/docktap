#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

var failures = 0
func pass(_ name: String) { print("PASS  \(name)") }
func fail(_ name: String, _ detail: String) {
    failures += 1
    print("FAIL  \(name) — \(detail)")
}

func axCopy<T>(_ el: AXUIElement, _ attr: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    return value as? T
}

func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success, let value else { return nil }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }
    return value as? Bool
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let posVal: AXValue = axCopy(el, kAXPositionAttribute as String),
          let sizeVal: AXValue = axCopy(el, kAXSizeAttribute as String) else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posVal, .cgPoint, &pos)
    AXValueGetValue(sizeVal, .cgSize, &size)
    return CGRect(origin: pos, size: size)
}

func wait(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

func dockItems() -> [(title: String, url: URL, frame: CGRect, running: Bool)] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        return []
    }
    let root = AXUIElementCreateApplication(dock.processIdentifier)
    var result: [(String, URL, CGRect, Bool)] = []
    var queue: [AXUIElement] = [root]
    var i = 0
    while i < queue.count {
        let el = queue[i]; i += 1
        let sub: String = axCopy(el, kAXSubroleAttribute as String) ?? ""
        if sub == "AXApplicationDockItem" {
            if let title: String = axCopy(el, kAXTitleAttribute as String),
               let url: URL = axCopy(el, "AXURL"),
               let frame = axFrame(el) {
                let running = axBool(el, "AXIsApplicationRunning") ?? false
                result.append((title, url, frame, running))
            }
            continue
        }
        if let kids: [AXUIElement] = axCopy(el, kAXChildrenAttribute as String) {
            queue.append(contentsOf: kids)
        }
    }
    return result
}

func textEditWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    let windows: [AXUIElement] = axCopy(appEl, kAXWindowsAttribute as String) ?? []
    return windows.filter { (axCopy($0, kAXRoleAttribute as String) as String?) == "AXWindow" }
}

func visibleCount(_ windows: [AXUIElement]) -> Int {
    windows.filter { axBool($0, kAXMinimizedAttribute as String) != true }.count
}

func clickQuartz(_ point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        up.post(tap: .cghidEventTap)
    }
}

func launchTextEdit() -> NSRunningApplication? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return nil }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    let sem = DispatchSemaphore(value: 0)
    var app: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { running, _ in
        app = running
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 5)
    wait(0.6)
    return app ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
}

func ensureDocument(_ app: NSRunningApplication) -> AXUIElement? {
    var windows = textEditWindows(app)
    if windows.isEmpty {
        app.activate(options: [.activateIgnoringOtherApps])
        wait(0.25)
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: true) { // N
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
        wait(0.6)
        windows = textEditWindows(app)
    }
    return windows.first
}

func unminimizeAll(_ windows: [AXUIElement]) {
    for w in windows {
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
}

print("Docktap smoke test")
print("AX trusted (this process): \(AXIsProcessTrusted())")
print("listen events: \(CGPreflightListenEventAccess())")

// 1. Process
let procs = NSWorkspace.shared.runningApplications.filter {
    $0.localizedName == "Docktap" || $0.bundleIdentifier == "com.astucore.docktap"
}
if procs.isEmpty { fail("process", "Docktap is not running") }
else { pass("process running (pid \(procs[0].processIdentifier))") }

// 2. Status
let statusURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Docktap/status.json")
wait(1.2)
if let data = try? Data(contentsOf: statusURL),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    let tap = json["eventTapCreated"] as? Bool ?? false
    let ax = json["accessibilityTrusted"] as? Bool ?? false
    let count = json["dockItemCount"] as? Int ?? 0
    let state = json["state"] as? String ?? "?"
    if tap { pass("event tap (\(state))") } else { fail("event tap", "state=\(state) json=\(json)") }
    if ax { pass("Docktap has Accessibility") } else { fail("Docktap Accessibility", "\(json)") }
    if count >= 3 { pass("dock items in status (\(count))") } else { fail("dock items", "count=\(count)") }
} else {
    fail("status.json", "missing at \(statusURL.path)")
}

// 3. Config
let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Docktap/config.json")
if let data = try? Data(contentsOf: configURL),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    if json["enabled"] as? Bool == true { pass("settings.enabled") } else { fail("settings.enabled", "\(json["enabled"] ?? "nil")") }
    if json["action"] as? String == "minimize" { pass("settings.action=minimize") } else { fail("settings.action", "\(json["action"] ?? "nil")") }
} else {
    fail("config", "could not read \(configURL.path)")
}

// 4. Dock AX
let items = dockItems()
if items.contains(where: { $0.title == "Finder" }) { pass("dock lists Finder") }
else { fail("dock lists Finder", "items=\(items.map { $0.title })") }
if let te = items.first(where: { $0.title == "TextEdit" || $0.url.lastPathComponent == "TextEdit.app" }) {
    pass("TextEdit dock tile at \(Int(te.frame.midX)),\(Int(te.frame.midY))")
} else {
    print("INFO  TextEdit not pinned; will appear once launched")
}

// 5. Direct AX minimize / restore (proves window actions work)
guard let app = launchTextEdit() else {
    fail("launch TextEdit", "openApplication failed")
    print("\n\(failures) FAILED")
    exit(1)
}
pass("launched TextEdit pid \(app.processIdentifier)")
guard let win = ensureDocument(app) else {
    fail("TextEdit window", "no AX window")
    print("\n\(failures) FAILED")
    exit(1)
}
unminimizeAll(textEditWindows(app))
wait(0.3)
app.activate(options: [.activateIgnoringOtherApps])
wait(0.3)
if visibleCount(textEditWindows(app)) == 0 {
    fail("precondition visible window", "all minimized before click test")
} else {
    pass("TextEdit has a visible window")
}

AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
wait(0.45)
if axBool(win, kAXMinimizedAttribute as String) == true { pass("AX minimize") }
else { fail("AX minimize", "window did not minimize") }
AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
wait(0.45)
if axBool(win, kAXMinimizedAttribute as String) != true { pass("AX restore") }
else { fail("AX restore", "window stayed minimized") }

// 6. Click the focused app's Dock icon → should minimize (Docktap)
unminimizeAll(textEditWindows(app))
wait(0.25)
app.activate(options: [.activateIgnoringOtherApps])
wait(0.45)
let items2 = dockItems()
guard let tile = items2.first(where: { $0.url.lastPathComponent == "TextEdit.app" }) else {
    fail("TextEdit dock tile", "not in dock after launch")
    print("\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
let clickPoint = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
print("INFO  clicking TextEdit dock tile at (\(Int(clickPoint.x)), \(Int(clickPoint.y))) while frontmost")
clickQuartz(clickPoint)
wait(0.7)
let afterClickMin = axBool(win, kAXMinimizedAttribute as String) == true || visibleCount(textEditWindows(app)) == 0
if afterClickMin { pass("click focused Dock icon minimized TextEdit") }
else { fail("click minimize", "window still visible after dock click") }

// 7. Click again → restore (native Dock; Docktap must not re-minimize)
print("INFO  clicking TextEdit dock tile again to restore")
clickQuartz(clickPoint)
wait(0.8)
let restored = axBool(win, kAXMinimizedAttribute as String) != true && visibleCount(textEditWindows(app)) > 0
if restored { pass("second click restored TextEdit") }
else { fail("click restore", "window did not come back (minimized=\(String(describing: axBool(win, kAXMinimizedAttribute as String))))") }

unminimizeAll(textEditWindows(app))
wait(0.2)

print("\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
exit(failures == 0 ? 0 : 1)
