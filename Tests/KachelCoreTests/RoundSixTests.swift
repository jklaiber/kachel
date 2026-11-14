import XCTest
import CoreGraphics
@testable import KachelCore

final class WeightsAndThreeColumnTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    func testWeightsShareAColumn() {
        XCTAssertEqual(Layout.distribute(900, [nil, nil, nil], weights: [1, 2, 1]), [225, 450, 225])
        // Minimums still win over weights.
        XCTAssertEqual(Layout.distribute(900, [nil, nil, 400], weights: [1, 2, 1]), [500.0 / 3, 1000.0 / 3, 400])
    }

    func testTallStackWithWeights() {
        let r = Layout.tile(.tall, count: 3, in: screen, nMaster: 1, ratio: 0.5, gap: 0, weights: [1, 3, 1])
        XCTAssertEqual(r[0].height, 900)                // master: alone in its column
        XCTAssertEqual(r[1].height, 675)
        XCTAssertEqual(r[2].height, 225)
    }

    func testWeightsRoundTripFromMouse() {
        let r = Layout.tile(.tall, count: 3, in: screen, nMaster: 1, ratio: 0.5, gap: 6, weights: [1, 1, 1])
        // Drag the first stack window down until it is 600 high.
        var dragged = r[1]; dragged.size.height = 600
        let w = Layout.weights(afterResizing: dragged, index: 1, count: 3, kind: .tall, in: screen,
                               nMaster: 1, ratio: 0.5, gap: 6, weights: [1, 1, 1])!
        let again = Layout.tile(.tall, count: 3, in: screen, nMaster: 1, ratio: 0.5, gap: 6, weights: w)
        XCTAssertEqual(again[1].height, 600, accuracy: 2)
        XCTAssertNil(Layout.weights(afterResizing: r[0], index: 0, count: 3, kind: .tall, in: screen,
                                    nMaster: 1, ratio: 0.5, gap: 6, weights: []))           // master is alone
    }

    func testThreeColumn() {
        let r = Layout.tile(.threeColumn, count: 4, in: screen, nMaster: 1, ratio: 0.5, gap: 0)
        XCTAssertEqual(r[0], CGRect(x: 300, y: 0, width: 600, height: 900))        // master in the middle
        XCTAssertEqual(r[1], CGRect(x: 900, y: 0, width: 300, height: 450))        // right column, 2 windows
        XCTAssertEqual(r[2], CGRect(x: 900, y: 450, width: 300, height: 450))
        XCTAssertEqual(r[3], CGRect(x: 0, y: 0, width: 300, height: 900))          // left column
        // Two windows: like Tall.
        XCTAssertEqual(Layout.tile(.threeColumn, count: 2, in: screen, nMaster: 1, ratio: 0.5, gap: 0),
                       Layout.tile(.tall, count: 2, in: screen, nMaster: 1, ratio: 0.5, gap: 0))
    }

    func testWideWindowStaysOnScreen() {
        // Claude needs 600 wide but the right column is only ~300: it grows
        // towards the middle and ends at the screen edge.
        let r = Layout.tile(.threeColumn, count: 3, in: screen, nMaster: 1, ratio: 0.5, gap: 6,
                            minSizes: [nil, CGSize(width: 600, height: 0), nil])
        XCTAssertEqual(r[1].width, 600)
        XCTAssertLessThanOrEqual(r[1].maxX, 1200 - 6)
        XCTAssertGreaterThanOrEqual(r[1].minX, 6)
    }

    func testThreeColumnRatioRoundTrip() {
        let r = Layout.tile(.threeColumn, count: 4, in: screen, nMaster: 1, ratio: 0.4, gap: 6)
        for i in 0..<4 {
            let back = Layout.ratio(afterResizing: r[i], index: i, count: 4, kind: .threeColumn, in: screen,
                                    nMaster: 1, gap: 6)!
            XCTAssertEqual(back, 0.4, accuracy: 0.01, "window \(i)")
        }
    }
}

