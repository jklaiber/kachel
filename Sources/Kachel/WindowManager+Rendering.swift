import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - screens

    func screensChanged() {
        // While asleep the display list is meaningless (lid closed = no
        // screens); the wake handler calls this again.
        guard !asleep else { return }
        // Corners and bar positions moved: applySettings re-parks from scratch.
        applySettings(rebindKeys: false)
        if managing { refresh() }
    }

    /// Displays were plugged in or out (or rearranged): which workspace each
    /// one shows now. Displays are told apart by name, not by position:
    ///  - one that stays keeps its workspace (also when one to its left goes);
    ///  - one that comes gets its pinned workspace (workspace-screens), else
    ///    the one it showed when it was last connected, else a free one;
    ///  - focus stays on the display it was on.
    func assignWorkspaces(after old: [Screen]) {
        // At launch there's nothing to keep (the saved state comes later).
        guard !old.isEmpty else {
            ss.setScreenCount(screens.count)
            return
        }
        let oldKeys = Self.displayKeys(old), newKeys = Self.displayKeys(screens)
        let oldShown = ss.screenWorkspace, oldCurrent = ss.currentScreen
        for (s, key) in oldKeys.enumerated() where s < oldShown.count { lastShownOnDisplay[key] = oldShown[s] }

        var shown = [Int?](repeating: nil, count: screens.count)
        var used = Set<Int>()
        func take(_ s: Int, _ w: Int) { shown[s] = w; used.insert(w) }
        for (s, key) in newKeys.enumerated() {
            if let o = oldKeys.firstIndex(of: key), o < oldShown.count, !used.contains(oldShown[o]) { take(s, oldShown[o]) }
        }
        for s in screens.indices where shown[s] == nil {
            let pinned = ss.workspaces.indices.first { !used.contains($0) && assignedScreen(of: $0) == s }
            let before = lastShownOnDisplay[newKeys[s]].flatMap { used.contains($0) || !ss.workspaces.indices.contains($0) ? nil : $0 }
            if let w = pinned ?? before { take(s, w) }
        }
        for s in screens.indices where shown[s] == nil {
            if let w = ss.workspaces.indices.first(where: { !used.contains($0) }) { take(s, w) }
        }
        let current = oldKeys.indices.contains(oldCurrent) ? newKeys.firstIndex(of: oldKeys[oldCurrent]) : nil
        ss.setScreens(shown.compactMap { $0 }, current: current ?? 0)
        if oldKeys != newKeys {
            Log.info("displays changed: " + zip(screens, ss.screenWorkspace).map { "\($0.name) shows \(ss.workspaces[$1].tag)" }
                .joined(separator: ", "))
        }
    }

    /// A key per display: its name, plus "#2", "#3" for further displays of
    /// the same model (left to right).
    static func displayKeys(_ list: [Screen]) -> [String] {
        var count: [String: Int] = [:]
        return list.map { s in
            count[s.name, default: 0] += 1
            return count[s.name]! == 1 ? s.name : "\(s.name)#\(count[s.name]!)"
        }
    }

    func screenIndex(containing p: CGPoint) -> Int? {
        screens.firstIndex { $0.frame.contains(p) }
    }

    func isOffscreen(_ f: CGRect) -> Bool {
        !screens.contains { $0.visible.intersection(f).width > 40 && $0.visible.intersection(f).height > 40 }
    }

    func centerOnCurrentScreen(_ w: AppWindow, _ size: CGSize) {
        guard ss.currentScreen < screens.count else { return }
        let v = screens[ss.currentScreen].visible
        w.move(to: CGPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2))
    }

    // MARK: - rendering

    /// Make the screen match the model: park hidden workspaces, tile visible ones, focus.
    /// The windows a workspace tiles: all its tiled windows, except when its
    /// layout is Floating or tiling is paused (none), or beyond the window limit.
    func tiledWindows(_ ws: Workspace) -> [WindowID] {
        if tilingPaused || ws.effectiveLayout == .floating { return [] }
        let all = ws.windows.filter { !ss.floating.contains($0) && windows[$0] != nil }
        let limit = Config.current.windowLimit
        return limit > 0 ? Array(all.prefix(limit)) : all
    }

    /// Floating right now: floating windows, and tiled ones the layout leaves alone.
    func floatsNow(_ id: WindowID) -> Bool {
        if ss.floating.contains(id) { return true }
        guard let i = ss.workspaceIndex(of: id) else { return false }
        return !tiledWindows(ss.workspaces[i]).contains(id)
    }

    /// Where display `s` tiles `count` windows, and the gap between them:
    /// edge padding (none on the built-in display if so set), none at all
    /// for a single window with smart gaps.
    func tileArea(_ s: Int, count: Int) -> (rect: CGRect, gap: CGFloat) {
        let cfg = Config.current, scr = screens[s]
        var gap = CGFloat(cfg.gap), pad = CGFloat(cfg.padding ?? cfg.gap)
        if !cfg.builtinPadding, scr.builtin { pad = 0 }
        if cfg.smartGaps, count == 1 { gap = 0; pad = 0 }
        // Layout.tile leaves `gap` at the edges; move them to `pad`.
        return (scr.visible.insetBy(dx: pad - gap, dy: pad - gap), gap)
    }

    func render(refocus: Bool = true) {
        guard !screens.isEmpty else { return }
        let visible = Set(ss.screenWorkspace)

        for (i, ws) in ss.workspaces.enumerated() where !visible.contains(i) {
            ws.windows.forEach(hide)
        }

        // Back on a workspace whose windows we minimized: restore them. They're
        // tiled into their old place once they reappear (see refresh).
        for wsIndex in visible {
            for id in ss.workspaces[wsIndex].windows {
                guard let m = minimizedByUs.removeValue(forKey: id) else { continue }
                if m.wasFocused { refocusWhenBack.insert(id) }
                m.window.setMinimized(false)
            }
        }

        var placed: Set<WindowID> = []
        for (s, wsIndex) in ss.screenWorkspace.enumerated() where s < screens.count {
            let ws = ss.workspaces[wsIndex]
            let scr = screens[s]
            let tiled = tiledWindows(ws)
            let (area, gap) = tileArea(s, count: tiled.count)
            placed.formUnion(tiled)
            let rects = Layout.tile(ws.effectiveLayout, count: tiled.count, in: area,
                                    nMaster: ws.nMaster, ratio: ws.ratio, gap: gap,
                                    minSizes: tiled.map { minSize[$0] },
                                    weights: tiled.map { ws.weights[$0] ?? 1 })
            for (id, r) in zip(tiled, rects) {
                windows[id]?.setFrame(r)
                expected[id] = r.integral
                hidden.remove(id)
            }
            let from = lastScreen[wsIndex]
            for id in ws.windows where windows[id] != nil && !tiled.contains(id) {
                if scratchParked.contains(id) { hide(id); continue }
                if hidden.contains(id) {
                    showFloating(id, on: scr)
                } else if let from, from != s, from < screens.count {
                    // greedyView swapped this workspace onto another screen:
                    // carry its floating windows along.
                    moveFloating(id, from: screens[from], to: scr)
                }
            }
            if ws.effectiveLayout == .full, let f = ws.focused, s != ss.currentScreen {
                windows[f]?.raise()
            }
        }

        lastScreen = [:]
        for (s, wsIndex) in ss.screenWorkspace.enumerated() { lastScreen[wsIndex] = s }
        // Only tiled, visible windows have a place to be checked against.
        expected = expected.filter { placed.contains($0.key) }

        if refocus { focusCurrent() }
        updateBar()
        scheduleVerify()
        scheduleSave()
    }

    /// Some apps (Electron, apps that animate) don't take a new size on the
    /// first try. Check shortly after and ask once more; if it still doesn't
    /// fit, the app has a minimum size and we leave it.
    func scheduleVerify() {
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
    func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [unowned self] in
            self.savePending = false
            self.saveSnapshot()
        }
    }

    func moveFloating(_ id: WindowID, from old: Screen, to new: Screen) {
        guard let w = windows[id], let f = w.frame else { return }
        let rel = f.offsetBy(dx: -old.visible.minX, dy: -old.visible.minY)
        floatRel[id] = rel
        hidden.insert(id)              // showFloating places + clamps it
        showFloating(id, on: new)
    }

    func hide(_ id: WindowID) {
        guard !hidden.contains(id), let w = windows[id], let f = w.frame else { return }
        if rule(for: w)?.hide == .minimize, !scratchWindow.values.contains(id), let ws = ss.workspaceIndex(of: id) {
            minimizedByUs[id] = (w, Date(), ss.workspaces[ws].focused == id)
            Log.info("minimizing window \(id) (\(appName(of: w))): its workspace \(ss.workspaces[ws].tag) is out of sight")
            w.setMinimized(true)
            return
        }
        if floatsNow(id) {
            let s = screenIndex(containing: CGPoint(x: f.midX, y: f.midY)) ?? ss.currentScreen
            let o = screens[min(s, screens.count - 1)].visible.origin
            floatRel[id] = f.offsetBy(dx: -o.x, dy: -o.y)
        }
        w.move(to: hidePoint(for: f))
        hidden.insert(id)
    }

    func showFloating(_ id: WindowID, on scr: Screen) {
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
    func hidePoint(for frame: CGRect) -> CGPoint {
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

    func updateBar() {
        guard !headless else { return }
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
            // Windows you can see on a workspace (not minimized, not a put-away scratchpad).
            func shown(_ ws: Workspace) -> [WindowID] { ws.windows.filter { windows[$0] != nil && !scratchParked.contains($0) } }
            for (i, ws) in ss.workspaces.enumerated() {
                let n = shown(ws).count
                c.tags.append(Bar.Tag(name: ws.tag,
                                      active: i == ss.currentWorkspaceIndex,
                                      visible: ss.isVisible(workspace: i),
                                      hasWindows: n > 0, count: n))
            }
            let ws = ss.workspaces[wsIndex]
            c.layout = tilingPaused ? "Paused" : ws.effectiveLayout.rawValue
            c.isFullLayout = ws.effectiveLayout == .full
            if managing, let f = ws.focused, let w = windows[f] { c.title = w.title }
            if managing {
                c.windows = shown(ws).compactMap { id in
                    guard let w = windows[id] else { return nil }
                    let t = w.title.isEmpty ? appName(of: w) : w.title
                    return Bar.Window(id: id, title: t, focused: id == ws.focused)
                }
            }
            contents.append(c)
        }
        bar.update(contents, warning: warning)
    }

    func focusCurrent() {
        ignoreFocusEventsUntil = Date().addingTimeInterval(0.3)
        ensureFocus()
        let ws = ss.current
        if let f = ws.focused, let w = windows[f] {
            touch(f)
            w.focus()
            DispatchQueue.main.async { self.updateBorder() }
        } else if !headless {
            border.hide()
            // Empty workspace: take focus ourselves so keystrokes don't go
            // to a window that's parked in a corner.
            NSApp.activate(ignoringOtherApps: true)
        }
        guard !headless else { return }       // tests never move your pointer
        // Pointer follows focus, unless it's already there (so clicks and
        // focus-follows-mouse never make it jump).
        let mouse = CGEvent(source: nil)?.location ?? .zero
        switch Config.current.mouseFollowsFocus {
        case .off:
            break
        case .screen:
            if ss.currentScreen < screens.count {
                let scr = screens[ss.currentScreen]
                if !scr.frame.contains(mouse) { CGWarpMouseCursorPosition(CGPoint(x: scr.frame.midX, y: scr.frame.midY)) }
            }
        case .window:
            if let f = ws.focused, let frame = expected[f] ?? windows[f]?.frame, !frame.contains(mouse),
               !hidden.contains(f) {
                CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
            } else if ws.focused == nil, ss.currentScreen < screens.count {
                let scr = screens[ss.currentScreen]
                if !scr.frame.contains(mouse) { CGWarpMouseCursorPosition(CGPoint(x: scr.frame.midX, y: scr.frame.midY)) }
            }
        }
    }
}
