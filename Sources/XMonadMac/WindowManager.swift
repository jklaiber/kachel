import AppKit
import ApplicationServices
import XMonadCore

/// AX callback: just forwards to the manager.
private let axCallback: AXObserverCallback = { _, _, notification, _ in
    WindowManager.shared.onAXEvent(notification as String)
}

/// How workspaces work here (same trick as AeroSpace):
/// macOS Spaces can't be driven reliably without disabling SIP, so we don't
/// use them. All windows live on one Space per display. Windows of hidden
/// workspaces are parked in a screen corner with only one pixel showing, and
/// moved back when their workspace is shown. That makes switching instant
/// and lets workspaces move freely between monitors, like in xmonad.
final class WindowManager {
    static let shared = WindowManager()

    private(set) var ss = StackSet(tags: Config.workspaces, screenCount: 1, ratio: Config.defaultRatio)
    private var windows: [WindowID: AXWindow] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var screens: [Screen] = []
    private var hidden: Set<WindowID> = []
    /// Floating window frames relative to their screen's visible origin, saved on hide.
    private var floatRel: [WindowID: CGRect] = [:]
    /// workspace index -> screen it was on at the last render (to detect swaps).
    private var lastScreen: [Int: Int] = [:]
    private var refreshPending = false
    private var ignoreFocusEventsUntil = Date.distantPast
    private var statusBar: StatusBar?
    private var pollTimer: Timer?

