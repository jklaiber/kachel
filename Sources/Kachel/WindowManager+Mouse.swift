import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - mouse resize of the master split

    func waitForMouseUp() {
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
    func applyMouseResize(_ id: WindowID) {
        guard let wsIndex = ss.workspaceIndex(of: id), !floatsNow(id),
              let s = ss.screen(ofWorkspace: wsIndex), s < screens.count,
              let frame = windows[id]?.frame else { return }
        let ws = ss.workspaces[wsIndex]
        let tiled = tiledWindows(ws)
        guard let i = tiled.firstIndex(of: id) else { render(); return }
        let kind = ws.effectiveLayout
        let (area, gap) = tileArea(s, count: tiled.count)
        let before = expected[id] ?? frame
        let dw = abs(frame.width - before.width), dh = abs(frame.height - before.height)
        // Which way the split runs vs. which way windows share a column.
        let splitChanged = kind == .mirrorTall ? dh > 4 : dw > 4
        let columnChanged = (kind == .mirrorTall || kind == .column) ? dw > 4 : dh > 4
        if splitChanged, let r = Layout.ratio(afterResizing: frame, index: i, count: tiled.count, kind: kind,
                                              in: area, nMaster: ws.nMaster, gap: gap) {
            Log.info("mouse resize: workspace \(ws.tag) ratio \(String(format: "%.2f", ws.ratio)) → \(String(format: "%.2f", r))")
            ss.setRatio(r, workspace: wsIndex)
            Haptics.tap()
        }
        if columnChanged, let w = Layout.weights(afterResizing: frame, index: i, count: tiled.count, kind: kind,
                                                 in: area, nMaster: ws.nMaster, ratio: ss.workspaces[wsIndex].ratio,
                                                 gap: gap, weights: tiled.map { ws.weights[$0] ?? 1 }) {
            Log.info("mouse resize: window \(id) share \(String(format: "%.2f", w[i])) in its column")
            ss.setWeights(Dictionary(uniqueKeysWithValues: zip(tiled, w)), workspace: wsIndex)
        }
        render()
    }

    // MARK: - trackpad swipes

    func updateGestures() {
        let g = Config.current.gestures
        let g2 = Gestures.shared
        g2.onSwipe = { [unowned self] dir in self.swiped(dir) }
        if managing && g.enabled { g2.start(fingers: g.fingers) } else { g2.stop() }
    }

    /// A swipe acts on the screen under the pointer, like the macOS one.
    func swiped(_ dir: Gestures.Direction) {
        guard managing, !switcher.isOpen, !rulePicker.isOpen else { return }
        Haptics.tap()
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
            let here = ss.currentScreen
            guard let target = ss.cycleTarget(d, skipEmpty: g.skipEmpty,
                                              allowed: { self.assignedScreen(of: $0).map { $0 == here } ?? true }) else {
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
    func applyMouseMove(_ id: WindowID) {
        guard let from = ss.workspaceIndex(of: id), !floatsNow(id),
              let primary = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let drop = CGPoint(x: m.x, y: primary.frame.height - m.y)
        guard let s = screenIndex(containing: drop) else { render(); return }
        let wsIndex = ss.screenWorkspace[s]
        let target = ss.workspaces[wsIndex].windows.first { t in
            t != id && !floatsNow(t) && (expected[t] ?? windows[t]?.frame)?.contains(drop) == true
        }
        if target != nil || wsIndex != from { Haptics.tap() }
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

    // MARK: - focus follows mouse


    /// The pointer moved: once it rests (120 ms), focus the window under it.
    /// Resting avoids focusing every window the pointer passes over.
    func pointerMoved() {
        guard Config.current.focusFollowsMouse else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [unowned self] _ in
            self.focusWindowUnderPointer()
        }
    }

    func focusWindowUnderPointer() {
        guard managing, NSEvent.pressedMouseButtons == 0, !switcher.isOpen, !rulePicker.isOpen, !asleep, !locked,
              let primary = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x, y: primary.frame.height - m.y)
        // Only inside the tiling area: not over the bar, the menu bar or the Dock.
        guard screens.contains(where: { $0.visible.contains(p) }) else { return }
        // The topmost normal window under the pointer, front to back.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(p),
                  let n = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            // The first window there decides: if it isn't one of ours, leave focus alone.
            guard let w = windows[n], ss.workspaceIndex(of: n) != nil, !hidden.contains(n),
                  n != ss.current.focused || focusedSystemWindow() != n else { return }
            ss.focus(n)
            touch(n)
            ignoreFocusEventsUntil = clock.now.addingTimeInterval(0.3)
            w.focus()
            updateBar()
            updateBorder()
            return
        }
    }
}
