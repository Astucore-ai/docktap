import AppKit
import ApplicationServices

enum AX {
    static let systemWide = AXUIElementCreateSystemWide()
    static let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)

    static func isTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        if err == .success { return true }
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }

    static func copy<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func role(of el: AXUIElement) -> String? { copy(el, kAXRoleAttribute as String) }
    static func subrole(of el: AXUIElement) -> String? { copy(el, kAXSubroleAttribute as String) }
    static func title(of el: AXUIElement) -> String? { copy(el, kAXTitleAttribute as String) }

    static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
        }
        return value as? Bool
    }

    static func setBool(_ el: AXUIElement, _ attr: String, _ flag: Bool) -> Bool {
        let value: CFBoolean = flag ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(el, attr as CFString, value) == .success
    }

    static func url(_ el: AXUIElement, _ attr: String = kAXURLAttribute as String) -> URL? {
        copy(el, attr)
    }

    static func children(of el: AXUIElement) -> [AXUIElement] {
        copy(el, kAXChildrenAttribute as String) ?? []
    }

    static func frame(of el: AXUIElement) -> CGRect? {
        guard let posVal: AXValue = copy(el, kAXPositionAttribute as String),
              let sizeVal: AXValue = copy(el, kAXSizeAttribute as String) else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal, .cgPoint, &pos),
              AXValueGetValue(sizeVal, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: pos, size: size)
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        return copy(app, kAXWindowsAttribute as String) ?? []
    }

    static func focusedWindow(for pid: pid_t) -> AXUIElement? {
        element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as String)
    }

    static func mainWindow(for pid: pid_t) -> AXUIElement? {
        element(AXUIElementCreateApplication(pid), kAXMainWindowAttribute as String)
    }

    static func isMinimized(_ el: AXUIElement) -> Bool {
        bool(el, kAXMinimizedAttribute as String) ?? false
    }

    static func setMessagingTimeout(_ el: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(el, seconds)
    }
}
