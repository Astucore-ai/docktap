import AppKit
import ApplicationServices
import CoreGraphics

private func dockTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}

private enum DockIntent {
    case minimize
    case restore
}

private struct ArmedClick {
    let pid: pid_t
    let bundleIdentifier: String?
    let title: String
    let downPoint: CGPoint
    let downAt: Date
    let intent: DockIntent
}

final class ClickMonitor {
    static let shared = ClickMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var cacheTimer: Timer?
    private var armed: ArmedClick?
    private var lastActionAt = Date.distantPast
    private var lastActionPID: pid_t = 0
    private var lastFrontmostPID: pid_t?
    private var lastFrontmostBundle: String?
    private var workspaceObserver: NSObjectProtocol?

    private let maxTravel: CGFloat = 10
    private let maxClickDuration: TimeInterval = 0.55
    private let minActionGap: TimeInterval = 0.18

    private init() {}

    var isTapInstalled: Bool { eventTap != nil }

    func start() {
        observeFrontmost()
        DockCache.shared.refresh(force: true)
        installTapIfPossible()
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.installTapIfPossible()
            }
        }
        if cacheTimer == nil {
            cacheTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if AX.isTrusted(prompt: false) {
                    DockCache.shared.refresh()
                    StatusStore.write(
                        state: ClickMonitor.shared.isTapInstalled ? "OK" : "NO_TAP",
                        eventTapCreated: ClickMonitor.shared.isTapInstalled,
                        dockItemCount: DockCache.shared.currentItems.count
                    )
                }
            }
        }
        publishStatus()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        cacheTimer?.invalidate()
        cacheTimer = nil
        armed = nil
        invalidateTap()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        publishStatus()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                DTLog.line("event tap re-enabled after \(type.rawValue)")
            } else {
                DispatchQueue.main.async { [weak self] in self?.installTapIfPossible() }
            }
            return Unmanaged.passUnretained(event)
        }

        guard SettingsStore.shared.settings.enabled else {
            armed = nil
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            onDown(event)
        case .leftMouseUp:
            onUp(event)
        case .leftMouseDragged:
            if let armed, hypot(event.location.x - armed.downPoint.x, event.location.y - armed.downPoint.y) > maxTravel {
                self.armed = nil
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func onDown(_ event: CGEvent) {
        armed = nil
        guard !hasModifiers(event) else { return }
        guard AX.isTrusted(prompt: false) else { return }

        let point = event.location
        let dockFrame = DockCache.shared.currentDockFrame
        if !dockFrame.isNull {
            let expanded = dockFrame.insetBy(dx: -36, dy: -48)
            guard expanded.contains(point) else { return }
        }

        DockCache.shared.refresh(force: true)
        guard let item = DockCache.shared.hit(at: point) else { return }
        guard item.running else { return }
        guard let app = DockCache.shared.runningApp(matching: item),
              app.processIdentifier != AX.ownPID else { return }
        if SettingsStore.shared.isExcluded(name: app.localizedName, bundleId: app.bundleIdentifier) {
            return
        }

        let pid = app.processIdentifier
        let visible = WindowActions.hasVisibleMinimizableWindow(pid: pid)
        let minimized = WindowActions.hasMinimizedWindow(pid: pid)
        let front = NSWorkspace.shared.frontmostApplication
            ?? runningApp(pid: lastFrontmostPID, bundle: lastFrontmostBundle)
        let isFront = front.map { DockCache.shared.matches(item, app: $0) } ?? false

        // Frontmost + visible → minimize (Windows). No visible windows but some
        // are minimized → restore all of them. The Dock only unminimizes one.
        let intent: DockIntent
        if isFront, visible, !app.isHidden {
            intent = .minimize
        } else if minimized, !visible {
            intent = .restore
        } else {
            return
        }

        let now = Date()
        if pid == lastActionPID, now.timeIntervalSince(lastActionAt) < minActionGap {
            return
        }

        armed = ArmedClick(
            pid: pid,
            bundleIdentifier: app.bundleIdentifier,
            title: item.title,
            downPoint: point,
            downAt: now,
            intent: intent
        )
    }

    private func onUp(_ event: CGEvent) {
        guard let armed else { return }
        self.armed = nil
        guard !hasModifiers(event) else { return }

        let point = event.location
        let duration = Date().timeIntervalSince(armed.downAt)
        guard duration <= maxClickDuration else { return }
        guard hypot(point.x - armed.downPoint.x, point.y - armed.downPoint.y) <= maxTravel else { return }
        guard let item = DockCache.shared.hit(at: point), item.title == armed.title else { return }

        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != armed.pid {
            if let bid = armed.bundleIdentifier, front.bundleIdentifier != bid {
                return
            }
        }

        lastActionAt = Date()
        lastActionPID = armed.pid
        let pid = armed.pid
        let title = armed.title
        let intent = armed.intent
        let settings = SettingsStore.shared.settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            self.performToggle(pid: pid, title: title, intent: intent, settings: settings)
        }
    }

    private func performToggle(pid: pid_t, title: String, intent: DockIntent, settings: DTSettings) {
        guard settings.enabled else { return }

        let result: String
        switch intent {
        case .restore:
            let n = WindowActions.restoreMinimized(pid: pid)
            result = "restore \(n) window(s)"
        case .minimize:
            guard WindowActions.hasVisibleMinimizableWindow(pid: pid) else { return }
            switch settings.action {
            case .hide:
                if title == "Finder" {
                    let n = WindowActions.minimize(pid: pid, scope: settings.scope)
                    result = "minimize-finder \(n) window(s)"
                } else if WindowActions.hide(pid: pid) {
                    result = "hide"
                } else {
                    let n = WindowActions.minimize(pid: pid, scope: settings.scope)
                    result = "hide-fallback-minimize \(n) window(s)"
                }
            case .minimize:
                let n = WindowActions.minimize(pid: pid, scope: settings.scope)
                result = "minimize \(n) window(s)"
            }
        }
        DTLog.line("\(title) pid=\(pid) → \(result)")
        StatusStore.write(
            state: isTapInstalled ? "OK" : "NO_TAP",
            eventTapCreated: isTapInstalled,
            dockItemCount: DockCache.shared.currentItems.count,
            lastAction: "\(title): \(result)"
        )
    }

    private func hasModifiers(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return flags.contains(.maskCommand)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskControl)
            || flags.contains(.maskShift)
    }

    private func runningApp(pid: pid_t?, bundle: String?) -> NSRunningApplication? {
        if let pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return app
        }
        if let bundle {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        }
        return nil
    }

    private func observeFrontmost() {
        if workspaceObserver != nil { return }
        let front = NSWorkspace.shared.frontmostApplication
        lastFrontmostPID = front?.processIdentifier
        lastFrontmostBundle = front?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.lastFrontmostPID = app?.processIdentifier
            self?.lastFrontmostBundle = app?.bundleIdentifier
        }
    }

    private func installTapIfPossible() {
        if eventTap != nil { return }
        guard AX.isTrusted(prompt: false) else {
            publishStatus(error: "accessibility_not_granted")
            return
        }
        let mask =
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: dockTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            DTLog.line("failed to create event tap")
            publishStatus(error: "event_tap_create_failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            publishStatus(error: "event_tap_source_failed")
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DockCache.shared.refresh(force: true)
        DTLog.line("event tap installed; dock items=\(DockCache.shared.currentItems.count)")
        publishStatus()
    }

    private func invalidateTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        self.runLoopSource = nil
        self.eventTap = nil
    }

    private func publishStatus(error: String? = nil) {
        StatusStore.write(
            state: eventTap == nil ? (error == nil ? "NO_TAP" : "FAIL") : "OK",
            eventTapCreated: eventTap != nil,
            dockItemCount: DockCache.shared.currentItems.count,
            lastError: error
        )
    }
}
