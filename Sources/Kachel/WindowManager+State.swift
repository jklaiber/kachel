import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - state across restarts

    static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Kachel/state.json")

    func saveSnapshot() {
        guard !headless else { return }
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
    func loadSnapshot() -> StackSet.Snapshot? {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else { return nil }
        // Window IDs start over after a reboot; old ones would match random windows.
        guard abs(saved.boot - Self.bootTime) < 1 else {
            Log.info("saved state is from before the last reboot, ignoring it")
            return nil
        }
        return saved.state
    }

    struct SavedState: Codable {
        var boot: Double
        var state: StackSet.Snapshot
    }

    static let bootTime: Double = {
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
