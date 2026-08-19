import AppKit
import ApplicationServices

struct DockAppItem {
    let title: String
    let url: URL
    let bundleIdentifier: String?
    let frame: CGRect
    let running: Bool
}

final class DockCache {
    static let shared = DockCache()

    private let lock = NSLock()
    private var items: [DockAppItem] = []
    private var dockFrame: CGRect = .null
    private var lastRefresh = Date.distantPast
    private let minInterval: TimeInterval = 0.25

    private init() {}

    var currentItems: [DockAppItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    var currentDockFrame: CGRect {
        lock.lock()
        defer { lock.unlock() }
        return dockFrame
    }

    func refresh(force: Bool = false) {
        if !force {
            lock.lock()
            let stale = Date().timeIntervalSince(lastRefresh) > minInterval
            lock.unlock()
            if !stale { return }
        }
        let snapshot = Self.load()
        lock.lock()
        items = snapshot.items
        dockFrame = snapshot.frame
        lastRefresh = Date()
        lock.unlock()
    }

    func hit(at quartzPoint: CGPoint, slop: CGFloat = 4) -> DockAppItem? {
        let list: [DockAppItem]
        let frame: CGRect
        lock.lock()
        list = items
        frame = dockFrame
        lock.unlock()

        let expandedDock = frame.insetBy(dx: -24, dy: -24)
        if !frame.isNull, !expandedDock.contains(quartzPoint) {
            return nil
        }
        return list.first { $0.frame.insetBy(dx: -slop, dy: -slop).contains(quartzPoint) }
    }

    func matches(_ item: DockAppItem, app: NSRunningApplication) -> Bool {
        if let itemId = item.bundleIdentifier, let appId = app.bundleIdentifier,
           itemId.caseInsensitiveCompare(appId) == .orderedSame {
            return true
        }
        if let appURL = app.bundleURL, Self.sameFile(item.url, appURL) {
            return true
        }
        if let name = app.localizedName, !name.isEmpty, item.title == name {
            return true
        }
        return false
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func load() -> (items: [DockAppItem], frame: CGRect) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return ([], .null)
        }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AX.setMessagingTimeout(root, seconds: 1.0)

        var found: [DockAppItem] = []
        var listFrame = CGRect.null
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (el, depth) = queue[index]
            index += 1
            if depth > 6 { continue }
            let role = AX.role(of: el) ?? ""
            let sub = AX.subrole(of: el) ?? ""
            if role == (kAXListRole as String), let frame = AX.frame(of: el) {
                if listFrame.isNull { listFrame = frame }
            }
            if role == "AXDockItem" && sub == "AXApplicationDockItem" {
                if let title = AX.title(of: el),
                   let frame = AX.frame(of: el) {
                    let url = AX.url(el) ?? URL(fileURLWithPath: "/\(title).app")
                    let running = AX.bool(el, "AXIsApplicationRunning") ?? false
                    let bid = AX.url(el).flatMap { Bundle(url: $0)?.bundleIdentifier }
                    found.append(DockAppItem(
                        title: title,
                        url: url,
                        bundleIdentifier: bid,
                        frame: frame,
                        running: running
                    ))
                }
                continue
            }
            for child in AX.children(of: el) {
                queue.append((child, depth + 1))
            }
        }
        if found.isEmpty {
            DTLog.line("dock cache empty listFrame=\(listFrame) children=\(AX.children(of: root).count)")
        }
        return (found, listFrame)
    }
}
