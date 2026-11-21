import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - window discovery

    func onAXEvent(_ notification: String, element: AXUIElement) {
        if notification == kAXWindowMovedNotification || notification == kAXWindowResizedNotification,
           let id = axWindowID(element), id == ss.current.focused {
            updateBorder()
        }
        if notification == kAXWindowMovedNotification {
            // A drag with the mouse (title bar): swap on drop, see applyMouseMove.
            if NSEvent.pressedMouseButtons & 1 != 0, let id = axWindowID(element), windows[id] != nil {
                mouseMoved = id
                waitForMouseUp()
            } else if let id = axWindowID(element) {
                correctAppMove(id)
            }
            return
        }
        if notification == kAXWindowResizedNotification {
            // Only your own drags count: the mouse button is down. Apps that
            // refuse a size we asked for must not move the split.
            if NSEvent.pressedMouseButtons & 1 != 0, let id = axWindowID(element), windows[id] != nil {
                mouseResized = id
                waitForMouseUp()
            } else if let id = axWindowID(element) {
                correctAppMove(id)
            }
            return
        }
        if notification == kAXUIElementDestroyedNotification {
            lastWindowGone = clock.now
        }
        if notification == kAXFocusedWindowChangedNotification {
            systemFocusChanged()
        }
        scheduleRefresh()
    }

    /// An app moved or resized one of its tiled windows by itself, e.g. iTerm
    /// sizing a tmux window to its session after we tiled it. Put it back (the
    /// verify pass also learns a real minimum size), at most a few times per
    /// window and minute so we never fight an app.
    func correctAppMove(_ id: WindowID) {
        guard expected[id] != nil else { return }
        let now = clock.now
        var log = appMoves[id, default: []].filter { now.timeIntervalSince($0) < 60 }
        guard log.count < 4 else { return }
        log.append(now)
        appMoves[id] = log
        scheduleVerify()
    }

    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        clock.after(0.05) { [unowned self] in
            self.refreshPending = false
            self.refresh()
        }
    }

    /// Reconcile our model with the windows that actually exist.
    func refresh() {
        guard !asleep, !locked else { return }
        let found = system.windows(known: windows)
        var changed = false
        let focusedBefore = ss.workspaces.map(\.focused)
        var missing = ss.allWindows.filter { found[$0] == nil }
        // Native tabs (Finder, Terminal, TextEdit): macOS shows each tab as its own
        // window. Switching tabs hides one and shows another; closing a tab removes
        // one and shows another. Either way the window that appears in the very
        // spot of the app's window that just went away takes its place.
        for (id, w) in found.sorted(by: { $0.key < $1.key }) where ss.workspaceIndex(of: id) == nil && !missing.isEmpty {
            guard let f = w.frame, let old = missing.first(where: { o in
                guard windows[o]?.pid == w.pid, let seen = lastSeen[o], let g = seen.frame,
                      clock.now.timeIntervalSince(seen.time) < 3.5 else { return false }
                return abs(g.minX - f.minX) < 8 && abs(g.minY - f.minY) < 8
                    && abs(g.width - f.width) < 8 && abs(g.height - f.height) < 8
            }), let wsIndex = ss.workspaceIndex(of: old) else { continue }
            ss.replace(old, with: id)
            if focusedBefore.indices.contains(wsIndex), focusedBefore[wsIndex] == old { ss.focus(id) }
            missing.removeAll { $0 == old }
            hidden.remove(old)
            Log.info("tab switch in \(appName(of: w)): window \(id) takes the place of \(old)")
            changed = true
        }
        if !missing.isEmpty {
            // Accessibility sometimes reports no windows at all: during sleep,
            // for busy apps, for minimized or fullscreen windows. Only forget a
            // window once the window server says it's really gone, or it would
            // lose its workspace and come back on the current one.
            let alive = system.windowServerIDs()
            let gone = Set(missing)
            for id in missing {
                if alive.contains(id) {
                    // Still there, just not showing (closed but kept by its app,
                    // minimized, asleep): keep its workspace, but tile without it
                    // and don't leave focus on it.
                    if windows[id] != nil {
                        changed = true
                        Log.info("window \(id) (\(windows[id].map(appName) ?? "?")) not listed by Accessibility, but it still exists: "
                                 + "keeping it on workspace \(ss.workspaceIndex(of: id).map { ss.workspaces[$0].tag } ?? "?")")
                    }
                    if id == ss.current.focused, let w = ss.workspaceIndex(of: id) {
                        refocus(afterLosing: id, in: w, gone: gone)
                    } else {
                        ss.focusOther(than: id, excluding: gone)
                    }
                    continue
                }
                Log.info("window \(id) (\(windows[id].map(appName) ?? "?")) closed (was on workspace \(ss.workspaceIndex(of: id).map { ss.workspaces[$0].tag } ?? "?"))")
                // The welcome window's buttons open System Settings: closing it
                // takes you back there, not to another window.
                if windows[id]?.bundleID == "com.apple.systempreferences", welcomeWindow.isOpen {
                    clock.after(0.3) { [unowned self] in self.welcomeWindow.bringToFront() }
                }
                let wsOfClosed = ss.workspaceIndex(of: id)
                let wasFocused = id == ss.current.focused
                ss.remove(id)
                if wasFocused, let w = wsOfClosed { refocus(afterLosing: id, in: w, gone: gone) }
                hidden.remove(id)
                floatRel[id] = nil
                minSize[id] = nil
                scratchParked.remove(id)
                scratchWindow = scratchWindow.filter { $0.value != id }
                changed = true
                lastWindowGone = clock.now
            }
        }
        // Windows coming back (after sleep, un-minimized, app answering again)
        // keep their workspace; just put them in place.
        for (id, w) in found.sorted(by: { $0.key < $1.key }) where windows[id] == nil && ss.workspaceIndex(of: id) != nil {
            Log.info("window \(id) (\(appName(of: w))) is back on workspace \(ss.workspaces[ss.workspaceIndex(of: id)!].tag), \(Log.frame(w.frame))")
            changed = true
        }
        // Several new at once (an app restoring its windows): in the order
        // they were opened, which is the order of their IDs.
        for (id, w) in found.sorted(by: { $0.key < $1.key }) where ss.workspaceIndex(of: id) == nil {
            if shouldFloat(w) {
                ss.floating.insert(id)
                if let f = w.frame, isOffscreen(f) { centerOnCurrentScreen(w, f.size) }
                if floatsOnlyAsDialog(w) { recheckDialog(id) }
            }
            Log.info("new window \(id): \(appName(of: w)) (\(w.bundleID ?? "?")) \(Log.title(w.title)), \(Log.frame(w.frame))"
                     + (ss.floating.contains(id) ? ", floats (\(floatReason(w)))" : ""))
            if let sp = startingScratchpad(for: w) {
                scratchPending[sp.name] = nil
                scratchWindow[sp.name] = id
                ss.floating.insert(id)
                ss.insert(id)
                hidden.remove(id)
                windows[id] = w
                showScratchpad(id, sp)
                changed = true
                continue
            }
            if let ws = ruleWorkspace(for: w), ws != ss.currentWorkspaceIndex {
                // A rule sends it elsewhere (xmonad doShift): it appears there, you stay here.
                ss.insert(id, into: ws)
                Log.info("rule: \(appName(of: w)) window \(id) → workspace \(ss.workspaces[ws].tag)")
            } else if ss.floating.contains(id), let f = w.frame,
                      let s = screenIndex(containing: CGPoint(x: f.midX, y: f.midY)), s != ss.currentScreen,
                      s < ss.screenWorkspace.count {
                // A dialog the app opened on another display belongs to the
                // workspace shown there, not to the one you're on, or ⌥J/⌥K
                // would cycle across displays to it.
                let ws = ss.screenWorkspace[s]
                ss.insert(id, into: ws)
                Log.info("new window \(id) is on display \(s + 1): joins workspace \(ss.workspaces[ws].tag)")
            } else {
                ss.insert(id)           // new windows land on the current workspace
            }
            hidden.remove(id)
            changed = true
        }
        for (id, _) in found {
            if refocusWhenBack.remove(id) != nil, let ws = ss.workspaceIndex(of: id), ss.isVisible(workspace: ws) {
                ss.focus(id)
                changed = true
            }
            // Restored while its workspace is out of sight, and not by us: you
            // clicked the app's small window or the Dock. Go there, like macOS
            // switches to the window's Space. (Shortly after we minimized it,
            // it can still look restored: that's the animation, not you.)
            guard let m = minimizedByUs[id], clock.now.timeIntervalSince(m.at) > 1.0 else { continue }
            minimizedByUs[id] = nil
            if let ws = ss.workspaceIndex(of: id), !ss.isVisible(workspace: ws) {
                Log.info("window \(id) was restored from another workspace: showing workspace \(ss.workspaces[ws].tag)")
                show(ws)
            }
            ss.focus(id)
            changed = true
        }
        windows = found
        if changed { render() }
        // Remember where every managed window is (tiled: where we put it).
        // After render, so a window tiled just now is known in its new place:
        // a tab switch right after it appeared must still be recognised.
        let now = clock.now
        for (id, w) in found where ss.workspaceIndex(of: id) != nil {
            lastSeen[id] = (now, expected[id] ?? (ss.floating.contains(id) ? w.frame : lastSeen[id]?.frame))
        }
        lastSeen = lastSeen.filter { ss.workspaceIndex(of: $0.key) != nil }
    }

    func shouldFloat(_ w: AppWindow) -> Bool {
        let cfg = Config.current
        if rule(for: w)?.float == true { return true }
        if !w.isResizable { return true }
        // Dialogs: no fullscreen button (AeroSpace's heuristic). Terminals often
        // hide theirs, so they're tiled regardless.
        if cfg.floatDialogs, !w.hasFullscreenButton, !Self.terminals.contains(w.bundleID ?? "") { return true }
        if cfg.floatSmallWindows > 0, let f = w.frame,
           f.width < CGFloat(cfg.floatSmallWindows), f.height < CGFloat(cfg.floatSmallWindows) { return true }
        return false
    }

    /// Why a new window floats, for the log.
    func floatReason(_ w: AppWindow) -> String {
        if rule(for: w)?.float == true { return "rule" }
        if !w.isResizable { return "not resizable" }
        if !w.hasFullscreenButton { return "no fullscreen button: a dialog" }
        return "small"
    }

    /// Floats only because it has no fullscreen button yet; some apps (often
    /// Electron) add it a moment after the window appears.
    func floatsOnlyAsDialog(_ w: AppWindow) -> Bool {
        let cfg = Config.current
        guard cfg.floatDialogs, !w.hasFullscreenButton, rule(for: w)?.float != true, w.isResizable else { return false }
        if cfg.floatSmallWindows > 0, let f = w.frame,
           f.width < CGFloat(cfg.floatSmallWindows), f.height < CGFloat(cfg.floatSmallWindows) { return false }
        return true
    }

    /// Look again shortly after: if the window got its fullscreen button, it's
    /// a normal window after all and gets tiled.
    func recheckDialog(_ id: WindowID) {
        for delay in [0.5, 1.5] {
            clock.after(delay) { [unowned self] in
                guard self.ss.floating.contains(id), let w = self.windows[id], w.hasFullscreenButton else { return }
                Log.info("window \(id) (\(self.appName(of: w))) turned out to be a normal window: tiling it")
                self.ss.floating.remove(id)
                self.render()
            }
        }
    }

    static let terminals: Set<String> = [
        "org.alacritty", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
    ]

    func appName(of w: AppWindow) -> String {
        NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID ?? "?"
    }

    func rule(for w: AppWindow) -> Rule? {
        Config.current.rule(bundleID: w.bundleID, appName: appName(of: w), title: w.title)
    }

    func ruleWorkspace(for w: AppWindow) -> Int? {
        rule(for: w)?.workspace.flatMap(Config.current.workspaceIndex(named:))
    }
}
