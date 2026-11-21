import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// Basics: windows appear, get tiled, and move between workspaces.
final class TilingTests: WindowManagerTestCase {
    func testNewWindowsAreTiledSideBySide() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        XCTAssertEqual(workspace(of: a), "1")
        XCTAssertEqual(workspace(of: b), "1")
        // Tall, ratio 0.5: two halves of the screen, nothing overlapping.
        let fa = try XCTUnwrap(a.frame), fb = try XCTUnwrap(b.frame)
        XCTAssertEqual(fa.width + fb.width, 1200, accuracy: 1)
        XCTAssertFalse(fa.intersects(fb))
        XCTAssertEqual(fa.height, 800, accuracy: 1)
    }

    func testSwitchingWorkspaceParksAndBringsBack() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        refresh()
        let tiled = a.frame
        try run("workspace 2")
        XCTAssertTrue(isParked(a))
        XCTAssertFalse(Self.screen1.insetBy(dx: 2, dy: 2).contains(a.frame!), "out of sight")
        try run("workspace 1")
        XCTAssertFalse(isParked(a))
        XCTAssertEqual(a.frame, tiled)
    }

    func testShiftSendsWindowAway() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        wm.ss.focus(b.id)
        try run("shift 3")
        XCTAssertEqual(workspace(of: b), "3")
        XCTAssertTrue(isParked(b))
        XCTAssertEqual(a.frame?.width ?? 0, 1200, accuracy: 1, "alone now: whole screen")
    }

    func testRuleSendsNewWindowToItsWorkspace() throws {
        try start(config: "rules:\n  - app: com.tinyspeck.slackmacgap\n    workspace: \"4\"\n")
        let slack = sys.open("com.tinyspeck.slackmacgap")
        refresh()
        XCTAssertEqual(workspace(of: slack), "4")
        XCTAssertEqual(wm.ss.current.tag, "1", "you stay where you are")
    }
}

/// Windows that vanish and come back: the bugs that were fixed by hand before.
final class WindowLifecycleTests: WindowManagerTestCase {
    func testClosedWindowIsForgotten() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        sys.close(b.id)
        refresh()
        XCTAssertNil(workspace(of: b))
        XCTAssertEqual(a.frame?.width ?? 0, 1200, accuracy: 1)
    }

    /// Accessibility briefly doesn't list a window that still exists (busy app,
    /// sleep): it must keep its workspace, not come back on the current one.
    func testWindowMissingFromAccessibilityKeepsItsWorkspace() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        refresh()
        wm.ss.focus(a.id)
        try run("shift 5")
        sys.axHidden.insert(a.id)
        refresh()
        XCTAssertEqual(workspace(of: a), "5", "kept while the window server still has it")
        sys.axHidden.remove(a.id)
        refresh()
        XCTAssertEqual(workspace(of: a), "5")
    }

    /// Native tabs (Finder, Terminal): switching tabs hides one window and
    /// shows another in the same spot. The new one takes the old one's place.
    func testTabSwitchKeepsThePlaceInTheLayout() throws {
        try start()
        let a = sys.open("com.apple.Terminal", pid: 2000)
        let b = sys.open("com.apple.Safari", pid: 2001)
        refresh()
        let slot = try XCTUnwrap(a.frame)
        let order = wm.ss.current.windows
        // Tab switch: a disappears, a new window of the same app appears where it was.
        sys.close(a.id)
        let tab = sys.open("com.apple.Terminal", pid: 2000, frame: slot)
        refresh()
        XCTAssertEqual(wm.ss.current.windows, order.map { $0 == a.id ? tab.id : $0 }, "same position in the stack")
        XCTAssertEqual(tab.frame, slot)
        XCTAssertNotNil(b.frame)
    }

    /// An app (Slack, Telegram) hides a window and brings it back with a new
    /// handle: same window, same workspace, no duplicate.
    func testNewHandleForSameWindow() throws {
        try start()
        let a = sys.open("com.tinyspeck.slackmacgap")
        refresh()
        wm.ss.focus(a.id)
        try run("shift 2")
        let again = sys.replaceHandle(a.id)
        refresh()
        XCTAssertEqual(workspace(of: again), "2")
        XCTAssertEqual(wm.ss.allWindows.filter { $0 == a.id }.count, 1)
        XCTAssertTrue(wm.windows[a.id] === again, "uses the new handle")
    }

    /// While the screen is locked, Accessibility hides every window. That must
    /// not look like all windows closed.
    func testLockedScreenChangesNothing() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        let before = wm.ss.current.windows
        wm.locked = true
        sys.axHidden = [a.id, b.id]
        refresh()
        XCTAssertEqual(wm.ss.current.windows, before)
        wm.locked = false
        sys.axHidden = []
        refresh()
        XCTAssertEqual(wm.ss.current.windows, before)
    }

    /// iTerm with tmux -CC resizes its own window after Kachel tiled it.
    /// Kachel puts it back, but at most 4 times a minute, so it never fights.
    func testAppMovingItsWindowIsCorrectedButNotForever() throws {
        try start()
        let a = sys.open("com.googlecode.iterm2")
        refresh()
        XCTAssertNotNil(wm.expected[a.id])
        for _ in 0..<10 { wm.correctAppMove(a.id) }
        XCTAssertEqual(wm.appMoves[a.id]?.count, 4)
    }
}

