import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - actions (bound in Config.swift)

    func perform(_ cmd: Command) {
        holdTimer?.invalidate()
        if case .shortcuts = cmd {} else { overview.hide() }
        Log.info("command \(cmd)")
        locked = false   // keys only reach us when unlocked, in case the unlock went unnoticed
        guard managing else {
            Log.info("ignoring \(cmd): no Accessibility permission yet")
            if case .quit = cmd { quit() }
            if case .reload = cmd { reload() }
            if case .restart = cmd { restart() }
            if case .settings = cmd { settingsWindow.show() }
            if case .welcome = cmd { welcomeWindow.show() }
            return
        }
        let step = Config.current.ratioStep
        switch cmd {
        case .greedyView(let i):
            // workspace-back-and-forth: the key of the workspace you're on goes back.
            if Config.current.workspaceBackAndForth, i == ss.currentWorkspaceIndex, let p = ss.previousWorkspace {
                greedyView(p)
            } else {
                greedyView(i)
            }
        case .workspaceBack:
            syncFocusFromSystem(followHidden: false)
            if let p = ss.previousWorkspace { greedyView(p) }
        case .taller: act { $0.scaleFocusedWeight(1.25) }
        case .shorter: act { $0.scaleFocusedWeight(0.8) }
        case .resetSizes: act { $0.resetSizes(ratio: Config.current.ratio) }
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
        case .prevLayout: act { $0.prevLayout(in: Config.current.layouts) }
        case .setLayout(let k): act { $0.setLayout(k) }
        case .toggleTiling:
            tilingPaused.toggle()
            Log.info(tilingPaused ? "tiling paused: windows stay where they are" : "tiling resumed")
            render()
        case .toggleFocusFollowsMouse:
            Config.setTopLevel(key: "focus-follows-mouse", value: Config.current.focusFollowsMouse ? "false" : "true")
            reload()
        case .increaseWindowLimit, .decreaseWindowLimit:
            // From "no limit", fewer starts at one less than what's tiled now.
            let now = Config.current.windowLimit
            let tiledNow = ss.current.windows.filter { !ss.floating.contains($0) && windows[$0] != nil }.count
            let new = cmd == .increaseWindowLimit
                ? (now == 0 ? 0 : now + 1)
                : max(1, (now == 0 ? tiledNow : now) - 1)
            Config.setTopLevel(key: "window-limit", value: String(new))
            reload()
        case .focusNextScreen: focusScreen(ss.neighbourScreen(+1))
        case .focusPrevScreen: focusScreen(ss.neighbourScreen(-1))
        case .shiftToNextScreen: shiftToScreen(ss.neighbourScreen(+1))
        case .shiftToPrevScreen: shiftToScreen(ss.neighbourScreen(-1))
        case .workspaceNext: syncFocusFromSystem(followHidden: false); greedyView(ss.neighbour(+1))
        case .workspacePrev: syncFocusFromSystem(followHidden: false); greedyView(ss.neighbour(-1))
        case .shiftNext: syncFocusFromSystem(followHidden: false); shift(to: ss.neighbour(+1))
        case .shiftPrev: syncFocusFromSystem(followHidden: false); shift(to: ss.neighbour(-1))
        case .restart: restart()
        case .settings: settingsWindow.show()
        case .welcome: welcomeWindow.show()
        case .shortcuts: overview.isOpen ? overview.hide() : showOverview(hint: "Press any key to close")
        case .windowSearch: toggleWindowSearch()
        case .appRule: toggleRulePicker()
        case .toggleFullscreen: act { $0.toggleFullscreen() }
        case .focusDirection(let d): focusDirection(d, swap: false)
        case .swapDirection(let d): focusDirection(d, swap: true)
        case .scratchpad(let name): toggleScratchpad(name)
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
        ss.focusScreen(assignedScreen(of: i) ?? s)
        ss.greedyView(i)
        render()
    }

    func greedyView(_ i: Int) {
        syncFocusFromSystem(followHidden: false)
        show(i)
        render()
    }

    /// Bring workspace `i` up: on its pinned screen if it has one
    /// (workspace-screens), otherwise here (greedyView).
    func show(_ i: Int) {
        if let s = assignedScreen(of: i), s != ss.currentScreen { ss.focusScreen(s) }
        ss.greedyView(i)
    }

    /// The screen a workspace is pinned to, if that screen is connected.
    func assignedScreen(of i: Int) -> Int? {
        let cfg = Config.current
        guard ss.workspaces.indices.contains(i),
              let pattern = cfg.workspaceScreens[ss.workspaces[i].tag] ?? cfg.workspaceScreens["\(i + 1)"] else { return nil }
        let main = NSScreen.screens.first
        let infos = screens.map { ScreenInfo(name: $0.ns.localizedName, builtin: $0.builtin, main: $0.ns == main) }
        return ScreenMatcher.index(for: pattern, in: infos)
    }
    func view(_ i: Int)       { syncFocusFromSystem(followHidden: false); ss.view(i); render() }

    func shift(to i: Int) {
        syncFocusFromSystem(followHidden: false)
        guard let f = ss.current.focused else { return }
        ss.shift(f, to: i)
        if Config.current.followMovedWindows, i != ss.currentWorkspaceIndex {
            show(i)                     // go with it
            ss.focus(f)
        }
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

    // offScreen() reads the state, so it runs before act() starts changing it.
    func focusDown()   { let skip = offScreen(); act { $0.focusDown(skipping: skip) } }
    func focusUp()     { let skip = offScreen(); act { $0.focusUp(skipping: skip) } }
    func focusMaster() { act { $0.focusMaster() } }
    func swapDown()    { let skip = offScreen(); act { $0.swapDown(skipping: skip) } }
    func swapUp()      { let skip = offScreen(); act { $0.swapUp(skipping: skip) } }
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

    /// Windows of the current workspace that aren't on screen: kept after
    /// closing (no Accessibility window), put-away scratchpads.
    func offScreen() -> Set<WindowID> {
        Set(ss.current.windows.filter { windows[$0] == nil || scratchParked.contains($0) })
    }

    func act(_ f: (inout StackSet) -> Void) {
        syncFocusFromSystem(followHidden: false)
        f(&ss)
        render()
    }
}
