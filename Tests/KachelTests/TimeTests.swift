import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// Rules that depend on time, with a clock that only moves when told.
final class TimeTests: WindowManagerTestCase {
    // MARK: apps moving their own windows

    /// At most 4 corrections a minute, and after a minute it may correct again.
    func testAppMoveCorrectionsStartOverAfterAMinute() throws {
        try start()
        let a = sys.open("com.googlecode.iterm2")
        refresh()
        for _ in 0..<6 { wm.correctAppMove(a.id) }
        XCTAssertEqual(wm.appMoves[a.id]?.count, 4)
        clock.advance(by: 30)
        wm.correctAppMove(a.id)
        XCTAssertEqual(wm.appMoves[a.id]?.count, 4, "still within the minute")
        clock.advance(by: 31)
        wm.correctAppMove(a.id)
        XCTAssertEqual(wm.appMoves[a.id]?.count, 1, "a new minute")
    }

    /// iTerm resizes its window after Kachel tiled it: the check 0.3 s later
    /// puts it back.
    func testWindowResizedByItsAppIsPutBack() throws {
        try start()
        let a = sys.open("com.googlecode.iterm2")
        refresh()
        let tiled = a.frame
        a.frame = CGRect(x: 40, y: 40, width: 700, height: 500)   // the app, on its own
        wm.correctAppMove(a.id)
        clock.advance(by: 0.2)
        XCTAssertNotEqual(a.frame, tiled, "not yet")
        clock.advance(by: 0.2)
        XCTAssertEqual(a.frame, tiled)
    }

    // MARK: minimum sizes

    /// Stack windows that won't get shorter: after two checks Kachel learns
    /// their minimum height and gives them room in the column, instead of
    /// letting them overlap.
    func testMinimumHeightIsLearnedAndMadeRoomFor() throws {
        try start()
        _ = sys.open("com.apple.Safari")
        let b = sys.open("com.microsoft.VSCode", pid: 1001)
        let c = sys.open("com.apple.Notes", pid: 1002)
        b.minSize = CGSize(width: 0, height: 600)
        refresh()
        XCTAssertEqual(b.frame?.height, 600, "asked for 400, took 600")
        clock.advance(by: 1)
        XCTAssertEqual(wm.minSize[b.id]?.height, 600)
        let fb = try XCTUnwrap(b.frame), fc = try XCTUnwrap(c.frame)
        XCTAssertFalse(fb.intersects(fc), "no overlap in the stack: \(fb) \(fc)")
        XCTAssertEqual(fb.height + fc.height, 800, accuracy: 1)
    }

    /// Too wide for its column: it grows towards the middle but stays on the
    /// screen (it overlaps the master; the columns don't move for it).
    func testTooWideWindowStaysOnScreen() throws {
        try start()
        _ = sys.open("com.apple.Safari")
        let b = sys.open("com.microsoft.VSCode", pid: 1001)
        b.minSize = CGSize(width: 800, height: 0)
        refresh()
        clock.advance(by: 1)
        XCTAssertEqual(wm.minSize[b.id]?.width, 800)
        XCTAssertTrue(Self.screen1.contains(try XCTUnwrap(b.frame)), "not hanging off the screen")
    }

    // MARK: dialogs

    /// No fullscreen button = dialog, floats. Some apps add the button a
    /// moment later: then it's tiled after all.
    func testLateFullscreenButtonGetsTheWindowTiled() throws {
        try start()
        let w = sys.open("com.electron.app")
        w.hasFullscreenButton = false
        refresh()
        XCTAssertTrue(wm.ss.floating.contains(w.id))
        w.hasFullscreenButton = true
        clock.advance(by: 0.6)
        XCTAssertFalse(wm.ss.floating.contains(w.id))
        XCTAssertEqual(w.frame, Self.screen1)
    }

    func testRealDialogKeepsFloating() throws {
        try start()
        let w = sys.open("com.apple.finder", frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        w.hasFullscreenButton = false
        refresh()
        clock.advance(by: 5)
        XCTAssertTrue(wm.ss.floating.contains(w.id))
        XCTAssertEqual(w.frame, CGRect(x: 300, y: 200, width: 400, height: 300), "left where it is")
    }

    // MARK: native tabs

    /// A window of the same app appearing in the same spot is a tab switch
    /// only right after the other one went (3.5 s): later it's a new window.
    func testTabSwitchOnlyRightAfterTheOtherWent() throws {
        try start()
        let a = sys.open("com.apple.Terminal", pid: 2000)
        let b = sys.open("com.apple.Safari", pid: 2001)
        refresh()
        let slot = try XCTUnwrap(a.frame)
        clock.advance(by: 5)                       // nothing looked in between
        sys.close(a.id)
        let late = sys.open("com.apple.Terminal", pid: 2000, frame: slot)
        refresh()
        XCTAssertEqual(wm.ss.current.windows.last, late.id, "a new window, added like any other")
        XCTAssertTrue(wm.ss.current.windows.contains(b.id))
    }

    // MARK: Teams: restoring a minimized meeting

    /// You click Teams' small window to get the meeting back while its
    /// workspace is hidden: Kachel goes to that workspace, like macOS goes
    /// to a window's Space.
    func testRestoringTheMeetingYourselfShowsItsWorkspace() throws {
        try start(config: "rules:\n  - app: com.microsoft.teams2\n    hide: minimize\n")
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        try run("workspace 2")
        XCTAssertTrue(meeting.minimized)
        clock.advance(by: 5)
        meeting.minimized = false                   // you
        refresh()
        XCTAssertEqual(wm.ss.current.tag, "1")
        XCTAssertEqual(wm.ss.current.focused, meeting.id)
    }

    /// Right after Kachel minimized it, the window can still look restored
    /// (the animation): that's not you, so Kachel stays where it is.
    func testMinimizeAnimationIsNotTakenForYou() throws {
        try start(config: "rules:\n  - app: com.microsoft.teams2\n    hide: minimize\n")
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        try run("workspace 2")
        meeting.minimized = false                   // still animating
        clock.advance(by: 0.3)
        refresh()
        XCTAssertEqual(wm.ss.current.tag, "2")
    }
}