final class BackAndForthTests: XCTestCase {
    func testPreviousWorkspacePerScreen() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        XCTAssertNil(ss.previousWorkspace)
        ss.greedyView(4)
        XCTAssertEqual(ss.previousWorkspace, 0)
        ss.greedyView(6)
        XCTAssertEqual(ss.previousWorkspace, 4)
        ss.greedyView(ss.previousWorkspace!)          // back
        XCTAssertEqual(ss.currentWorkspaceIndex, 4)
        XCTAssertEqual(ss.previousWorkspace, 6)       // and forth
        ss.focusScreen(1)
        XCTAssertNil(ss.previousWorkspace)            // the other screen has its own history
    }

    func testCycleRespectsAllowed() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 1)
        ss.insert(1, into: 7); ss.insert(2, into: 8)
        XCTAssertEqual(ss.cycleTarget(+1, skipEmpty: true, allowed: { $0 != 7 }), 8)
    }
}

final class ScreenMatcherTests: XCTestCase {
    let screens = [ScreenInfo(name: "Built-in Retina Display", builtin: true, main: false),
                   ScreenInfo(name: "DELL U2723QE", builtin: false, main: true)]

    func testPatterns() {
        XCTAssertEqual(ScreenMatcher.index(for: "external", in: screens), 1)
        XCTAssertEqual(ScreenMatcher.index(for: "builtin", in: screens), 0)
        XCTAssertEqual(ScreenMatcher.index(for: "main", in: screens), 1)
        XCTAssertEqual(ScreenMatcher.index(for: "1", in: screens), 0)
        XCTAssertEqual(ScreenMatcher.index(for: "dell", in: screens), 1)
        XCTAssertNil(ScreenMatcher.index(for: "3", in: screens))
        XCTAssertNil(ScreenMatcher.index(for: "external", in: [screens[0]]))        // not connected
    }
}

final class RoundSixSettingsTests: XCTestCase {
    func testDefaults() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertEqual(s.mouseFollowsFocus, .window)
        XCTAssertFalse(s.focusFollowsMouse)
        XCTAssertFalse(s.workspaceBackAndForth)
        XCTAssertEqual(s.workspaceScreens, [:])
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt], key: "tab")], .workspaceBack)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt, .shift], key: "a")], .taller)
    }

    func testValues() throws {
        let s = try Settings.parse("""
        mouse-follows-focus: screen
        focus-follows-mouse: true
        workspace-back-and-forth: true
        workspace-screens:
          "8": external
          "9": DELL
        """)
        XCTAssertEqual(s.mouseFollowsFocus, .screen)
        XCTAssertTrue(s.focusFollowsMouse)
        XCTAssertEqual(s.workspaceScreens, ["8": "external", "9": "DELL"])
        XCTAssertEqual(try Settings.parse("mouse-follows-focus: true").mouseFollowsFocus, .window)
        XCTAssertEqual(try Settings.parse("mouse-follows-focus: false").mouseFollowsFocus, .off)
        XCTAssertThrowsError(try Settings.parse("workspace-screens:\n  \"12\": external"))
        XCTAssertThrowsError(try Settings.parse("mouse-follows-focus: sometimes"))
    }
}


final class MasterSkipsFloatingTests: XCTestCase {
    func testMasterIsFirstTiledWindow() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        ss.insert(3); ss.insert(2); ss.insert(1)             // [1,2,3]
        ss.floating.insert(1)                                // a floating dialog in front
        ss.focusMaster()
        XCTAssertEqual(ss.current.focused, 2)
        ss.focus(3)
        ss.swapMaster()
        XCTAssertEqual(ss.current.windows, [1, 3, 2])        // the dialog stays where it is
        ss.focus(1)
        ss.swapMaster()                                      // floating: no-op
        XCTAssertEqual(ss.current.windows, [1, 3, 2])
    }
}


final class CycleSkipsInvisibleTests: XCTestCase {
    func testFocusAndSwapSkipInvisibleWindows() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        ss.insert(4); ss.insert(3); ss.insert(2); ss.insert(1)     // [1,2,3,4], focus 1
        let ghost: Set<WindowID> = [1]                              // e.g. Calendar's closed window
        ss.focus(2)
        ss.focusUp(skipping: ghost)
        XCTAssertEqual(ss.current.focused, 4)                       // wraps past the ghost
        ss.focusDown(skipping: ghost)
        XCTAssertEqual(ss.current.focused, 2)                       // and back, past it again
        ss.swapUp(skipping: ghost)
        XCTAssertEqual(ss.current.windows, [1, 4, 3, 2])            // swapped with 4, ghost untouched
    }

    func testFromAnInvisibleFocus() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        ss.insert(3); ss.insert(2); ss.insert(1)                    // focus 1
        ss.focusDown(skipping: [1])
        XCTAssertEqual(ss.current.focused, 2)
    }
}
