import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - directional focus

    /// Focus (or swap with) the window in a direction, across screens.
    func focusDirection(_ d: Direction, swap: Bool) {
        syncFocusFromSystem(followHidden: false)
        guard let f = ss.current.focused, let from = windows[f]?.frame else { return }
        var candidates: [(id: WindowID, frame: CGRect)] = []
        for wsIndex in ss.screenWorkspace {
            for id in ss.workspaces[wsIndex].windows where id != f && !scratchParked.contains(id) && !hidden.contains(id) {
                if let fr = windows[id]?.frame { candidates.append((id, fr)) }
            }
        }
        guard let target = Navigation.neighbour(of: from, in: d, among: candidates) else { return }
        if swap {
            ss.swap(f, target)
            ss.focus(f)
        } else {
            ss.focus(target)
        }
        render()
    }

    // MARK: - focus tracking (mouse clicks, cmd-tab, …)

    func focusedSystemWindow() -> WindowID? { system.focusedWindow() }

    /// Pull the real focus into the model. If the user cmd-tabbed to a
    /// window on a hidden workspace, bring that workspace here.
    /// The focused window went away: stay on its screen and focus the window
    /// you used most recently on that workspace (not whatever macOS picks,
    /// which is often on another screen).
    func refocus(afterLosing id: WindowID, in wsIndex: Int, gone: Set<WindowID>) {
        if let s = ss.screen(ofWorkspace: wsIndex) { ss.focusScreen(s) }
        let candidates = ss.workspaces[wsIndex].windows.filter {
            $0 != id && !gone.contains($0) && windows[$0] != nil && !scratchParked.contains($0)
        }
        if let next = mru.first(where: candidates.contains) ?? candidates.first {
            ss.focus(next)
        } else {
            ss.focusOther(than: id, excluding: gone.union([id]))
        }
    }


    /// macOS says focus changed (a click, cmd-tab, the Dock, or macOS itself
    /// after a window closed). Wait a moment and look at what happened first:
    /// if a window just went away, macOS's choice is noise and we keep ours.
    func systemFocusChanged() {
        guard !systemFocusPending else { return }
        systemFocusPending = true
        clock.after(0.25) { [unowned self] in
            self.systemFocusPending = false
            guard self.managing, !self.asleep, !self.locked else { return }
            self.refresh()
            if clock.now.timeIntervalSince(self.lastWindowGone) < 1.0 {
                if let f = self.focusedSystemWindow(), f != self.ss.current.focused {
                    Log.info("not following focus to window \(f): macOS picked it after a window closed")
                    self.focusCurrent()
                }
                return
            }
            self.syncFocusFromSystem(followHidden: true)
        }
    }

    /// After unlock or wake: give focus back to the current workspace's
    /// window (the one you used last, else the master) instead of leaving you
    /// to click one. After unlock macOS can still name a window as focused
    /// while nothing is active, so `force` focuses it again regardless.
    /// A workspace with windows always has one focused: the one you used
    /// last, else the master.
    func ensureFocus() {
        let ws = ss.current
        if let f = ws.focused, windows[f] != nil { return }
        let usable = ws.windows.filter { windows[$0] != nil && !scratchParked.contains($0) }
        guard let pick = mru.first(where: usable.contains) ?? usable.first(where: { !ss.floating.contains($0) }) ?? usable.first
        else { return }
        Log.info("workspace \(ws.tag) had no focused window: focusing \(pick)")
        ss.focus(pick)
    }

    func restoreFocusIfLost(reason: String, force: Bool = false) {
        guard managing, !asleep else { return }   // the wake handler calls again
        refresh()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        let sys = focusedSystemWindow()
        if let f = sys, let ws = ss.workspaceIndex(of: f), ss.isVisible(workspace: ws) {
            ss.focus(f)                     // you may have clicked a window already
            if !force { updateBar(); updateBorder(); return }
        }
        ensureFocus()
        guard ss.current.focused != nil else { return }
        Log.info("\(reason): frontmost \(front), focused window \(sys.map(String.init) ?? "none"); focusing \(ss.current.focused!)")
        focusCurrent()
        updateBar()
    }

    func syncFocusFromSystem(followHidden: Bool) {
        guard clock.now > ignoreFocusEventsUntil,
              let id = focusedSystemWindow(),
              ss.workspaceIndex(of: id) != nil else { return }
        let before = ss.current.focused
        if ss.focus(id) {
            if before != id {
                Log.info("macOS focused window \(id) (\(windows[id].map(appName) ?? "?")): following it")
            }
            touch(id)
            updateBar()
            updateBorder()
        } else if followHidden {
            followHiddenFocus(id)
        }
    }

    /// Focus landed on a window of a hidden workspace. If you did that
    /// (cmd-tab, Dock, clicking a notification) we follow it there, like
    /// xmonad does. If macOS did it because the window you were using just
    /// closed, we stay put. The close notification can arrive a little after
    /// the activation, so decide after a short pause.
    func followHiddenFocus(_ id: WindowID) {
        guard !followPending else { return }
        followPending = true
        clock.after(0.25) { [unowned self] in
            self.followPending = false
            self.refresh()                                   // notices closed windows
            if clock.now.timeIntervalSince(self.lastWindowGone) < 1.0 {
                Log.info("not following focus to window \(id): macOS activated it after a window closed")
                self.focusCurrent()
                return
            }
            guard self.focusedSystemWindow() == id, let ws = self.ss.workspaceIndex(of: id),
                  !self.ss.isVisible(workspace: ws) else { return }
            Log.info("following focus to window \(id) on workspace \(self.ss.workspaces[ws].tag)")
            self.show(ws)
            self.ss.focus(id)
            self.render()
        }
    }
}
