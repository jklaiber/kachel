import AppKit
import ApplicationServices
import KachelCore

/// AX callback: just forwards to the manager.
private let axCallback: AXObserverCallback = { _, element, notification, _ in
    WindowManager.shared.onAXEvent(notification as String, element: element)
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
    /// When a window last closed or an app quit. macOS then activates some
    /// other app on its own; that must not drag us to that app's workspace.
    private var lastWindowGone = Date.distantPast
    private var followPending = false
    /// Between "going to sleep" and shortly after waking: windows and screens
    /// are in flux, so don't draw conclusions from them.
    private var asleep = false
    /// A tiled window being resized with the mouse; applied on mouse-up.
    private var mouseResized: WindowID?
    private var mouseUpTimer: Timer?
    private var mouseMoved: WindowID?
    /// Where render() put each tiled window, to notice apps that didn't comply.
    private var expected: [WindowID: CGRect] = [:]
    private var verifyPending = false
    /// Minimum sizes learned from windows that refused to get smaller.
    private var minSize: [WindowID: CGSize] = [:]
    private var savePending = false
    private let bar = Bar()
    private let menuBarItem = MenuBarItem()
    private let switcher = WindowSwitcher()
    private let rulePicker = RulePicker()
    /// Most recently focused first, for ranking search results.
    private var mru: [WindowID] = []
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
        switcher.onGo = { [unowned self] id in self.goToWindow(id) }
        switcher.onBring = { [unowned self] id in self.bringWindow(id) }
        switcher.onCancel = { [unowned self] in self.focusCurrent() }
        rulePicker.onCancel = { [unowned self] in self.focusCurrent() }
        bar.onToggleMenuBarIcon = { [unowned self] in
            Config.setTopLevel(key: "menubar-icon", value: Config.current.menubarIcon ? "false" : "true")
            self.reload()
        }
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
            ("Restart Kachel", { [unowned self] in self.restart() }),
            (Config.current.startAtLogin ? "Start at Login ✓" : "Start at Login", {
                Config.setTopLevel(key: "start-at-login", value: Config.current.startAtLogin ? "false" : "true")
            }),
            ("Reload Config", { [unowned self] in self.reload() }),
            ("Edit Config…", { Config.openInEditor() }),
            ("Show Log", { NSWorkspace.shared.open(Log.url) }),
            ("-", {}),
            ("Re-tile", { [unowned self] in self.refreshNow() }),
            ("Open Accessibility Settings…", { WindowManager.openAccessibilitySettings() }),
            ("-", {}),
            ("Quit Kachel", { [unowned self] in self.quit() }),
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
            self.lastWindowGone = Date()
            self.scheduleRefresh()
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [unowned self] _ in
            self.syncFocusFromSystem(followHidden: true)
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [unowned self] _ in
            self.scheduleRefresh()
        }
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [unowned self] _ in
                if !self.asleep { Log.info("sleeping: pausing window tracking") }
                self.asleep = true
            }
        }
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [unowned self] _ in
                // Give displays and apps a moment to come back, then re-check everything.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [unowned self] in
                    guard self.asleep else { return }
                    self.asleep = false
                    Log.info("awake: re-checking screens and windows")
                    self.screensChanged()
                }
            }
        }

        adoptExistingWindows()
        updateGestures()
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
        LoginItem.apply(cfg.startAtLogin)
        updateGestures()
        bar.menuBarIconShown = cfg.menubarIcon
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
            if let ws = ruleWorkspace(for: w) { target = ws }
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

    // MARK: - mouse resize of the master split

    private func waitForMouseUp() {
        guard mouseUpTimer == nil else { return }
        mouseUpTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [unowned self] t in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            t.invalidate()
            self.mouseUpTimer = nil
            // Resizing from the left/top edge also moves the window: a resize wins.
            if let id = self.mouseResized { self.applyMouseResize(id) }
            else if let id = self.mouseMoved { self.applyMouseMove(id) }
            self.mouseResized = nil
            self.mouseMoved = nil
        }
    }

    /// Turn the window's new size into the workspace's master ratio, then
    /// re-tile so the other windows make room. Anything that isn't a split
    /// (Full, Column, floating) just snaps back.
    private func applyMouseResize(_ id: WindowID) {
        guard let wsIndex = ss.workspaceIndex(of: id), !ss.floating.contains(id),
              let s = ss.screen(ofWorkspace: wsIndex), s < screens.count,
              let frame = windows[id]?.frame else { return }
        let ws = ss.workspaces[wsIndex]
        let tiled = ws.windows.filter { !ss.floating.contains($0) && windows[$0] != nil }
        if let i = tiled.firstIndex(of: id),
           let r = Layout.ratio(afterResizing: frame, index: i, count: tiled.count, kind: ws.layout,
                                in: screens[s].visible, nMaster: ws.nMaster, gap: CGFloat(Config.current.gap)) {
            Log.info("mouse resize: workspace \(ws.tag) ratio \(String(format: "%.2f", ws.ratio)) → \(String(format: "%.2f", r))")
            ss.setRatio(r, workspace: wsIndex)
        }
        render()
    }

    // MARK: - trackpad swipes

    private func updateGestures() {
        let g = Config.current.gestures
        let g2 = Gestures.shared
        g2.onSwipe = { [unowned self] dir in self.swiped(dir) }
        if managing && g.enabled { g2.start(fingers: g.fingers) } else { g2.stop() }
    }

    /// A swipe acts on the screen under the pointer, like the macOS one.
    private func swiped(_ dir: Gestures.Direction) {
        guard managing, !switcher.isOpen, !rulePicker.isOpen else { return }
        let g = Config.current.gestures
        // With natural scrolling off, macOS flips its Spaces swipe; so do we.
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let flip = g.direction == .reversed || (g.direction == .auto && !natural)
        var dir = dir
        if flip {
            switch dir {
            case .left: dir = .right
            case .right: dir = .left
            case .up: dir = .down
            case .down: dir = .up
            }
        }
        let cmd: Command?
        switch dir {
        case .left: cmd = g.left
        case .right: cmd = g.right
        case .up: cmd = g.up
        case .down: cmd = g.down
        }
        guard let cmd else { return }
        syncFocusFromSystem(followHidden: false)
        if let primary = NSScreen.screens.first {
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: m.x, y: primary.frame.height - m.y)     // to AX coordinates
            if let s = screenIndex(containing: p) { ss.focusScreen(s) }
        }
        switch cmd {
        case .workspaceNext, .workspacePrev:
            let d = cmd == .workspaceNext ? +1 : -1
            guard let target = ss.cycleTarget(d, skipEmpty: g.skipEmpty) else {
                Log.info("swipe \(dir.rawValue): no other workspace to go to")
                return
            }
            Log.info("swipe \(dir.rawValue): workspace \(ss.workspaces[target].tag) on screen \(ss.currentScreen)")
            ss.greedyView(target)
            render()
        default:
            Log.info("swipe \(dir.rawValue): \(cmd)")
            perform(cmd)
        }
    }

    /// A tiled window was dragged and dropped (Amethyst's mouse-swaps-windows):
    /// onto another tiled window, the two swap (also across screens); onto
    /// an empty part of another screen, it moves to that screen's workspace.
    /// Anything else snaps back.
    private func applyMouseMove(_ id: WindowID) {
        guard let from = ss.workspaceIndex(of: id), !ss.floating.contains(id),
              let primary = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let drop = CGPoint(x: m.x, y: primary.frame.height - m.y)
        guard let s = screenIndex(containing: drop) else { render(); return }
        let wsIndex = ss.screenWorkspace[s]
        let target = ss.workspaces[wsIndex].windows.first { t in
            t != id && !ss.floating.contains(t) && (expected[t] ?? windows[t]?.frame)?.contains(drop) == true
        }
        if let t = target {
            Log.info("mouse drag: swap window \(id) with \(t)")
            ss.swap(id, t)
        } else if wsIndex != from {
            Log.info("mouse drag: window \(id) → workspace \(ss.workspaces[wsIndex].tag)")
            ss.shift(id, to: wsIndex)
        }
        ss.focus(id)
        render()
    }

    // MARK: - window search

    private func touch(_ id: WindowID) {
        if mru.first == id { return }
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if mru.count > 200 { mru.removeLast(mru.count - 200) }
    }

    func toggleWindowSearch() {
        if switcher.isOpen { switcher.close(cancelled: true); return }
        syncFocusFromSystem(followHidden: false)
        let focused = ss.current.focused
        var apps: [pid_t: NSRunningApplication] = [:]
        var entries: [WindowSwitcher.Entry] = []
        for (i, ws) in ss.workspaces.enumerated() {
            for id in ws.windows {
                guard let w = windows[id] else { continue }
                let app = apps[w.pid] ?? NSRunningApplication(processIdentifier: w.pid)
                apps[w.pid] = app
                entries.append(.init(id: id, app: app?.localizedName ?? w.bundleID ?? "?", title: w.title,
                                     icon: app?.icon, workspace: i, tag: ws.tag,
                                     visible: ss.isVisible(workspace: i), active: i == ss.currentWorkspaceIndex,
                                     recency: mru.firstIndex(of: id) ?? mru.count + Int(id % 1000),
                                     focused: id == focused))
            }
        }
        guard ss.currentScreen < screens.count else { return }
        let scr = screens[ss.currentScreen]
        let cfg = Config.current.bar
        switcher.open(entries, area: scr.nsVisible, bottom: cfg.enabled ? Bar.height(for: cfg) : 0)
    }

    /// ↩ in the search: show the window's workspace here (greedyView) and focus it.
    private func goToWindow(_ id: WindowID) {
        guard let ws = ss.workspaceIndex(of: id) else { return }
        if ws != ss.currentWorkspaceIndex { ss.greedyView(ws) }
        ss.focus(id)
        render()
    }

    /// ⇧↩ in the search: move the window to this workspace and focus it.
    private func bringWindow(_ id: WindowID) {
        let here = ss.currentWorkspaceIndex
        if ss.workspaceIndex(of: id) != here { ss.shift(id, to: here) }
        ss.focus(id)
        render()
    }

    // MARK: - app rules (mod-shift-p)

    func toggleRulePicker() {
        if rulePicker.isOpen { rulePicker.close(cancelled: true); return }
        syncFocusFromSystem(followHidden: false)
        guard let fid = ss.current.focused, let w = windows[fid] else {
            Log.info("app rule: no focused window")
            NSSound.beep()
            return
        }
        let name = appName(of: w)
        let key = w.bundleID ?? name                       // what the rule matches on
        let existing = Config.current.rules.first {
            $0.title == nil && $0.matches(bundleID: w.bundleID, appName: name, title: "")
        }
        let cfg = Config.current
        guard ss.currentScreen < screens.count else { return }
        rulePicker.onChoose = { [unowned self] choice in
            var r = existing ?? Rule(app: key)
            switch choice {
            case .workspace(let i): r.workspace = cfg.workspaces[i]
            case .toggleFloat: r.float.toggle()
            case .remove: break
            }
            let keep: Rule? = {
                if case .remove = choice { return nil }
                return (r.workspace == nil && !r.float) ? nil : r
            }()
            Config.setRule(app: existing?.app ?? key, rule: keep, comment: name)
            Config.load(force: true)
            self.applySettings(rebindKeys: false)
            self.applyRuleNow(bundleID: w.bundleID, appName: name)
        }
        rulePicker.open(app: name, icon: NSRunningApplication(processIdentifier: w.pid)?.icon,
                        tags: cfg.workspaces,
                        current: existing?.workspace.flatMap(cfg.workspaceIndex(named:)),
                        floats: existing?.float ?? false, hasRule: existing != nil,
                        area: screens[ss.currentScreen].nsVisible,
                        bottom: cfg.bar.enabled ? Bar.height(for: cfg.bar) : 0)
    }

    /// After setting a rule: move the app's open windows there now, and
    /// float or tile them to match. You stay on your workspace.
    private func applyRuleNow(bundleID: String?, appName name: String) {
        var moved = 0
        for (id, w) in windows where w.bundleID == bundleID && appName(of: w) == name {
            let r = rule(for: w)
            if let ws = r?.workspace.flatMap(Config.current.workspaceIndex(named:)), ss.workspaceIndex(of: id) != ws {
                ss.shift(id, to: ws)
                moved += 1
            }
            if r?.float == true { ss.floating.insert(id) }
            else if !shouldFloat(w) { ss.floating.remove(id) }
        }
        Log.info("rule for \(name): moved \(moved) window(s)")
        render()
    }

    // MARK: - state across restarts

    private static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Kachel/state.json")

    private func saveSnapshot() {
        do {
            try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedState(boot: Self.bootTime, state: ss.snapshot))
                .write(to: Self.stateURL, options: .atomic)
        } catch {
            Log.info("could not save state: \(error)")
        }
    }

    /// Window IDs only live as long as the apps do, so the snapshot is used
    /// once and only if it's from this login session's apps (stale IDs just
    /// don't match anything).
    private func loadSnapshot() -> StackSet.Snapshot? {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else { return nil }
        // Window IDs start over after a reboot; old ones would match random windows.
        guard abs(saved.boot - Self.bootTime) < 1 else {
            Log.info("saved state is from before the last reboot, ignoring it")
            return nil
        }
        return saved.state
    }

    private struct SavedState: Codable {
        var boot: Double
        var state: StackSet.Snapshot
    }

    private static let bootTime: Double = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
    }()

    /// Last resort when Kachel is crashing: put parked windows back on screen
    /// (AeroSpace does the same). Not async-signal-safe, but it's the end anyway.
    func emergencyRestore() {
        restoreAllWindows()
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
                        AXObserverAddNotification(obs, el, kAXWindowResizedNotification as CFString, nil)
                        AXObserverAddNotification(obs, el, kAXWindowMovedNotification as CFString, nil)
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

    fileprivate func onAXEvent(_ notification: String, element: AXUIElement) {
        if notification == kAXWindowMovedNotification {
            // A drag with the mouse (title bar): swap on drop, see applyMouseMove.
            if NSEvent.pressedMouseButtons & 1 != 0, let id = axWindowID(element), windows[id] != nil {
                mouseMoved = id
                waitForMouseUp()
            }
            return
        }
        if notification == kAXWindowResizedNotification {
            // Only your own drags count: the mouse button is down. Apps that
            // refuse a size we asked for must not move the split.
            if NSEvent.pressedMouseButtons & 1 != 0, let id = axWindowID(element), windows[id] != nil {
                mouseResized = id
                waitForMouseUp()
            }
            return
        }
        if notification == kAXUIElementDestroyedNotification {
            lastWindowGone = Date()
        }
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
        guard !asleep else { return }
        let found = enumerateWindows()
        var changed = false
        let missing = ss.allWindows.filter { found[$0] == nil }
        if !missing.isEmpty {
            // Accessibility sometimes reports no windows at all: during sleep,
            // for busy apps, for minimized or fullscreen windows. Only forget a
            // window once the window server says it's really gone, or it would
            // lose its workspace and come back on the current one.
            let alive = windowServerIDs()
            for id in missing {
                if alive.contains(id) { continue }
                Log.info("window \(id) closed (was on workspace \(ss.workspaceIndex(of: id).map { ss.workspaces[$0].tag } ?? "?"))")
                ss.remove(id)
                hidden.remove(id)
                floatRel[id] = nil
                minSize[id] = nil
                changed = true
                lastWindowGone = Date()
            }
        }
        // Windows coming back (after sleep, un-minimized, app answering again)
        // keep their workspace; just put them in place.
        if found.keys.contains(where: { windows[$0] == nil && ss.workspaceIndex(of: $0) != nil }) {
            changed = true
        }
        for (id, w) in found where ss.workspaceIndex(of: id) == nil {
            if shouldFloat(w) {
                ss.floating.insert(id)
                if let f = w.frame, isOffscreen(f) { centerOnCurrentScreen(w, f.size) }
            }
            Log.info("new window \(id): \(appName(of: w)) \"\(w.title.prefix(40))\"")
            if let ws = ruleWorkspace(for: w), ws != ss.currentWorkspaceIndex {
                // A rule sends it elsewhere (xmonad doShift): it appears there, you stay here.
                ss.insert(id, into: ws)
                Log.info("rule: \(appName(of: w)) window \(id) → workspace \(ss.workspaces[ws].tag)")
            } else {
                ss.insert(id)           // new windows land on the current workspace
            }
            hidden.remove(id)
            changed = true
        }
        windows = found
        if changed { render() }
    }

    /// Every window the window server knows, on any Space, visible or not.
    private func windowServerIDs() -> Set<WindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private func shouldFloat(_ w: AXWindow) -> Bool {
        let cfg = Config.current
        if let b = w.bundleID, cfg.floating.contains(b) { return true }
        if rule(for: w)?.float == true { return true }
        if !w.isResizable { return true }
        // Dialogs: no fullscreen button (AeroSpace's heuristic). Terminals often
        // hide theirs, so they're tiled regardless.
        if cfg.floatDialogs, !w.hasFullscreenButton, !Self.terminals.contains(w.bundleID ?? "") { return true }
        if cfg.floatSmallWindows > 0, let f = w.frame,
           f.width < CGFloat(cfg.floatSmallWindows), f.height < CGFloat(cfg.floatSmallWindows) { return true }
        return false
    }

    private static let terminals: Set<String> = [
        "org.alacritty", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
    ]

    private func appName(of w: AXWindow) -> String {
        NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID ?? "?"
    }

    private func rule(for w: AXWindow) -> Rule? {
        Config.current.rule(bundleID: w.bundleID, appName: appName(of: w), title: w.title)
    }

    private func ruleWorkspace(for w: AXWindow) -> Int? {
        rule(for: w)?.workspace.flatMap(Config.current.workspaceIndex(named:))
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
              ss.workspaceIndex(of: id) != nil else { return }
        if ss.focus(id) {
            touch(id)
            updateBar()
        } else if followHidden {
            followHiddenFocus(id)
        }
    }

    /// Focus landed on a window of a hidden workspace. If you did that
    /// (cmd-tab, Dock, clicking a notification) we follow it there, like
    /// xmonad does. If macOS did it because the window you were using just
    /// closed, we stay put. The close notification can arrive a little after
    /// the activation, so decide after a short pause.
    private func followHiddenFocus(_ id: WindowID) {
        guard !followPending else { return }
        followPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [unowned self] in
            self.followPending = false
            self.refresh()                                   // notices closed windows
            if Date().timeIntervalSince(self.lastWindowGone) < 1.0 {
                Log.info("not following focus to window \(id): macOS activated it after a window closed")
                self.focusCurrent()
                return
            }
            guard self.focusedSystemWindow() == id, let ws = self.ss.workspaceIndex(of: id),
                  !self.ss.isVisible(workspace: ws) else { return }
            Log.info("following focus to window \(id) on workspace \(self.ss.workspaces[ws].tag)")
            self.ss.greedyView(ws)
            self.ss.focus(id)
            self.render()
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
        case .windowSearch: toggleWindowSearch()
        case .appRule: toggleRulePicker()
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
        // While asleep the display list is meaningless (lid closed = no
        // screens); the wake handler calls this again.
        guard !asleep else { return }
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
                                    nMaster: ws.nMaster, ratio: ws.ratio, gap: CGFloat(Config.current.gap),
                                    minSizes: tiled.map { minSize[$0] })
            for (id, r) in zip(tiled, rects) {
                windows[id]?.setFrame(r)
                expected[id] = r.integral
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
        // Only tiled, visible windows have a place to be checked against.
        let placed = Set(ss.screenWorkspace.flatMap { ss.workspaces[$0].windows }).subtracting(ss.floating)
        expected = expected.filter { placed.contains($0.key) }

        focusCurrent()
        updateBar()
        scheduleVerify()
        scheduleSave()
    }

    /// Some apps (Electron, apps that animate) don't take a new size on the
    /// first try. Check shortly after and ask once more; if it still doesn't
    /// fit, the app has a minimum size and we leave it.
    private func scheduleVerify() {
        guard !verifyPending else { return }
        verifyPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [unowned self] in
            self.verifyPending = false
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }     // you're dragging
            // First pass: ask again for every window that isn't where we put it.
            var retried: [WindowID: CGRect] = [:]
            for (id, r) in self.expected {
                guard let w = self.windows[id], let f = w.frame else { continue }
                let off = abs(f.minX - r.minX) > 2 || abs(f.minY - r.minY) > 2
                    || abs(f.width - r.width) > 2 || abs(f.height - r.height) > 2
                guard off else { continue }
                w.setFrame(r)
                retried[id] = r
            }
            guard !retried.isEmpty else { return }
            // Second look a bit later (apps that animate need the time). Whatever
            // is still bigger than asked is that window's minimum size: remember
            // it so the stack makes room instead of letting windows overlap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [unowned self] in
                var learned = false
                for (id, r) in retried where self.expected[id] == r {
                    guard let w = self.windows[id], let g = w.frame,
                          g.width > r.width + 2 || g.height > r.height + 2 else { continue }
                    let old = self.minSize[id] ?? .zero
                    let new = CGSize(width: g.width > r.width + 2 ? max(old.width, g.width) : old.width,
                                     height: g.height > r.height + 2 ? max(old.height, g.height) : old.height)
                    guard new != old else { continue }
                    self.minSize[id] = new
                    learned = true
                    Log.info("window \(id) (\(w.bundleID ?? "?")) needs at least \(Int(new.width))×\(Int(new.height)), making room")
                }
                // Re-tile once with what we learned; the next check finds nothing new.
                if learned { self.render() }
            }
        }
    }

    /// Save the workspace state a moment after every change, so a crash or a
    /// reboot of Kachel puts every window back where it was.
    private func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [unowned self] in
            self.savePending = false
            self.saveSnapshot()
        }
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
            warning = "Kachel needs Accessibility permission. Right-click → Open Accessibility Settings, then switch Kachel on."
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
            touch(f)
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
