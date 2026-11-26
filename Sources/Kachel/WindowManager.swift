import AppKit
import ApplicationServices
import KachelCore

/// AX callback: just forwards to the manager.
let axCallback: AXObserverCallback = { _, element, notification, _ in
    WindowManager.shared.onAXEvent(notification as String, element: element)
}

/// How workspaces work here (same trick as AeroSpace):
/// macOS Spaces can't be driven reliably without disabling SIP, so we don't
/// use them. All windows live on one Space per display. Windows of hidden
/// workspaces are parked in a screen corner with only one pixel showing, and
/// moved back when their workspace is shown. That makes switching instant
/// and lets workspaces move freely between monitors, like in xmonad.
final class WindowManager {
    static let shared = WindowManager(system: AXWindowSystem(), clock: SystemClock(),
                                      store: FileStateStore(url: WindowManager.stateURL))

    /// macOS's windows, or a fake in tests.
    let system: WindowSystem
    /// Tests: no bar, border or overlays, and nothing written to disk (log,
    /// saved state, the watchdog's list).
    let headless: Bool
    /// The time, or a fake one in tests.
    let clock: Clock

    /// Saved state between runs.
    let store: StateStore

    init(system: WindowSystem, clock: Clock, store: StateStore, headless: Bool = false) {
        self.system = system
        self.clock = clock
        self.store = store
        self.headless = headless
    }

    var ss = StackSet(tags: Config.current.workspaces, screenCount: 1, ratio: Config.current.ratio)
    var windows: [WindowID: AppWindow] = [:]
    var screens: [Screen] = []
    var hidden: Set<WindowID> = [] { didSet { scheduleRecordParked() } }
    /// When apps moved their own tiled windows (see correctAppMove).
    var appMoves: [WindowID: [Date]] = [:]
    /// When and where each managed window was last seen, to recognise a
    /// native tab switch (one window of an app vanishes, another appears in
    /// its place).
    var lastSeen: [WindowID: (time: Date, frame: CGRect?)] = [:]
    /// toggle-tiling: windows stay where they are (workspaces still switch).
    var tilingPaused = false
    /// Windows we minimized because their workspace went out of sight (rules
    /// with `hide: minimize`, e.g. a Teams meeting, so the app shows its small
    /// window). Ones you minimized yourself aren't here and stay minimized.
    var minimizedByUs: [WindowID: (window: AppWindow, at: Date, wasFocused: Bool)] = [:] { didSet { scheduleRecordParked() } }
    var recordPending = false

