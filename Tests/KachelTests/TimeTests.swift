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

/// Issue #8: a window restored from minimized must end up in front.
final class RestoreFocusTests: WindowManagerTestCase {
    private let teams = "rules:\n  - app: com.microsoft.teams2\n    hide: minimize\n"

    /// Teams on 1 with Alacritty; Teams focused, sent away and brought back.
    private func setUpMeeting() throws -> (meeting: FakeWindow, terminal: FakeWindow) {
        try start(config: teams)
        let terminal = sys.open("org.alacritty", title: "zsh", pid: 6000)
        let meeting = sys.open("com.microsoft.teams2", title: "Weekly sync", pid: 6001)
        refresh()
        wm.ss.focus(meeting.id)
        try run("workspace 2")
        XCTAssertTrue(meeting.minimized)
        try run("workspace 1")                    // un-minimized
        refresh()                                 // it's back: focus it
        return (meeting, terminal)
    }

    /// macOS activates the app that was in front before: Kachel focuses the
    /// meeting again a moment later.
    func testFocusStolenAfterRestoreIsTakenBack() throws {
        let (meeting, terminal) = try setUpMeeting()
        XCTAssertEqual(sys.focused, meeting.id)
        sys.focused = terminal.id                 // macOS, not you
        wm.syncFocusFromSystem(followHidden: true)
        clock.advance(by: 0.6)
        XCTAssertEqual(sys.focused, meeting.id, "in front again")
        XCTAssertEqual(wm.ss.current.focused, meeting.id)
    }

    /// You clicked the terminal yourself right after: that stays.
    func testYourClickWins() throws {
        let (_, terminal) = try setUpMeeting()
        clock.advance(by: 0.2)
        wm.lastUserInput = clock.now              // your click
        sys.focused = terminal.id
        wm.syncFocusFromSystem(followHidden: true)
        clock.advance(by: 2)
        XCTAssertEqual(sys.focused, terminal.id)
    }

    /// You moved on with a Kachel shortcut right after (the key monitor
    /// doesn't see those keys): that stays too (#17).
    func testYourShortcutWins() throws {
        let (meeting, terminal) = try setUpMeeting()
        clock.advance(by: 0.2)
        try run("focus-down")
        XCTAssertEqual(sys.focused, terminal.id)
        clock.advance(by: 2)
        XCTAssertEqual(sys.focused, terminal.id, "not taken back to \(meeting.id)")
        XCTAssertEqual(wm.ss.current.focused, terminal.id)
    }

    /// The app didn't answer the first time (Teams after sleep): the second
    /// look, later, still gets it in front.
    func testSecondLookLater() throws {
        let (meeting, terminal) = try setUpMeeting()
        sys.focused = terminal.id
        clock.advance(by: 0.6)                    // first look: focused again
        sys.focused = terminal.id                 // and lost again
        clock.advance(by: 1.0)                    // second look
        XCTAssertEqual(sys.focused, meeting.id)
    }
}

/// Issue #15: switching to an empty workspace must not bounce back because
/// macOS kept the previous workspace's app in front.
final class EmptyWorkspaceTests: WindowManagerTestCase {
    private var current: String { wm.ss.current.tag }

    /// Slack on 9, focused; you switch to the empty 8.
    private func switchToEmpty() throws -> FakeWindow {
        try start()
        try run("workspace 9")
        let slack = sys.open("com.tinyspeck.slackmacgap", title: "Slack", pid: 7000)
        refresh()
        XCTAssertEqual(sys.focused, slack.id)
        try run("workspace 8")                    // empty: Slack stays in front
        return slack
    }

    /// macOS reports Slack's window as focused a moment later.
    private func macOSReportsFocus() {
        clock.advance(by: 0.5)
        wm.syncFocusFromSystem(followHidden: true)
        clock.advance(by: 0.3)
    }

    func testStaysOnTheEmptyWorkspace() throws {
        _ = try switchToEmpty()
        macOSReportsFocus()
        XCTAssertEqual(current, "8", "no bounce back to 9")
    }

    /// You clicked Slack (or used ⌘Tab) after switching: that's a real wish.
    func testYourClickStillFollows() throws {
        _ = try switchToEmpty()
        clock.advance(by: 0.2)
        wm.lastUserInput = clock.now
        macOSReportsFocus()
        XCTAssertEqual(current, "9")
    }

    /// Only the workspace you just left is protected: a window on another
    /// hidden workspace that gets focus is still followed (link, Dock).
    func testOtherHiddenWorkspacesStillFollow() throws {
        try start()
        let chrome = sys.open("com.google.Chrome", title: "Inbox", pid: 7001)
        refresh()
        try run("shift 4")
        try run("workspace 9")
        try run("workspace 8")
        sys.focused = chrome.id                   // a link opens in Chrome
        macOSReportsFocus()
        XCTAssertEqual(current, "4")
    }
}

/// Issue #16: from an empty workspace, the key for a workspace shown on the
/// other display swaps it here, although macOS still reports that display's
/// window as focused.
final class EmptyDisplayTests: WindowManagerTestCase {
    /// Chrome on 1 (laptop), focused; you go to the DELL, which shows the empty 2.
    private func goToEmptyDisplay() throws -> FakeWindow {
        try start(displays: [Self.laptop, Self.dell])
        let chrome = sys.open("com.google.Chrome", title: "Inbox", pid: 8000)
        refresh()
        XCTAssertEqual(sys.focused, chrome.id)
        try run("focus-next-screen")              // empty: Chrome stays in front
        XCTAssertEqual(wm.ss.currentScreen, 1)
        return chrome
    }

    func testWorkspaceKeySwapsInsteadOfJustFocusingTheOtherDisplay() throws {
        let chrome = try goToEmptyDisplay()
        clock.advance(by: 1)
        try run("workspace 1")
        XCTAssertEqual(wm.ss.currentScreen, 1, "still on the DELL")
        XCTAssertEqual(wm.ss.current.tag, "1")
        XCTAssertEqual(display(of: chrome), "DELL U2720Q")
        XCTAssertEqual(wm.ss.workspaces[wm.ss.screenWorkspace[0]].tag, "2", "2 went to the laptop")
    }

    /// The poll doesn't pull you back either.
    func testStaysOnTheEmptyDisplay() throws {
        _ = try goToEmptyDisplay()
        clock.advance(by: 1)
        wm.syncFocusFromSystem(followHidden: true)
        XCTAssertEqual(wm.ss.currentScreen, 1)
    }

    /// You clicked Chrome on the laptop: Kachel follows you there.
    func testYourClickOnTheOtherDisplayFollows() throws {
        let chrome = try goToEmptyDisplay()
        clock.advance(by: 0.5)
        wm.lastUserInput = clock.now
        wm.syncFocusFromSystem(followHidden: true)
        XCTAssertEqual(wm.ss.currentScreen, 0)
        XCTAssertEqual(wm.ss.current.focused, chrome.id)
    }

    /// Another window getting focus (a link opening a new window) is followed.
    func testANewlyFocusedWindowIsFollowed() throws {
        _ = try goToEmptyDisplay()
        let other = sys.open("com.google.Chrome", title: "Link", pid: 8000)
        clock.advance(by: 1)
        refresh()
        sys.focused = other.id
        wm.syncFocusFromSystem(followHidden: true)
        XCTAssertNotEqual(wm.ss.current.windows, [], "not left on the empty workspace")
    }
}
