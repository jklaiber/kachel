import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// A window that only exists in the test. Moving, resizing and minimizing
/// just change its fields, so a test can look at what Kachel did to it.
final class FakeWindow: AppWindow {
    let id: WindowID
    let pid: pid_t
    let bundleID: String?
    var title: String
    var frame: CGRect?
    var hasFullscreenButton = true
    var isResizable = true
    var minimized = false
    /// In macOS's own fullscreen (the green button): on a Space of its own,
    /// and like minimized windows not one Kachel manages meanwhile.
    var fullscreen = false
    /// How often Kachel minimized it: a minimize undone in the same pass
    /// still flashes on screen, so the end state alone isn't enough.
    var timesMinimized = 0
    /// How often Kachel moved it out of sight (parked it).
    var timesParked = 0
    /// Smallest size the "app" accepts (like a real app refusing to shrink).
    var minSize: CGSize = .zero
    weak var system: FakeWindowSystem?

    init(id: WindowID, pid: pid_t, bundleID: String?, title: String, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
    }

    func setFrame(_ r: CGRect) {
        let r = r.integral
        frame = CGRect(origin: r.origin, size: CGSize(width: max(r.width, minSize.width), height: max(r.height, minSize.height)))
    }
    func move(to p: CGPoint) {
        frame?.origin = p
        if let s = system, !s.displays.contains(where: { $0.frame.insetBy(dx: 2, dy: 2).contains(frame!) }) { timesParked += 1 }
    }
    func setMinimized(_ on: Bool) {
        if on { timesMinimized += 1 }
        minimized = on
    }
    func raise() {}
    func focus() { system?.focused = id }
    func close() { system?.close(id) }
}

/// What macOS would report, under the test's control.
final class FakeWindowSystem: WindowSystem {
    /// Every window that exists, minimized or not.
    private(set) var all: [WindowID: FakeWindow] = [:]
    /// Windows Accessibility doesn't list right now although they exist
    /// (an app busy, the screen locked, a closed window an app keeps).
    var axHidden: Set<WindowID> = []
    var focused: WindowID?
    /// The connected displays; change it and call `screensChanged()` to plug
    /// one in or out.
    var displays: [Screen] = []
    private var nextID: WindowID = 100

    @discardableResult
    func open(_ bundleID: String, title: String = "", pid: pid_t = 1000,
              frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400)) -> FakeWindow {
        nextID += 1
        let w = FakeWindow(id: nextID, pid: pid, bundleID: bundleID, title: title, frame: frame)
        w.system = self
        all[w.id] = w
        return w
    }

    /// A window that already exists (from an earlier fake), same ID.
    func adopt(_ w: FakeWindow) {
        w.system = self
        all[w.id] = w
    }

    /// Gone for good: not even the window server knows it any more.
    func close(_ id: WindowID) {
        all[id] = nil
        if focused == id { focused = nil }
    }

    /// The same window (ID) behind a new Accessibility handle.
    func replaceHandle(_ id: WindowID) -> FakeWindow {
        let old = all[id]!
        let w = FakeWindow(id: id, pid: old.pid, bundleID: old.bundleID, title: old.title, frame: old.frame!)
        w.system = self
        all[id] = w
        return w
    }

    // MARK: WindowSystem

    func windows(known: [WindowID: AppWindow]) -> [WindowID: AppWindow] {
        // Like Accessibility: minimized windows aren't manageable.
        all.filter { !$0.value.minimized && !$0.value.fullscreen && !axHidden.contains($0.key) }.mapValues { $0 as AppWindow }
    }
    func windowServerIDs() -> Set<WindowID> { Set(all.keys) }
    func focusedWindow() -> WindowID? { focused }
    func appQuit(_ pid: pid_t) {}
    /// Change it to simulate a restart of the Mac.
    var bootTime: Double = 1_000
    /// Commands Kachel ran (nothing is really started), and what they report.
    var ran: [String] = []
    var runResult: (Int32, String) = (0, "")
    func run(_ command: String, done: @escaping (Int32, String) -> Void) {
        ran.append(command)
        done(runResult.0, runResult.1)
    }
    func screens(reserveBottom: CGFloat) -> [Screen] {
        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}