/// Teams meetings: `hide: minimize` rules.
final class MinimizeRuleTests: WindowManagerTestCase {
    private let teams = """
    rules:
      - app: com.microsoft.teams2
        title-not: ["Microsoft Teams"]
        hide: minimize

    """

    func testMeetingIsMinimizedWhenItsWorkspaceLeavesTheScreen() throws {
        try start(config: teams)
        let main = sys.open("com.microsoft.teams2", title: "Chat | Microsoft Teams", pid: 3000)
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        try run("workspace 2")
        XCTAssertTrue(meeting.minimized, "Teams shows its small window")
        XCTAssertFalse(main.minimized, "title-not: the main window is only parked")
        XCTAssertTrue(isParked(main))
        try run("workspace 1")
        XCTAssertFalse(meeting.minimized)
    }

    /// Two displays, meeting on one: focusing the other display doesn't hide
    /// it, nor does switching the other display's workspace.
    func testMeetingStaysWhileVisibleOnAnotherDisplay() throws {
        try start(screens: [Self.screen1, Self.screen2], config: teams)
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        XCTAssertEqual(workspace(of: meeting), "1")
        try run("focus-next-screen")
        try run("workspace 3")            // on the second display
        try run("workspace 4")
        XCTAssertEqual(meeting.timesMinimized, 0, "not even briefly")
        XCTAssertEqual(meeting.timesParked, 0)
        XCTAssertFalse(meeting.minimized)
    }

    /// Swapping displays (greedyView of a workspace shown on the other one)
    /// keeps it visible: no minimize, it just moves.
    func testSwappingDisplaysDoesNotMinimize() throws {
        try start(screens: [Self.screen1, Self.screen2], config: teams)
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        try run("focus-next-screen")
        try run("workspace 1")            // workspace 1 comes over to display 2
        XCTAssertEqual(meeting.timesMinimized, 0)
        XCTAssertFalse(meeting.minimized)
        XCTAssertTrue(Self.screen2.contains(CGPoint(x: meeting.frame!.midX, y: meeting.frame!.midY)))
    }

    /// A window you minimized yourself isn't Kachel's to restore.
    func testOwnMinimizeIsLeftAlone() throws {
        try start(config: teams)
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 3000)
        refresh()
        meeting.minimized = true          // you, with the yellow button
        refresh()
        try run("workspace 2")
        try run("workspace 1")
        XCTAssertTrue(meeting.minimized)
    }
}

/// What the watchdog gets to restore after a crash.
final class ParkedStateTests: WindowManagerTestCase {
    func testHiddenMatchesWindowsOutOfSight() throws {
        try start()
        let a = sys.open("com.apple.Safari")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        wm.ss.focus(b.id)
        try run("shift 2")
        XCTAssertEqual(wm.hidden, [b.id])
        try run("workspace 2")
        XCTAssertEqual(wm.hidden, [a.id])
    }
}
