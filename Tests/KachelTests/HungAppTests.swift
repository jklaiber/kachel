import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// An app that didn't answer may have missed what Kachel asked of it.
final class HungAppTests: WindowManagerTestCase {
    /// Kachel parked the window while the app was frozen, but the app never
    /// got the move: when it answers again, it's parked once more.
    func testLostParkIsRedoneWhenTheAppAnswersAgain() throws {
        try start()
        let a = sys.open("test.kachel.hanger", pid: 4000)
        refresh()
        let tiled = try XCTUnwrap(a.frame)
        try run("workspace 2")
        XCTAssertTrue(isParked(a))
        a.frame = tiled                                  // the move was lost
        wm.appAnswersAgain(4000)
        XCTAssertTrue(isParked(a))
        XCTAssertFalse(Self.screen1.insetBy(dx: 2, dy: 2).contains(a.frame!), "out of sight again")
    }

    /// A floating window that did get parked keeps its remembered place: the
    /// corner must not become where it shows up next time.
    func testParkedFloatingWindowKeepsItsPlace() throws {
        try start()
        let f = sys.open("com.apple.finder", pid: 4001, frame: CGRect(x: 300, y: 200, width: 400, height: 300))
        f.hasFullscreenButton = false
        refresh()
        try run("workspace 2")
        let remembered = wm.floatRel[f.id]
        wm.appAnswersAgain(4001)
        XCTAssertEqual(wm.floatRel[f.id], remembered)
        try run("workspace 1")
        XCTAssertEqual(f.frame, CGRect(x: 300, y: 200, width: 400, height: 300))
    }
}