    // MARK: - lifecycle

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        screens = Screen.all()
        ss.setScreenCount(screens.count)
        statusBar = StatusBar(wm: self)
        Config.bindKeys(self)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [unowned self] _ in
            self.scheduleRefresh()
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [unowned self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.dropObserver(app.processIdentifier)
            }
            self.scheduleRefresh()
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [unowned self] _ in
            self.syncFocusFromSystem(followHidden: true)
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [unowned self] _ in
            self.scheduleRefresh()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [unowned self] _ in
            self.screensChanged()
        }

        adoptExistingWindows()

        // Safety net in case an AX notification gets lost.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [unowned self] _ in
            self.refresh()
        }
    }

    /// On startup every existing window joins the workspace shown on the
    /// screen it currently sits on.
    private func adoptExistingWindows() {
        let found = enumerateWindows()
        for (id, w) in found.sorted(by: { $0.key < $1.key }) {
            var target = ss.screenWorkspace[ss.currentScreen]
            if let f = w.frame, let s = screenIndex(containing: CGPoint(x: f.midX, y: f.midY)) {
                target = ss.screenWorkspace[s]
            }
            if shouldFloat(w) { ss.floating.insert(id) }
            ss.insert(id, into: target)
        }
        windows = found
        render()
    }

    func quit() {
        restoreAllWindows()
        HotKeys.shared.unbindAll()
        exit(0)
    }

    /// Never leave windows stranded in a corner when we exit.
    private func restoreAllWindows() {
        guard let scr = screens.first else { return }
        var offset: CGFloat = 0
        for id in hidden {
            guard let w = windows[id] else { continue }
            w.move(to: CGPoint(x: scr.visible.minX + 40 + offset, y: scr.visible.minY + 40 + offset))
            offset = (offset + 24).truncatingRemainder(dividingBy: 240)
        }
        hidden.removeAll()
    }

    // MARK: - window discovery

    private func enumerateWindows() -> [WindowID: AXWindow] {
        var result: [WindowID: AXWindow] = [:]
        let me = getpid()
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
                for (id, w) in windows where w.pid == pid { result[id] = w }
                continue
            }
            for el in elements where isManageable(el) {
                guard let id = axWindowID(el) else { continue }
                if let known = windows[id] {
                    result[id] = known
                } else {
                    result[id] = AXWindow(element: el, id: id, pid: pid, bundleID: app.bundleIdentifier)
                    if let obs = observers[pid] {
                        AXObserverAddNotification(obs, el, kAXUIElementDestroyedNotification as CFString, nil)
                    }
                }
            }
        }
        return result
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

    private func dropObserver(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    fileprivate func onAXEvent(_ notification: String) {
        if notification == kAXFocusedWindowChangedNotification {
            syncFocusFromSystem(followHidden: true)
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [unowned self] in
            self.refreshPending = false
            self.refresh()
        }
    }

    /// Reconcile our model with the windows that actually exist.
    private func refresh() {
        let found = enumerateWindows()
        var changed = false
        for id in ss.allWindows where found[id] == nil {
            ss.remove(id)
            hidden.remove(id)
            floatRel[id] = nil
            changed = true
        }
        for (id, w) in found where ss.workspaceIndex(of: id) == nil {
            if shouldFloat(w) {
                ss.floating.insert(id)
                if let f = w.frame, isOffscreen(f) { centerOnCurrentScreen(w, f.size) }
            }
            ss.insert(id)               // new windows land on the current workspace
            hidden.remove(id)
            changed = true
        }
        windows = found
        if changed { render() }
    }

    private func shouldFloat(_ w: AXWindow) -> Bool {
        if let b = w.bundleID, Config.floatingBundleIDs.contains(b) { return true }
        return !w.isResizable
    }

    // MARK: - focus tracking (mouse clicks, cmd-tab, …)

    private func focusedSystemWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        return axElement(appEl, kAXFocusedWindowAttribute).flatMap(axWindowID)
    }

    /// Pull the real focus into the model. If the user cmd-tabbed to a
    /// window on a hidden workspace, bring that workspace here.
    private func syncFocusFromSystem(followHidden: Bool) {
        guard Date() > ignoreFocusEventsUntil,
              let id = focusedSystemWindow(),
              let wsIndex = ss.workspaceIndex(of: id) else { return }
        if ss.focus(id) {
            statusBar?.update(ss)
        } else if followHidden {
            ss.greedyView(wsIndex)
            ss.focus(id)
            render()
        }
    }

    // MARK: - actions (bound in Config.swift)

    func greedyView(_ i: Int) { syncFocusFromSystem(followHidden: false); ss.greedyView(i); render() }
    func view(_ i: Int)       { syncFocusFromSystem(followHidden: false); ss.view(i); render() }

    func shift(to i: Int) {
        syncFocusFromSystem(followHidden: false)
        guard let f = ss.current.focused else { return }
        ss.shift(f, to: i)
        render()
    }

    func focusScreen(_ s: Int) {
        syncFocusFromSystem(followHidden: false)
        ss.focusScreen(s)
        render()
    }

    func shiftToScreen(_ s: Int) {
        syncFocusFromSystem(followHidden: false)
        guard ss.screenWorkspace.indices.contains(s), let f = ss.current.focused else { return }
        ss.shift(f, to: ss.screenWorkspace[s])
        render()
    }

    func focusDown()   { act { $0.focusDown() } }
    func focusUp()     { act { $0.focusUp() } }
    func focusMaster() { act { $0.focusMaster() } }
    func swapDown()    { act { $0.swapDown() } }
    func swapUp()      { act { $0.swapUp() } }
    func swapMaster()  { act { $0.swapMaster() } }
    func nextLayout()  { act { $0.nextLayout() } }
    func incMaster(_ d: Int)      { act { $0.incMaster(d) } }
    func adjustRatio(_ d: Double) { act { $0.adjustRatio(d) } }

    func toggleFloat() {
        act { ss in
            if let f = ss.current.focused { ss.toggleFloating(f) }
        }
    }

    func closeFocused() {
        syncFocusFromSystem(followHidden: false)
        if let f = ss.current.focused { windows[f]?.close() }
    }

    func refreshNow() {
        screensChanged()
    }

    func spawn(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        try? p.run()
    }

    private func act(_ f: (inout StackSet) -> Void) {
        syncFocusFromSystem(followHidden: false)
        f(&ss)
        render()
    }

    // MARK: - screens

    private func screensChanged() {
        screens = Screen.all()
        ss.setScreenCount(screens.count)
        // Corners moved, so re-park everything from scratch.
        hidden.removeAll()
        refresh()
        render()
    }

    private func screenIndex(containing p: CGPoint) -> Int? {
        screens.firstIndex { $0.frame.contains(p) }
    }

    private func isOffscreen(_ f: CGRect) -> Bool {
        !screens.contains { $0.visible.intersection(f).width > 40 && $0.visible.intersection(f).height > 40 }
    }

    private func centerOnCurrentScreen(_ w: AXWindow, _ size: CGSize) {
        guard ss.currentScreen < screens.count else { return }
        let v = screens[ss.currentScreen].visible
        w.move(to: CGPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2))
    }

    // MARK: - rendering

    /// Make the screen match the model: park hidden workspaces, tile visible ones, focus.
    private func render() {
        guard !screens.isEmpty else { return }
        let visible = Set(ss.screenWorkspace)

        for (i, ws) in ss.workspaces.enumerated() where !visible.contains(i) {
            ws.windows.forEach(hide)
        }

        for (s, wsIndex) in ss.screenWorkspace.enumerated() where s < screens.count {
            let ws = ss.workspaces[wsIndex]
            let scr = screens[s]
            let tiled = ws.windows.filter { !ss.floating.contains($0) && windows[$0] != nil }
            let rects = Layout.tile(ws.layout, count: tiled.count, in: scr.visible,
                                    nMaster: ws.nMaster, ratio: ws.ratio, gap: Config.gap)
            for (id, r) in zip(tiled, rects) {
                windows[id]?.setFrame(r)
                hidden.remove(id)
            }
            let from = lastScreen[wsIndex]
            for id in ws.windows where ss.floating.contains(id) {
                if hidden.contains(id) {
                    showFloating(id, on: scr)
                } else if let from, from != s, from < screens.count {
                    // greedyView swapped this workspace onto another screen:
                    // carry its floating windows along.
                    moveFloating(id, from: screens[from], to: scr)
                }
            }
            if ws.layout == .full, let f = ws.focused, s != ss.currentScreen {
                windows[f]?.raise()
            }
        }

        lastScreen = [:]
        for (s, wsIndex) in ss.screenWorkspace.enumerated() { lastScreen[wsIndex] = s }

        focusCurrent()
        statusBar?.update(ss)
    }

    private func moveFloating(_ id: WindowID, from old: Screen, to new: Screen) {
        guard let w = windows[id], let f = w.frame else { return }
        let rel = f.offsetBy(dx: -old.visible.minX, dy: -old.visible.minY)
        floatRel[id] = rel
        hidden.insert(id)              // showFloating places + clamps it
        showFloating(id, on: new)
    }

    private func hide(_ id: WindowID) {
        guard !hidden.contains(id), let w = windows[id], let f = w.frame else { return }
        if ss.floating.contains(id) {
            let s = screenIndex(containing: CGPoint(x: f.midX, y: f.midY)) ?? ss.currentScreen
            let o = screens[min(s, screens.count - 1)].visible.origin
            floatRel[id] = f.offsetBy(dx: -o.x, dy: -o.y)
        }
        w.move(to: hidePoint(for: f))
        hidden.insert(id)
    }

    private func showFloating(_ id: WindowID, on scr: Screen) {
        guard hidden.contains(id), let w = windows[id] else { return }
        let size = w.frame?.size ?? CGSize(width: 800, height: 600)
        let rel = floatRel[id] ?? CGRect(origin: CGPoint(x: 60, y: 60), size: size)
        let v = scr.visible
        let x = min(max(v.minX, v.minX + rel.minX), v.maxX - min(size.width, v.width))
        let y = min(max(v.minY, v.minY + rel.minY), v.maxY - min(size.height, v.height))
        w.move(to: CGPoint(x: x, y: y))
        hidden.remove(id)
    }

    /// A corner where the window can sit with one pixel on-screen without
    /// overlapping any other display (macOS refuses fully off-screen windows).
    private func hidePoint(for frame: CGRect) -> CGPoint {
        let size = frame.size
        let home = screenIndex(containing: CGPoint(x: frame.midX, y: frame.midY))
        let ordered = home.map { [screens[$0]] + screens } ?? screens
        for scr in ordered {
            let f = scr.frame
            let candidates = [CGPoint(x: f.maxX - 1, y: f.maxY - 1),                  // bottom-right
                              CGPoint(x: f.minX - size.width + 1, y: f.maxY - 1)]     // bottom-left
            for p in candidates {
                let r = CGRect(origin: p, size: size).insetBy(dx: 2, dy: 2)
                if !screens.contains(where: { $0.frame.intersects(r) }) { return p }
            }
        }
        let last = screens[screens.count - 1].frame
        return CGPoint(x: last.maxX - 1, y: last.maxY - 1)
    }

    private func focusCurrent() {
        ignoreFocusEventsUntil = Date().addingTimeInterval(0.3)
        let ws = ss.current
        if let f = ws.focused, let w = windows[f] {
            w.focus()
        } else {
            // Empty workspace: take focus ourselves so keystrokes don't go
            // to a window that's parked in a corner.
            NSApp.activate(ignoringOtherApps: true)
        }
        if Config.mouseFollowsFocus, ss.currentScreen < screens.count {
            let scr = screens[ss.currentScreen]
            let mouse = CGEvent(source: nil)?.location ?? .zero
            if !scr.frame.contains(mouse) {
                CGWarpMouseCursorPosition(CGPoint(x: scr.frame.midX, y: scr.frame.midY))
            }
        }
    }
}
