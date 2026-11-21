import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - state across restarts

    static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Kachel/state.json")

    func saveSnapshot() {
        do {
            try store.save(JSONEncoder().encode(SavedState(boot: system.bootTime, state: ss.snapshot, memory: lastMemory)))
        } catch {
            Log.info("could not save state: \(error)")
        }
    }

    func loadSaved() -> SavedState? {
        guard let data = store.load() else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    struct SavedState: Codable {
        var boot: Double
        var state: StackSet.Snapshot
        /// Older saved states lack it.
        var memory: [RememberedWindow]?
    }

    /// Where every managed window is, by app and (hashed) title.
    func rememberWindows() {
        var out: [RememberedWindow] = []
        for (i, ws) in ss.workspaces.enumerated() {
            for (order, id) in ws.windows.enumerated() {
                guard let w = windows[id], let app = w.bundleID, !scratchWindow.values.contains(id) else { continue }
                out.append(RememberedWindow(bundleID: app, title: w.title, workspace: i,
                                            floating: ss.floating.contains(id), order: order))
            }
        }
        lastMemory = out
    }

    /// After a restart: which of these windows had a place before.
    func takeRemembered(_ found: [WindowID: AppWindow]) -> [WindowID: RememberedWindow] {
        guard !remembered.isEmpty, !found.isEmpty else { return [:] }
        guard clock.now < rememberUntil else {
            Log.info("after a restart: \(remembered.count) remembered windows didn't come back")
            remembered = []
            return [:]
        }
        let candidates = found.compactMap { id, w in
            w.bundleID.map { WindowMemory.Candidate(id: id, bundleID: $0, title: w.title) }
        }
        return WindowMemory.match(candidates, in: &remembered)
    }

    /// A window back on the workspace it was on before the restart, in its old place.
    func putBack(_ id: WindowID, _ m: RememberedWindow) {
        let ws = min(m.workspace, ss.workspaces.count - 1)
        if m.floating { ss.floating.insert(id) }
        ss.insert(id, into: ws)
        restoredOrder[id] = m.order
        ss.order(workspace: ws) { self.restoredOrder[$0] }
        Log.info("window \(id) (\(windows[id].map(appName) ?? m.bundleID)) back on workspace \(ss.workspaces[ws].tag) after the restart")
    }

    /// Last resort when Kachel is crashing: put parked windows back on screen
    /// (AeroSpace does the same). Not async-signal-safe, but it's the end anyway.
    func emergencyRestore() {
        restoreAllWindows()
        AppResponsiveness.shared.flush(timeout: 1.0)
    }

    /// Never leave windows stranded in a corner when we exit.
    func restoreAllWindows() {
        for (_, m) in minimizedByUs { m.window.setMinimized(false) }
        minimizedByUs.removeAll()
        guard let scr = screens.first else { return }
        var offset: CGFloat = 0
        for id in hidden {
            guard let w = windows[id] else { continue }
            w.move(to: CGPoint(x: scr.visible.minX + 40 + offset, y: scr.visible.minY + 40 + offset))
            offset = (offset + 24).truncatingRemainder(dividingBy: 240)
        }
        hidden.removeAll()
    }
}