extension Screen {
    /// A made-up display; `menuBar` points at the top are taken (only the main one has it).
    static func fake(_ frame: CGRect, name: String, builtin: Bool = false, main: Bool = false) -> Screen {
        let menuBar: CGFloat = main ? 30 : 0
        let visible = CGRect(x: frame.minX, y: frame.minY + menuBar, width: frame.width, height: frame.height - menuBar)
        return Screen(frame: frame, visible: visible, nsVisible: visible, name: name, builtin: builtin, main: main)
    }
}

/// Saved state kept in memory, so a test can "restart" Kachel or the Mac.
final class MemoryStateStore: StateStore {
    var data: Data?
    func load() -> Data? { data }
    func save(_ d: Data) throws { data = d }
}

/// Time that only moves when the test says so. Work Kachel schedules
/// ("check again in 0.3 s") runs when the clock passes its time, in order.
final class FakeClock: Clock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var pending: [(at: Date, seq: Int, work: () -> Void)] = []
    private var seq = 0

    func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        seq += 1
        pending.append((now.addingTimeInterval(seconds), seq, work))
    }

    /// Move time forward, running everything that falls due on the way
    /// (also work that this work schedules).
    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = pending.filter({ $0.at <= end }).min(by: { ($0.at, $0.seq) < ($1.at, $1.seq) }) {
            pending.removeAll { $0.seq == next.seq }
            now = next.at
            next.work()
        }
        now = end
    }
}

/// A WindowManager on fake screens, with nothing written to disk.
class WindowManagerTestCase: XCTestCase {
    var sys: FakeWindowSystem!
    var wm: WindowManager!
    var clock: FakeClock!
    /// Timers Kachel sets outside the clock (focus border) may fire after a
    /// test ended; the managers must still be there then.
    private static var keepAlive: [WindowManager] = []

    static let screen1 = CGRect(x: 0, y: 0, width: 1200, height: 800)
    static let screen2 = CGRect(x: 1200, y: 0, width: 1000, height: 800)
    /// A laptop and an external display to its right.
    static let laptop = Screen.fake(CGRect(x: 0, y: 0, width: 1512, height: 982), name: "Built-in Retina Display",
                                    builtin: true, main: true)
    static let dell = Screen.fake(CGRect(x: 1512, y: 0, width: 2560, height: 1440), name: "DELL U2720Q")

    /// - config: YAML on top of the defaults (e.g. rules).
    func start(screens: [CGRect] = [screen1], config: String = "") throws {
        try start(displays: screens.enumerated().map { i, f in Screen.fake(f, name: "Display \(i + 1)") }, config: config)
    }

    func start(displays: [Screen], config: String = "", store: MemoryStateStore = MemoryStateStore(),
               bootTime: Double = 1_000) throws {
        Log.enabled = false
        // No gaps, padding or bar: frames are easy to check.
        Config.use(try Settings.parse("gap: 0\nmouse-follows-focus: off\nborder:\n  enabled: false\n" + config))
        sys = FakeWindowSystem()
        sys.displays = displays
        sys.bootTime = bootTime
        clock = FakeClock()
        wm = WindowManager(system: sys, clock: clock, store: store, headless: true)
        Self.keepAlive.append(wm)
        wm.managing = true
        wm.screensChanged()            // reads the displays like at launch
    }

    /// Plug displays in or out, as macOS reports it.
    func connect(_ displays: [Screen]) {
        sys.displays = displays
        wm.screensChanged()
    }

    func display(of w: FakeWindow) -> String? {
        guard let f = w.frame else { return nil }
        return sys.displays.first { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) }?.name
    }

    /// What happens after macOS reports a change.
    func refresh() { wm.refresh() }

    func workspace(of w: FakeWindow) -> String? {
        wm.ss.workspaceIndex(of: w.id).map { wm.ss.workspaces[$0].tag }
    }

    func isParked(_ w: FakeWindow) -> Bool { wm.hidden.contains(w.id) }

    func run(_ cmd: String) throws {
        wm.perform(try Settings.parseCommand(cmd, workspaceCount: 9, context: "test"))
    }
}
