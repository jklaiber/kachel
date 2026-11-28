import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// What the watchdog and the next start rely on.
final class RecoveryTests: WindowManagerTestCase {
    /// The watchdog hears about a window before it's moved out of sight, so a
    /// crash in between can't leave it in a corner unknown to the watchdog.
    func testWatchdogHearsBeforeAWindowIsParked() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        var stillOnScreenWhenRecorded: [WindowID: Bool] = [:]
        wm.recordParked = { [unowned self] state in
            for e in state.parked where stillOnScreenWhenRecorded[e.window] == nil {
                let f = self.sys.all[e.window]?.frame ?? .zero
                stillOnScreenWhenRecorded[e.window] = Self.screen1.contains(CGPoint(x: f.midX, y: f.midY))
            }
        }
        try run("workspace 2")
        XCTAssertTrue(isParked(a) && isParked(b))
        XCTAssertEqual(stillOnScreenWhenRecorded[a.id], true, "recorded while still on screen")
        XCTAssertEqual(stillOnScreenWhenRecorded[b.id], true)
        XCTAssertFalse(Self.screen1.contains(CGPoint(x: a.frame!.midX, y: a.frame!.midY)), "and then parked")
    }

    /// A damaged state file: Kachel starts afresh, says so, and keeps every window.
    func testDamagedSavedStateStartsAfresh() throws {
        let store = MemoryStateStore()
        store.data = Data("{\"boot\": 1000, \"state\": {\"order\": [1,2".utf8)
        var lines: [String] = []
        Log.sink = { lines.append($0) }
        defer { Log.sink = nil }
        try start(displays: [Self.laptop], store: store)
        let a = sys.open("com.apple.Safari")
        wm.adoptExistingWindows()
        XCTAssertNotNil(workspace(of: a), "the window is managed")
        XCTAssertTrue(lines.contains { $0.contains("couldn't read the saved workspaces") })
    }
}
