import AppKit
import ApplicationServices
import KachelCore

/// A small second process that outlives Kachel. If Kachel ends without
/// quitting properly (a crash, a force quit, `kill -9`), it puts the windows
/// of hidden workspaces back on screen, unminimizes the ones Kachel minimized,
/// and starts Kachel again, which takes its workspaces from the saved state.
///
/// Kachel crashing can't clean up reliably by itself: a signal handler may
/// not get to run (force quit, `kill -9`), and when it does, it isn't safe to
/// talk to other apps from there. Kachel keeps `parked.json` up to date with
/// what it has moved out of sight, and the watchdog works from that file.
enum Watchdog {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Kachel")
    static let parkedURL = dir.appendingPathComponent("parked.json")
    static let crashURL = dir.appendingPathComponent("last-crash.json")

    struct Parked: Codable, Equatable {
        struct Entry: Codable, Equatable { var pid: Int32; var window: UInt32 }
        var parked: [Entry] = []
        var minimized: [Entry] = []
    }

    /// When Kachel last ended unexpectedly and the watchdog restarted it.
    struct Crash: Codable {
        var at: Date
        var restarts: [Date]
    }

    // MARK: - in Kachel

    private static var child: Process?
    private static var lastWritten: Parked?

    /// Start the watchdog for this Kachel.
    static func spawn() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["--watchdog", "\(getpid())", Bundle.main.bundlePath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            child = p
            Log.info("watchdog started (pid \(p.processIdentifier))")
        } catch {
            Log.info("could not start the watchdog: \(error)")
        }
    }

    /// Kachel quits properly: windows are back already, nothing to watch.
    static func stop() {
        guard let p = child, p.isRunning else { return }
        kill(p.processIdentifier, SIGTERM)
        child = nil
        try? FileManager.default.removeItem(at: parkedURL)
    }

    /// What's out of sight right now. Written only when it changes.
    static func record(_ state: Parked) {
        guard state != lastWritten else { return }
        lastWritten = state
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: parkedURL, options: .atomic)
        } catch {
            Log.info("could not write \(parkedURL.lastPathComponent): \(error)")
        }
    }

    // MARK: - the watchdog process

    /// `Kachel --watchdog <pid> <bundle path>`. Never returns.
    static func run(parent: pid_t, bundle: String) -> Never {
        let started = Date()
        signal(SIGTERM, SIG_DFL)          // stop() asks us to go
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        source.setEventHandler {
            parentEnded(started: started, bundle: bundle)
            exit(0)
        }
        source.resume()
        // It may have died before we were watching.
        if kill(parent, 0) != 0, errno == ESRCH {
            parentEnded(started: started, bundle: bundle)
            exit(0)
        }
        dispatchMain()
    }

    private static func parentEnded(started: Date, bundle: String) {
        Log.info("watchdog: Kachel ended without quitting, putting windows back")
        restoreWindows()

        // Start it again, unless it keeps crashing (3 restarts in 10 minutes)
        // or crashed right after starting.
        let old = (try? Data(contentsOf: crashURL)).flatMap { try? JSONDecoder().decode(Crash.self, from: $0) }
        let recent = (old?.restarts ?? []).filter { Date().timeIntervalSince($0) < 600 }
        let ran = Date().timeIntervalSince(started)
        let restart = recent.count < 3 && ran > 20 && bundle.hasSuffix(".app")
        let crash = Crash(at: Date(), restarts: recent + (restart ? [Date()] : []))
        try? JSONEncoder().encode(crash).write(to: crashURL, options: .atomic)
        guard restart else {
            Log.info("watchdog: not starting Kachel again: " + (recent.count >= 3 ? "it ended 3 times in 10 minutes"
                                                                 : ran <= 20 ? "it ended \(Int(ran)) s after starting" : "not an app bundle"))
            return
        }
        Log.info("watchdog: starting Kachel again")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", bundle]
        try? p.run()
        p.waitUntilExit()
    }

    /// Parked windows to the main screen, minimized ones back up.
    private static func restoreWindows() {
        guard let data = try? Data(contentsOf: parkedURL),
              let state = try? JSONDecoder().decode(Parked.self, from: data) else {
            Log.info("watchdog: nothing was parked")
            return
        }
        guard AXIsProcessTrusted() else {
            Log.info("watchdog: no Accessibility permission, can't move windows")
            return
        }
        let main = CGDisplayBounds(CGMainDisplayID())        // same top-left coordinates as AX
        var offset: CGFloat = 0
        var moved = 0, unminimized = 0
        let wanted = Set((state.parked + state.minimized).map(\.pid))
        for pid in wanted {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1.0)
            guard let windows = axCopy(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for el in windows {
                guard let id = axWindowID(el) else { continue }
                if state.parked.contains(.init(pid: pid, window: id)) {
                    var p = CGPoint(x: main.minX + 60 + offset, y: main.minY + 80 + offset)
                    if let v = AXValueCreate(.cgPoint, &p) {
                        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
                    }
                    offset = (offset + 28).truncatingRemainder(dividingBy: 280)
                    moved += 1
                }
                if state.minimized.contains(.init(pid: pid, window: id)) {
                    AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    unminimized += 1
                }
            }
        }
        try? FileManager.default.removeItem(at: parkedURL)
        Log.info("watchdog: moved \(moved) window(s) back on screen, unminimized \(unminimized)")
    }
}
