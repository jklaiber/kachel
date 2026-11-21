import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - scratchpads

    func scratchpad(named name: String) -> Scratchpad? {
        Config.current.scratchpads.first { $0.name == name }
    }

    func matches(_ w: AppWindow, _ sp: Scratchpad, checkTitle: Bool = true) -> Bool {
        var m = sp.matcher
        if !checkTitle { m.title = nil }
        return m.matches(bundleID: w.bundleID, appName: appName(of: w), title: w.title)
    }

    /// A new window that a scratchpad we just started is waiting for. Titles
    /// are often set a moment later, so only the app has to match.
    func startingScratchpad(for w: AppWindow) -> Scratchpad? {
        for (name, started) in scratchPending where clock.now.timeIntervalSince(started) < 15 {
            guard let sp = scratchpad(named: name), matches(w, sp, checkTitle: false) else { continue }
            // With a title, only the matching window counts: apps like TextEdit
            // reopen other documents at the same time. A window without a
            // title yet (set a moment later) still counts.
            if let t = sp.title, !t.isEmpty, !w.title.isEmpty, !w.title.localizedCaseInsensitiveContains(t) { continue }
            return sp
        }
        return nil
    }

    /// Show it here if it's away (or on another workspace), put it away if
    /// it's showing here; start it if it isn't open.
    func toggleScratchpad(_ name: String) {
        guard let sp = scratchpad(named: name) else { return }
        syncFocusFromSystem(followHidden: false)
        var id = scratchWindow[name].flatMap { windows[$0] != nil ? $0 : nil }
        if id == nil {
            // Adopt an open window that fits (e.g. after a restart).
            let taken = Set(scratchWindow.values)
            id = windows.first { !taken.contains($0.key) && matches($0.value, sp) }?.key
            if let id { scratchWindow[name] = id }
        }
        guard let id else {
            guard let run = sp.run else {
                Log.info("scratchpad \(name): no window and nothing to run")
                NSSound.beep(); return
            }
            Log.info("scratchpad \(name): starting \(run)")
            scratchPending[name] = clock.now
            spawn(run)
            return
        }
        let here = ss.currentWorkspaceIndex
        if ss.workspaceIndex(of: id) == here, !scratchParked.contains(id) {
            Log.info("scratchpad \(name): away")
            scratchParked.insert(id)
            // Back to the window you used before the scratchpad.
            let previous = mru.first { $0 != id && !scratchParked.contains($0) && ss.workspaceIndex(of: $0) == here }
            if let previous { ss.focus(previous) } else { ss.focusOther(than: id, excluding: scratchParked) }
            render()
        } else {
            Log.info("scratchpad \(name): here")
            if ss.workspaceIndex(of: id) != here { ss.shift(id, to: here) }
            ss.floating.insert(id)
            showScratchpad(id, sp)
            render()
        }
    }

    /// Float it at its size and position on the current screen, and focus it.
    func showScratchpad(_ id: WindowID, _ sp: Scratchpad) {
        scratchParked.remove(id)
        guard ss.currentScreen < screens.count, let w = windows[id] else { return }
        let v = screens[ss.currentScreen].visible
        let size = CGSize(width: v.width * sp.width, height: v.height * sp.height)
        let y = sp.position == .top ? v.minY + CGFloat(Config.current.gap) : v.midY - size.height / 2
        w.setFrame(CGRect(x: v.midX - size.width / 2, y: y, width: size.width, height: size.height))
        hidden.remove(id)
        ss.focus(id)
    }

    /// The window you last used (Kachel's own windows don't count), for the
    /// settings window's "from the focused window" buttons.
    func focusedWindowInfo() -> (app: String, title: String)? {
        guard let f = ss.current.focused, let w = windows[f] else { return nil }
        return (w.bundleID ?? appName(of: w), w.title)
    }
}
