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
        if let s = system, !s.screens.contains(where: { $0.insetBy(dx: 2, dy: 2).contains(frame!) }) { timesParked += 1 }
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
    var screens: [CGRect] = []
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
        all.filter { !$0.value.minimized && !axHidden.contains($0.key) }.mapValues { $0 as AppWindow }
    }
    func windowServerIDs() -> Set<WindowID> { Set(all.keys) }
    func focusedWindow() -> WindowID? { focused }
    func appQuit(_ pid: pid_t) {}
}

/// A WindowManager on fake screens, with nothing written to disk.
class WindowManagerTestCase: XCTestCase {
    var sys: FakeWindowSystem!
    var wm: WindowManager!
    /// Timers Kachel sets (verify, save) may fire after a test ended; the
    /// managers must still be there then.
    private static var keepAlive: [WindowManager] = []

    static let screen1 = CGRect(x: 0, y: 0, width: 1200, height: 800)
    static let screen2 = CGRect(x: 1200, y: 0, width: 1000, height: 800)

    /// - config: YAML on top of the defaults (e.g. rules).
    func start(screens: [CGRect] = [screen1], config: String = "") throws {
        Log.enabled = false
        guard let ns = NSScreen.screens.first else { throw XCTSkip("needs a display") }
        // No gaps, padding or bar: frames are easy to check.
        Config.use(try Settings.parse("gap: 0\nmouse-follows-focus: off\nborder:\n  enabled: false\n" + config))
        sys = FakeWindowSystem()
        sys.screens = screens
        wm = WindowManager(system: sys, headless: true)
        Self.keepAlive.append(wm)
        wm.screens = screens.map { f in
            Screen(frame: f, visible: f, nsVisible: NSRect(x: f.minX, y: 0, width: f.width, height: f.height), ns: ns)
        }
        wm.ss = StackSet(tags: Config.current.workspaces, screenCount: screens.count, ratio: 0.5)
        wm.managing = true
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
