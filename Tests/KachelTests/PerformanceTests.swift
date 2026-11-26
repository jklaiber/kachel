import XCTest
@testable import Kachel
@testable import KachelCore

/// Kachel runs all day: while nothing changes, it must do (almost) nothing.
/// These count the expensive things instead of timing them, so they're exact
/// and don't depend on how fast the Mac is.
final class PerformanceTests: WindowManagerTestCase {
    /// Three windows on 1, two on 2; tiled and settled.
    private func settled() throws -> [FakeWindow] {
        try start()
        var ws = (0..<3).map { sys.open("com.example.app\($0)", pid: pid_t(4000 + $0)) }
        refresh()
        try run("workspace 2")
        ws += (3..<5).map { sys.open("com.example.app\($0)", pid: pid_t(4000 + $0)) }
        refresh()
        clock.advance(by: 5)                      // checks after tiling are done
        wm.pollRefresh()
        return ws
    }

    private var writes: Int { sys.all.values.map(\.writes).reduce(0, +) }

    /// The 2-second poll doesn't ask every app while nothing on screen changed,
    /// and still does every 10 seconds.
    func testIdlePollDoesNotAskTheApps() throws {
        _ = try settled()
        let before = sys.windowListings
        for _ in 0..<4 { clock.advance(by: 2); wm.pollRefresh() }       // 8 s
        XCTAssertEqual(sys.windowListings, before, "nothing changed: no app asked")
        clock.advance(by: 2); wm.pollRefresh()                           // 10 s
        XCTAssertEqual(sys.windowListings, before + 1, "the full look every 10 s")
    }

    /// Idle: no window is moved, resized or minimized, over a minute of polls.
    func testIdleKachelLeavesWindowsAlone() throws {
        _ = try settled()
        let before = writes
        for _ in 0..<30 { clock.advance(by: 2); wm.pollRefresh(); wm.updateBar() }
        XCTAssertEqual(writes, before)
    }

    /// A new window is still picked up by the next poll.
    func testNewWindowIsFoundByTheNextPoll() throws {
        _ = try settled()
        let w = sys.open("com.example.new", pid: 4100)
        clock.advance(by: 2); wm.pollRefresh()
        XCTAssertNotNil(wm.ss.workspaceIndex(of: w.id))
    }

    /// You minimized a window yourself: the next poll tiles without it.
    func testMinimizedWindowIsNoticedByTheNextPoll() throws {
        let ws = try settled()
        ws[3].minimized = true
        clock.advance(by: 2); wm.pollRefresh()
        XCTAssertEqual(ws[4].frame, Self.screen1, "the other one has the screen to itself")
    }

    /// Switching workspaces touches only the windows that change: hide the
    /// ones going away, show the ones coming in, once each.
    func testSwitchingTouchesEachWindowOnce() throws {
        let ws = try settled()
        let before = ws.map(\.writes)
        try run("workspace 1")
        clock.advance(by: 2)
        let after = ws.map(\.writes)
        for (i, w) in ws.enumerated() {
            XCTAssertLessThanOrEqual(after[i] - before[i], 2, "window \(w.id): \(after[i] - before[i]) writes")
        }
    }

    /// Many windows: moving focus around a full workspace moves no window,
    /// they're already where they belong. (Re-tile, mod-z, puts every window
    /// in place again on purpose.)
    func testFocusChangesWriteNothing() throws {
        try start()
        for i in 0..<40 { _ = sys.open("com.example.app\(i % 8)", pid: pid_t(5000 + i % 8)) }
        refresh()
        clock.advance(by: 5)
        let before = writes
        for _ in 0..<10 { try run("focus-down") }
        clock.advance(by: 5)
        XCTAssertEqual(writes, before)
    }

    /// Skipping windows that are in place mustn't leave one out of place: a
    /// window something else moved is put back by the check after tiling.
    func testMovedWindowIsStillPutBack() throws {
        let ws = try settled()
        try run("workspace 1")
        clock.advance(by: 2)
        let place = try XCTUnwrap(ws[0].frame)
        ws[0].frame = CGRect(x: 300, y: 300, width: 500, height: 400)    // not Kachel
        try run("focus-down")
        clock.advance(by: 1)
        XCTAssertEqual(ws[0].frame, place)
    }

    /// Re-tile (mod-z) sends every window its place again, on purpose.
    func testRetileSendsEveryPlaceAgain() throws {
        let ws = try settled()
        try run("workspace 1")
        clock.advance(by: 2)
        let before = ws[0...2].map(\.writes)
        wm.refreshNow()
        XCTAssertEqual(zip(ws[0...2], before).filter { $0.0.writes > $0.1 }.count, 3)
    }
}
