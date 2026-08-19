import AppKit
import ApplicationServices

enum WindowActions {
    private static let skipSubroles: Set<String> = [
        "AXUnknown",
        "AXPictureInPictureWindow",
        "AXFloatingWindow",
        "AXSystemDialog",
        "AXDialog",
        "AXPanel"
    ]

    static func hasVisibleMinimizableWindow(pid: pid_t) -> Bool {
        !visibleMinimizableWindows(pid: pid).isEmpty
    }

    static func visibleMinimizableWindows(pid: pid_t) -> [AXUIElement] {
        candidates(pid: pid).filter { isMinimizableVisible($0) }
    }

    static func minimize(pid: pid_t, scope: DTScope) -> Int {
        let targets: [AXUIElement]
        switch scope {
        case .focusedWindow:
            if let focused = AX.focusedWindow(for: pid), isMinimizableVisible(focused) {
                targets = [focused]
            } else if let main = AX.mainWindow(for: pid), isMinimizableVisible(main) {
                targets = [main]
            } else {
                targets = Array(visibleMinimizableWindows(pid: pid).prefix(1))
            }
        case .allVisibleWindows:
            targets = visibleMinimizableWindows(pid: pid)
        }
        var count = 0
        for window in targets {
            if minimize(window) { count += 1 }
        }
        return count
    }

    static func hide(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        return app.hide()
    }

    static func restoreMinimized(pid: pid_t) -> Int {
        var count = 0
        for window in AX.windows(for: pid) where AX.isMinimized(window) {
            if AX.setBool(window, kAXMinimizedAttribute as String, false) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                count += 1
            }
        }
        return count
    }

    @discardableResult
    static func minimize(_ window: AXUIElement) -> Bool {
        if AX.setBool(window, kAXMinimizedAttribute as String, true) {
            return true
        }
        if let button = AX.element(window, kAXMinimizeButtonAttribute as String) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                return true
            }
        }
        return false
    }

    private static func candidates(pid: pid_t) -> [AXUIElement] {
        let focused = AX.focusedWindow(for: pid)
        let main = AX.mainWindow(for: pid)
        var list: [AXUIElement] = []
        if let focused { list.append(focused) }
        if let main { list.append(main) }
        list.append(contentsOf: AX.windows(for: pid))
        var seen = Set<ObjectIdentifier>()
        return list.filter { window in
            let id = ObjectIdentifier(window)
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
    }

    private static func isMinimizableVisible(_ window: AXUIElement) -> Bool {
        let role = AX.role(of: window) ?? ""
        if role != (kAXWindowRole as String) { return false }
        let sub = AX.subrole(of: window) ?? ""
        if skipSubroles.contains(sub) { return false }
        if AX.isMinimized(window) { return false }
        if let size = AX.frame(of: window)?.size, size.width < 80 || size.height < 60 {
            return false
        }
        if AX.element(window, kAXMinimizeButtonAttribute as String) != nil {
            return true
        }
        return sub == (kAXStandardWindowSubrole as String)
    }
}
