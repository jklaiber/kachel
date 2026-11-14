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

    private(set) var ss = StackSet(tags: Config.current.workspaces, screenCount: 1, ratio: Config.current.ratio)
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
    private let bar = Bar()
    private let menuBarItem = MenuBarItem()
    private var managing = false
    private var hotkeyProblems: [String] = []
    private var pollTimer: Timer?
    private var pollTick = 0

    // MARK: - lifecycle

    /// Runs at launch, before Accessibility is granted: config, bar, hotkeys.
    /// Without this nothing at all is visible while permission is missing.
    func startUI() {
        Log.info("starting (pid \(getpid()))")
        Config.load(force: true)
        bar.onClickWorkspace = { [unowned self] s, i in
            guard self.managing else { return }
            self.greedyView(i, onScreen: s)
        }
        bar.onToggleWidget = { [unowned self] w in
            Config.toggleWidget(w)
            self.reload()
        }
        bar.menuActions = menuEntries()
        menuBarItem.entries = { [unowned self] in self.menuEntries() }
        applySettings()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [unowned self] _ in
            self.screensChanged()
        }
        // Picks up config edits; does the AX safety-net refresh once managing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
            if Config.load() { self.applySettings() }
            self.pollTick += 1
            if self.managing, self.pollTick % 2 == 0 { self.refresh(); self.updateBar() }
        }
    }

    /// Shared by the menu bar icon and the bar's right-click menu.
    private func menuEntries() -> [(title: String, action: () -> Void)] {
        [
            ("Restart XMonadMac", { [unowned self] in self.restart() }),
            ("Reload Config", { [unowned self] in self.reload() }),
            ("Edit Config…", { Config.openInEditor() }),
            ("Show Log", { NSWorkspace.shared.open(Log.url) }),
            ("-", {}),
            ("Re-tile", { [unowned self] in self.refreshNow() }),
            ("Open Accessibility Settings…", { WindowManager.openAccessibilitySettings() }),
            ("-", {}),
            ("Quit XMonadMac", { [unowned self] in self.quit() }),
        ]
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Runs once Accessibility permission is granted.
    func startManaging() {
        guard !managing else { return }
        managing = true
        Log.info("Accessibility granted, managing windows")
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

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

        adoptExistingWindows()
    }

    /// (Re)apply Config.current: hotkeys, workspaces, bar, screen geometry.
    private func applySettings(rebindKeys: Bool = true) {
        let cfg = Config.current
        if rebindKeys {
            hotkeyProblems = HotKeys.shared.bind(cfg.keys) { [unowned self] cmd in self.perform(cmd) }
        }
        ss.setTags(cfg.workspaces)
        ss.setLayoutIfUnlisted(cfg.layouts)
        menuBarItem.setVisible(cfg.menubarIcon)
        screens = Screen.all(reserveBottom: cfg.bar.enabled ? Bar.height(for: cfg.bar) : 0)
        ss.setScreenCount(screens.count)
        bar.place(on: screens, settings: cfg.bar)
        if managing {
            hidden.removeAll()       // geometry may have changed: re-park from scratch
            render()
        } else {
            updateBar()
        }
    }

    func reload() {
        Config.load(force: true)
        applySettings()
    }

    /// On startup every existing window joins the workspace shown on the
    /// screen it currently sits on.
    private func adoptExistingWindows() {
        let found = enumerateWindows()
        if let snap = loadSnapshot() {
            ss.restore(snap, existing: Set(found.keys))
            Log.info("restored \(ss.allWindows.count) of \(found.count) windows to their workspaces from the last run")
        }
        for (id, w) in found.sorted(by: { $0.key < $1.key }) where ss.workspaceIndex(of: id) == nil {
            var target = ss.screenWorkspace[ss.currentScreen]
            if let f = w.frame, let s = screenIndex(containing: CGPoint(x: f.midX, y: f.midY)) {
                target = ss.screenWorkspace[s]
            }
            if shouldFloat(w) { ss.floating.insert(id) }
            ss.insert(id, into: target)
        }
        windows = found
        Log.info("adopted \(found.count) windows on \(screens.count) screens")
        render()
        dumpState()
    }

    /// Write the whole model to the log (also triggered externally, see main.swift).
    func dumpState() {
        Log.info("state: managing=\(managing) currentScreen=\(ss.currentScreen) screens→ws=\(ss.screenWorkspace)")
        for (i, s) in screens.enumerated() { Log.info("  screen \(i): frame=\(s.frame) visible=\(s.visible)") }
        for ws in ss.workspaces where !ws.windows.isEmpty {
            let list = ws.windows.map { id -> String in
                let w = windows[id]
                let tag = (ss.floating.contains(id) ? "F" : "") + (hidden.contains(id) ? "H" : "")
                return "\(id)\(tag.isEmpty ? "" : "[\(tag)]") \(w?.bundleID ?? "?") \"\(w?.title.prefix(30) ?? "")\" \(w?.frame.map { "\($0)" } ?? "noframe")"
            }
            Log.info("  ws \(ws.tag) \(ws.layout.rawValue) focused=\(ws.focused.map(String.init) ?? "-"):")
            list.forEach { Log.info("    \($0)") }
        }
    }

    func quit() {
        if managing { saveSnapshot() }
        restoreAllWindows()
        HotKeys.shared.unbindAll()
        Log.info("quit")
        exit(0)
    }

    /// Quit and start again; windows keep their workspaces (see saveSnapshot).
    func restart() {
        Log.info("restarting")
        if managing { saveSnapshot() }
        restoreAllWindows()
        HotKeys.shared.unbindAll()
        let bundle = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        if bundle.hasSuffix(".app") {
            p.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", bundle]
        } else {
            p.arguments = ["-c", "sleep 0.5; \"$0\" >/dev/null 2>&1 &", ProcessInfo.processInfo.arguments[0]]
        }
        try? p.run()
        exit(0)
    }

    // MARK: - state across restarts

    private static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XMonadMac/state.json")

    private func saveSnapshot() {
        do {
            try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(ss.snapshot).write(to: Self.stateURL, options: .atomic)
        } catch {
            Log.info("could not save state: \(error)")
        }
    }

    /// Window IDs only live as long as the apps do, so the snapshot is used
    /// once and only if it's from this login session's apps (stale IDs just
    /// don't match anything).
    private func loadSnapshot() -> StackSet.Snapshot? {
        defer { try? FileManager.default.removeItem(at: Self.stateURL) }
        guard let data = try? Data(contentsOf: Self.stateURL) else { return nil }
        return try? JSONDecoder().decode(StackSet.Snapshot.self, from: data)
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
        if let b = w.bundleID, Config.current.floating.contains(b) { return true }
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
            updateBar()
        } else if followHidden {
            ss.greedyView(wsIndex)
            ss.focus(id)
            render()
        }
    }

    // MARK: - actions (bound in Config.swift)

    func perform(_ cmd: Command) {
        Log.info("command \(cmd)")
        guard managing else {
            Log.info("ignoring \(cmd): no Accessibility permission yet")
            if case .quit = cmd { quit() }
            if case .reload = cmd { reload() }
            if case .restart = cmd { restart() }
            return
        }
        let step = Config.current.ratioStep
        switch cmd {
        case .greedyView(let i): greedyView(i)
        case .view(let i): view(i)
        case .shift(let i): shift(to: i)
        case .focusScreen(let s): focusScreen(s)
        case .shiftToScreen(let s): shiftToScreen(s)
        case .focusDown: focusDown()
        case .focusUp: focusUp()
        case .focusMaster: focusMaster()
        case .swapDown: swapDown()
        case .swapUp: swapUp()
        case .swapMaster: swapMaster()
        case .nextLayout: act { $0.nextLayout(in: Config.current.layouts) }
        case .focusNextScreen: focusScreen(ss.neighbourScreen(+1))
        case .focusPrevScreen: focusScreen(ss.neighbourScreen(-1))
        case .shiftToNextScreen: shiftToScreen(ss.neighbourScreen(+1))
        case .shiftToPrevScreen: shiftToScreen(ss.neighbourScreen(-1))
        case .workspaceNext: syncFocusFromSystem(followHidden: false); greedyView(ss.neighbour(+1))
        case .workspacePrev: syncFocusFromSystem(followHidden: false); greedyView(ss.neighbour(-1))
        case .shiftNext: syncFocusFromSystem(followHidden: false); shift(to: ss.neighbour(+1))
        case .shiftPrev: syncFocusFromSystem(followHidden: false); shift(to: ss.neighbour(-1))
        case .restart: restart()
        case .shrink: adjustRatio(-step)
        case .expand: adjustRatio(+step)
        case .incMaster: incMaster(+1)
        case .decMaster: incMaster(-1)
        case .toggleFloat: toggleFloat()
        case .refresh: refreshNow()
        case .close: closeFocused()
        case .terminal: spawn(Config.current.terminal)
        case .spawn(let c): spawn(c)
        case .reload: reload()
        case .quit: quit()
        }
    }

    /// Clicking workspace `i` in screen `s`'s bar: show it on that screen.
    func greedyView(_ i: Int, onScreen s: Int) {
        syncFocusFromSystem(followHidden: false)   // before focusScreen, or it would undo it
        ss.focusScreen(s)
        ss.greedyView(i)
        render()
    }

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
        // Corners and bar positions moved: applySettings re-parks from scratch.
        applySettings(rebindKeys: false)
        if managing { refresh() }
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
                                    nMaster: ws.nMaster, ratio: ws.ratio, gap: CGFloat(Config.current.gap))
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
        updateBar()
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

    private func updateBar() {
        var warning: String?
        if !managing {
            warning = "XMonadMac needs Accessibility permission. Right-click → Open Accessibility Settings, then switch XMonadMac on."
        } else if let e = Config.error {
            warning = "config: \(e)"
        } else if let p = hotkeyProblems.first {
            warning = p + (hotkeyProblems.count > 1 ? " (+\(hotkeyProblems.count - 1) more, see log)" : "")
        }
        var contents: [Bar.Content] = []
        for (s, wsIndex) in ss.screenWorkspace.enumerated() {
            var c = Bar.Content()
            c.isCurrentScreen = s == ss.currentScreen
            for (i, ws) in ss.workspaces.enumerated() {
                c.tags.append(Bar.Tag(name: ws.tag,
                                      active: i == ss.currentWorkspaceIndex,
                                      visible: ss.isVisible(workspace: i),
                                      hasWindows: !ws.windows.isEmpty))
            }
            let ws = ss.workspaces[wsIndex]
            c.layout = ws.layout.rawValue
            if managing, let f = ws.focused, let w = windows[f] { c.title = w.title }
            contents.append(c)
        }
        bar.update(contents, warning: warning)
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
        if Config.current.mouseFollowsFocus, ss.currentScreen < screens.count {
            let scr = screens[ss.currentScreen]
            let mouse = CGEvent(source: nil)?.location ?? .zero
            if !scr.frame.contains(mouse) {
                CGWarpMouseCursorPosition(CGPoint(x: scr.frame.midX, y: scr.frame.midY))
            }
        }
    }
}