    /// Tell the watchdog what's out of sight, once per run loop pass.
    func scheduleRecordParked() {
        guard !headless, !recordPending else { return }
        recordPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recordPending = false
            let entry = { (id: WindowID) in self.windows[id].map { Watchdog.Parked.Entry(pid: $0.pid, window: id) } }
            Watchdog.record(.init(parked: self.hidden.sorted().compactMap(entry),
                                  minimized: self.minimizedByUs.keys.sorted().compactMap(entry)))
        }
    }
    /// Restored by us; focus them again once they're back.
    var refocusWhenBack: Set<WindowID> = []
    /// Your last key press or click (not Kachel's own shortcuts).
    var lastUserInput = Date.distantPast
    /// The workspace you were on before the last switch, and when you left it
    /// (so macOS keeping an app of it in front doesn't drag you back).
    var shownWorkspace: Int?
    var leftWorkspace: (index: Int, at: Date)?
    /// The window macOS had in front when Kachel showed an empty workspace and
    /// focused it (macOS often leaves that window in front): while it stays
    /// so, it doesn't pull Kachel to its display (#16).
    var frontWhenEmpty: (window: WindowID, screen: Int, at: Date)?
    /// The app holding secure input while it blocks one-sided shortcuts (#12).
    var secureInputHolder: String?
    /// The window focusCurrent last focused, so the log names each change once.
    var lastFocusedByUs: WindowID?
    /// Floating window frames relative to their screen's visible origin, saved on hide.
    var floatRel: [WindowID: CGRect] = [:]
    /// workspace index -> screen it was on at the last render (to detect swaps).
    var lastScreen: [Int: Int] = [:]
    var refreshPending = false
    var ignoreFocusEventsUntil = Date.distantPast
    /// When a window last closed or an app quit. macOS then activates some
    /// other app on its own; that must not drag us to that app's workspace.
    var lastWindowGone = Date.distantPast
    var followPending = false
    /// Between "going to sleep" and shortly after waking: windows and screens
    /// are in flux, so don't draw conclusions from them.
    var asleep = false
    /// While the screen is locked, Accessibility hides every window; tracking
    /// pauses so that doesn't look like all windows went away.
    var locked = false
    /// A tiled window being resized with the mouse; applied on mouse-up.
    var mouseResized: WindowID?
    var mouseUpTimer: Timer?
    var mouseMoved: WindowID?
    /// Where render() put each tiled window, to notice apps that didn't comply.
    var expected: [WindowID: CGRect] = [:]
    var verifyPending = false
    let border = FocusBorder()
    /// Scratchpads: which window each one is, which are put away, which are starting.
    var scratchWindow: [String: WindowID] = [:]
    var scratchParked: Set<WindowID> = []
    var scratchPending: [String: Date] = [:]
    /// What went wrong the last time a scratchpad was started (shown in the
    /// bar until it works).
    var scratchProblems: [String: String] = [:]
    /// Minimum sizes learned from windows that refused to get smaller.
    var minSize: [WindowID: CGSize] = [:]
    var savePending = false
    let bar = Bar()
    let menuBarItem = MenuBarItem()
    let switcher = WindowSwitcher()
    let rulePicker = RulePicker()
    let overview = ShortcutOverview()
    let settingsWindow = SettingsWindow()
    let welcomeWindow = WelcomeWindow()
    var holdTimer: Timer?
    /// Most recently focused first, for ranking search results.
    var mru: [WindowID] = []
    var managing = false
    var hotkeyProblems: [String] = []
    var pollTimer: Timer?
    var pollTick = 0

    /// The workspace each display showed when it was last connected, by
    /// display (see displayKeys), to give it back when it's plugged in again.
    var lastShownOnDisplay: [String: Int] = [:]
    /// The display (see displayKeys) each workspace was last shown on.
    var lastDisplayOfWorkspace: [Int: String] = [:]
    /// Where windows were (by app and title), saved with the state for after
    /// a restart. Captured at quit, sleep, lock and every few minutes, not on
    /// every save: reading titles asks every app.
    var lastMemory: [RememberedWindow] = []
    /// After a restart: windows still to put back, until `rememberUntil`.
    var remembered: [RememberedWindow] = []
    var rememberUntil = Date.distantPast
    /// Their old place in the stack, to keep the order as they come back one by one.
    var restoredOrder: [WindowID: Int] = [:]
    /// workspace-layouts as last applied, to apply only what changed.
    var appliedLayouts: [Int: LayoutKind] = [:]
    var hoverTimer: Timer?
    var systemFocusPending = false

    // MARK: - lifecycle

    /// Runs at launch, before Accessibility is granted: config, bar, hotkeys.
    /// Without this nothing at all is visible while permission is missing.
    func startUI() {
        Log.info("starting Kachel \(AppVersion.string) (pid \(getpid()))")
        Config.load(force: true)
        bar.onClickWorkspace = { [unowned self] s, i in
            guard self.managing else { return }
            self.greedyView(i, onScreen: s)
        }
        bar.onClickWindow = { [unowned self] _, id in
            guard self.managing else { return }
            Log.info("bar click: window \(id)")
            // A tab in another display's bar: go to that display, don't pull its workspace over.
            if let ws = self.ss.workspaceIndex(of: id), let s = self.ss.screen(ofWorkspace: ws) { self.ss.focusScreen(s) }
            self.goToWindow(id)
        }
        bar.onToggleWidget = { [unowned self] w in
            Config.toggleWidget(w)
            self.reload()
        }
        bar.menuActions = menuEntries()
        menuBarItem.entries = { [unowned self] in self.menuEntries() }
        UpdateCheck.shared.onChange = { [unowned self] in self.bar.menuActions = self.menuEntries() }
        switcher.onGo = { [unowned self] id in self.goToWindow(id) }
        switcher.onBring = { [unowned self] id in self.bringWindow(id) }
        switcher.onCancel = { [unowned self] in self.focusCurrent() }
        rulePicker.onCancel = { [unowned self] in self.focusCurrent() }
        bar.onToggleMenuBarIcon = { [unowned self] in
            Config.setTopLevel(key: "menubar-icon", value: Config.current.menubarIcon ? "false" : "true")
            self.reload()
        }
        applySettings()
        // First launch, or no Accessibility yet: the welcome window explains what to do.
        // Once the app has finished launching (windows ordered front before
        // that don't show up): the welcome window first, then macOS's own
        // Accessibility request on top of it, which also lists Kachel there.
        DispatchQueue.main.async { [unowned self] in
            guard !AXIsProcessTrusted() else { self.welcomeWindow.showOnFirstLaunch(); return }
            self.welcomeWindow.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [unowned self] _ in
            self.screensChanged()
        }
        // Picks up config edits; does the AX safety-net refresh once managing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
            if Config.load() { self.applySettings() }
            self.pollTick += 1
            if self.managing, self.pollTick % 2 == 0 { self.refresh(); self.updateBar() }
            if self.managing, !self.locked, !self.asleep, self.pollTick % 300 == 0 { self.rememberWindows() }
            self.checkSecureInput()
        }
    }

    /// Shared by the menu bar icon and the bar's right-click menu.
    func menuEntries() -> [(title: String, action: () -> Void)] {
        let update: [(title: String, action: () -> Void)] = UpdateCheck.shared.available.map {
            [("Update Available: Kachel \($0.version)…", { UpdateCheck.shared.showDetails() }), ("-", {})]
        } ?? []
        return update + [
            ("About Kachel", { AppVersion.showAbout() }),
            ("Settings…", { [unowned self] in self.settingsWindow.show() }),
            ("Keyboard Shortcuts", { [unowned self] in self.showOverview(hint: "Press any key to close") }),
            ("Welcome and Setup Check…", { [unowned self] in self.welcomeWindow.show() }),
            ("-", {}),
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
        AppResponsiveness.shared.onAnswersAgain = { [unowned self] pid in self.appAnswersAgain(pid) }
        Watchdog.spawn()
        // One-sided shortcuts (mod: left-alt) couldn't start without it.
        if !Config.current.modSides.isEmpty {
            hotkeyProblems = HotKeys.shared.bind(Config.current.keys, sides: Config.current.modSides) { [unowned self] cmd in self.perform(cmd) }
        }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [unowned self] _ in
            self.scheduleRefresh()
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [unowned self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.system.appQuit(app.processIdentifier)
            }
            self.lastWindowGone = Date()
            self.scheduleRefresh()
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [unowned self] _ in
            self.systemFocusChanged()
            self.keepBorderAbove()           // the app may raise its window over the frame
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [unowned self] _ in
            self.scheduleRefresh()
        }
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [unowned self] _ in
                if !self.asleep {
                    Log.info("sleeping: pausing window tracking")
                    self.rememberWindows()
                    self.saveSnapshot()
                }
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
                    self.restoreFocusIfLost(reason: "wake")
                }
            }
        }
        // The lock screen takes focus and macOS doesn't always give it back.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [unowned self] _ in
            Log.info("screen locked: pausing window tracking")
            if self.managing { self.rememberWindows(); self.saveSnapshot() }
            self.locked = true
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [unowned self] _ in
            Log.info("screen unlocked")
            self.locked = false
            // The lock screen lets go a moment after the notification; try
            // again a little later in case it still had focus the first time.
            for delay in [0.5, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [unowned self] in
                    self.restoreFocusIfLost(reason: "unlock", force: true)
                }
            }
        }

        adoptExistingWindows()
        // You just granted Accessibility in System Settings: come back to the
        // welcome window and its next checks (after the windows above settled).
        if welcomeWindow.isOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [unowned self] in self.welcomeWindow.bringToFront() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [unowned self] _ in self.pointerMoved() }
        // Holding the modifier alone shows the shortcut overview; anything else hides it.
        let watched: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        NSEvent.addGlobalMonitorForEvents(matching: watched) { [unowned self] e in self.modifierEvent(e) }
        NSEvent.addLocalMonitorForEvents(matching: watched) { [unowned self] e in self.modifierEvent(e); return e }
        updateGestures()
    }

    /// (Re)apply Config.current: hotkeys, workspaces, bar, screen geometry.
    func applySettings(rebindKeys: Bool = true) {
        let cfg = Config.current
        if rebindKeys, !headless {
            hotkeyProblems = HotKeys.shared.bind(cfg.keys, sides: cfg.modSides) { [unowned self] cmd in self.perform(cmd) }
        }
        ss.setTags(cfg.workspaces)
        // A changed config may have fixed a scratchpad: try again before warning.
        scratchProblems = [:]
        ss.insertPosition = cfg.newWindows
        ss.setLayoutIfUnlisted(cfg.layouts)
        applyWorkspaceLayouts()
        if !headless {
            menuBarItem.setVisible(cfg.menubarIcon)
            UpdateCheck.shared.apply(enabled: cfg.checkForUpdates)
            LoginItem.apply(cfg.startAtLogin)
            updateGestures()
            bar.menuBarIconShown = cfg.menubarIcon
        }
        let old = screens
        screens = system.screens(reserveBottom: cfg.bar.enabled && !headless ? Bar.height(for: cfg.bar) : 0)
        assignWorkspaces(after: old)
        if !headless { bar.place(on: screens, settings: cfg.bar) }
        if managing {
            hidden.removeAll()       // geometry may have changed: re-park from scratch
            // While you're in one of Kachel's own windows (Settings, the welcome
            // window, About), a reload mustn't hand focus to another app's window.
            render(refocus: headless || !NSApp.isActive)
        } else {
            updateBar()
        }
    }

    /// workspace-layouts: set what's configured, at the start (`force`) or
    /// when the config changed for that workspace.
    func applyWorkspaceLayouts(force: Bool = false) {
        let cfg = Config.current
        for i in ss.workspaces.indices {
            let want = cfg.configuredLayout(forWorkspace: i)
            if let want, force || appliedLayouts[i] != want {
                ss.setLayout(want, workspace: i)
            }
            appliedLayouts[i] = want
        }
    }

    /// Secure input blocks the one-sided shortcuts (they go through an event
    /// tap): say so, and who holds it, instead of shortcuts silently failing.
    func checkSecureInput() {
        let holder = HotKeys.shared.usesTap ? SecureInput.holder() : nil
        guard holder != secureInputHolder else { return }
        secureInputHolder = holder
        if let holder {
            Log.info("secure input is on (\(holder)): one-sided shortcuts are blocked until it's off")
        } else {
            Log.info("secure input is off: shortcuts work again")
        }
        updateBar()
    }

    func reload() {
        Config.load(force: true)
        applySettings()
    }

    /// On startup every existing window joins the workspace shown on the
    /// screen it currently sits on.
    func adoptExistingWindows() {
        let found = system.windows(known: windows)
        if let saved = loadSaved() {
            if abs(saved.boot - system.bootTime) < 1 {
                ss.restore(saved.state, existing: Set(found.keys))
                Log.info("restored \(ss.allWindows.count) of \(found.count) windows to their workspaces from the last run")
            } else {
                // Window IDs started over: keep the workspaces' layouts and
                // sizes, and put windows back by app and title as they come.
                ss.restore(saved.state, existing: [])
                remembered = saved.memory ?? []
                lastMemory = remembered
                rememberUntil = clock.now.addingTimeInterval(600)
                Log.info("after a restart: layouts back, \(remembered.count) windows to put back by app and title")
            }
        }
        // The saved state brought back layouts; configured ones start as configured.
        applyWorkspaceLayouts(force: true)
        let placed = takeRemembered(found.filter { ss.workspaceIndex(of: $0.key) == nil })
        for (id, w) in found.sorted(by: { $0.key < $1.key }) where ss.workspaceIndex(of: id) == nil {
            if let m = placed[id] {
                putBack(id, m)
                continue
            }
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
                return "\(id)\(tag.isEmpty ? "" : "[\(tag)]") \(w?.bundleID ?? "?") \(Log.title(w?.title ?? "")) \(Log.frame(w?.frame))"
            }
            Log.info("  ws \(ws.tag) \(ws.layout.rawValue) focused=\(ws.focused.map(String.init) ?? "-"):")
            list.forEach { Log.info("    \($0)") }
        }
    }

    func quit() {
        if managing { rememberWindows(); saveSnapshot() }
        restoreAllWindows()
        // Moving windows back happens on each app's queue: let it finish
        // (a hung app gets 1.5 s; the watchdog file still lists its windows).
        AppResponsiveness.shared.flush(timeout: 1.5)
        Watchdog.stop()
        Ctl.stopListening()
        HotKeys.shared.unbindAll()
        Log.info("quit")
        exit(0)
    }

    /// Quit and start again; windows keep their workspaces (see saveSnapshot).
    func restart() {
        Log.info("restarting")
        if managing { rememberWindows(); saveSnapshot() }
        restoreAllWindows()
        // Moving windows back happens on each app's queue: let it finish
        // (a hung app gets 1.5 s; the watchdog file still lists its windows).
        AppResponsiveness.shared.flush(timeout: 1.5)
        Watchdog.stop()
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

}
