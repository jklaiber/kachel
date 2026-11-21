import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// macOS's own fullscreen (the green button): the window gets a Space of its
/// own. Kachel leaves it alone meanwhile, keeps its workspace, and tiles it
/// again in its old place when it leaves fullscreen.
final class FullscreenTests: WindowManagerTestCase {
    func testOthersTakeTheRoomWhileItsFullscreen() throws {
        try start()
        let video = sys.open("com.apple.Safari")
        let notes = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        video.fullscreen = true
        refresh()
        XCTAssertEqual(workspace(of: video), "1", "still belongs to its workspace")
        XCTAssertEqual(notes.frame, Self.screen1, "the other window takes the whole screen")
    }

    func testKachelDoesntTouchItWhileFullscreen() throws {
        try start()
        let video = sys.open("com.apple.Safari")
        refresh()
        video.fullscreen = true
        refresh()
        let parkedBefore = video.timesParked
        let frame = video.frame
        try run("workspace 2")
        try run("workspace 1")
        try run("workspace 3")
        XCTAssertEqual(video.timesParked, parkedBefore, "never parked: macOS shows it on its own Space")
        XCTAssertEqual(video.frame, frame)
    }

    func testBackInItsPlaceAfterFullscreen() throws {
        try start()
        let video = sys.open("com.apple.Safari")
        let notes = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        let slot = video.frame
        let order = wm.ss.current.windows
        video.fullscreen = true
        refresh()
        video.fullscreen = false
        refresh()
        XCTAssertEqual(wm.ss.current.windows, order, "same place in the stack")
        XCTAssertEqual(video.frame, slot)
        XCTAssertNotEqual(notes.frame, Self.screen1)
    }

    /// Left fullscreen while its workspace isn't on screen: it's parked like
    /// the rest of that workspace, not left in the middle of another one.
    func testLeavingFullscreenWhileItsWorkspaceIsHidden() throws {
        try start()
        let video = sys.open("com.apple.Safari")
        refresh()
        video.fullscreen = true
        refresh()
        try run("workspace 2")
        video.fullscreen = false
        video.frame = Self.screen1                       // macOS puts it back in view
        refresh()
        XCTAssertEqual(workspace(of: video), "1")
        XCTAssertTrue(isParked(video))
    }

    /// The focused window went fullscreen: focus on the workspace moves on to
    /// another window instead of staying on one Kachel can't reach.
    func testFocusMovesOnWhileFullscreen() throws {
        try start()
        let video = sys.open("com.apple.Safari")
        let notes = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        wm.ss.focus(video.id)
        video.fullscreen = true
        refresh()
        XCTAssertEqual(wm.ss.current.focused, notes.id)
    }
}
