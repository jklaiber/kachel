import AppKit
import ApplicationServices
import KachelCore

/// Everything WindowManager asks macOS about windows. AXWindowSystem is the
/// real one; the tests drive WindowManager with a fake (Tests/KachelTests).
protocol WindowSystem: AnyObject {
    /// Every window Kachel could manage, of every app. `known` is the last
    /// answer: windows whose handle didn't change are reused from it, and an
    /// app that doesn't answer keeps its windows from it.
    func windows(known: [WindowID: AppWindow]) -> [WindowID: AppWindow]
    /// Every window the window server knows, on any Space, visible or not.
    func windowServerIDs() -> Set<WindowID>
    /// The focused window of the frontmost app (not Kachel's own).
    func focusedWindow() -> WindowID?
    /// An app quit: forget what we kept for it.
    func appQuit(_ pid: pid_t)
    /// The displays, left to right; `reserveBottom` is kept free for the bar.
    func screens(reserveBottom: CGFloat) -> [Screen]
}

/// The real one: Accessibility and the window server.
final class AXWindowSystem: WindowSystem {
    private var observers: [pid_t: AXObserver] = [:]
    /// Windows logged as left alone (they float above others on their own).
    private var leftAlone: Set<WindowID> = []

    func windows(known: [WindowID: AppWindow]) -> [WindowID: AppWindow] {
        var result: [WindowID: AppWindow] = [:]
        let me = getpid()
        let raised = raisedWindows()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != me {
            let pid = app.processIdentifier
            ensureObserver(pid)
            let appEl = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
            guard err == .success, let elements = value as? [AXUIElement] else {
                // App busy / not answering: keep what we knew instead of
                // forgetting its windows (and their workspaces).
                for (id, w) in known where w.pid == pid { result[id] = w }
                continue
            }
            for el in elements where isManageable(el) {
                guard let id = axWindowID(el) else { continue }
                if let level = raised[id] {
                    // The app keeps it above normal windows itself (Outlook's
                    // reminder, an "always on top" window), like a panel. As in
                    // Amethyst, it's left alone: not tiled, not cycled to, not
                    // parked when you switch workspaces. Its app decides where it goes.
                    if leftAlone.insert(id).inserted {
                        Log.info("leaving window \(id) (\(app.localizedName ?? "?")) alone: it floats above other windows (level \(level))")
                    }
                    continue
                }
                if let old = known[id] as? AXWindow, CFEqual(old.element, el) {
                    result[id] = old
                } else {
                    // New, or an app (Slack, Telegram) hid the window and brought it
                    // back with a new handle: the old one no longer answers.
                    if known[id] != nil {
                        Log.info("window \(id) (\(app.localizedName ?? "?")) came back with a new handle: using it")
                    }
                    result[id] = AXWindow(element: el, id: id, pid: pid, bundleID: app.bundleIdentifier)
                    if let obs = observers[pid] {
                        AXObserverAddNotification(obs, el, kAXUIElementDestroyedNotification as CFString, nil)
                        AXObserverAddNotification(obs, el, kAXWindowResizedNotification as CFString, nil)
                        AXObserverAddNotification(obs, el, kAXWindowMovedNotification as CFString, nil)
                    }
                }
            }
        }
        return result
    }

    func windowServerIDs() -> Set<WindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    func focusedWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        return axElement(appEl, kAXFocusedWindowAttribute).flatMap(axWindowID)
    }

    func screens(reserveBottom: CGFloat) -> [Screen] { Screen.all(reserveBottom: reserveBottom) }

    func appQuit(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    /// Windows that sit above the normal window level, by ID, with their level.
    private func raisedWindows() -> [WindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var out: [WindowID: Int] = [:]
        for w in list {
            guard let level = w[kCGWindowLayer as String] as? Int, level > 0,
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            out[id] = level
        }
        return out
    }

    private func ensureObserver(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        // Apps that are still launching refuse subscriptions. Don't cache the
        // observer then, so the next refresh tries again.
        guard AXObserverAddNotification(obs, appEl, kAXWindowCreatedNotification as CFString, nil) == .success
        else { return }
        for n in [kAXFocusedWindowChangedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                  kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            AXObserverAddNotification(obs, appEl, n as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }
}
