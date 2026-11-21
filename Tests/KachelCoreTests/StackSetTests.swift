import XCTest
import CoreGraphics
@testable import KachelCore

final class StackSetTests: XCTestCase {
    func makeTwoScreens() -> StackSet {
        StackSet(tags: (1...9).map(String.init), screenCount: 2)
    }

    func testInitialScreens() {
        let ss = makeTwoScreens()
        XCTAssertEqual(ss.screenWorkspace, [0, 1])   // screen A shows 1, screen B shows 2
        XCTAssertEqual(ss.currentScreen, 0)
    }

    func testGreedyViewSwapsVisibleWorkspaces() {
        var ss = makeTwoScreens()
        ss.greedyView(1)                             // on A, press mod-2
        XCTAssertEqual(ss.screenWorkspace, [1, 0])   // A shows 2, B now shows 1
        XCTAssertEqual(ss.currentScreen, 0)
    }

    func testGreedyViewHiddenWorkspace() {
        var ss = makeTwoScreens()
        ss.greedyView(4)
        XCTAssertEqual(ss.screenWorkspace, [4, 1])
    }

    func testViewMovesFocusInsteadOfSwapping() {
        var ss = makeTwoScreens()
        ss.view(1)
        XCTAssertEqual(ss.screenWorkspace, [0, 1])
        XCTAssertEqual(ss.currentScreen, 1)
    }

    func testInsertAboveFocusedAndRemove() {
        var ss = makeTwoScreens()
        ss.insert(10); ss.insert(11); ss.insert(12)
        XCTAssertEqual(ss.current.windows, [12, 11, 10])
        ss.focusDown()                                // focus 11
        ss.insert(13)
        XCTAssertEqual(ss.current.windows, [12, 13, 11, 10])
        XCTAssertEqual(ss.current.focused, 13)
        ss.remove(13)
        XCTAssertEqual(ss.current.focused, 11)        // focus goes down, like xmonad
    }

    func testShiftAndFloatingSurvives() {
        var ss = makeTwoScreens()
        ss.insert(10); ss.floating.insert(10)
        ss.shift(10, to: 5)
        XCTAssertEqual(ss.workspaceIndex(of: 10), 5)
        XCTAssertTrue(ss.floating.contains(10))
        XCTAssertNil(ss.current.focused)
    }

    func testSwapMaster() {
        var ss = makeTwoScreens()
        ss.insert(1); ss.insert(2); ss.insert(3)     // [3,2,1], focus 3
        ss.focusDown(); ss.focusDown()               // focus 1
        ss.swapMaster()
        XCTAssertEqual(ss.current.windows, [1, 2, 3])
    }

    func testScreenCountChange() {
        var ss = makeTwoScreens()
        ss.focusScreen(1)
        ss.setScreenCount(1)
        XCTAssertEqual(ss.screenWorkspace, [0])
        XCTAssertEqual(ss.currentScreen, 0)
        ss.setScreenCount(3)
        XCTAssertEqual(ss.screenWorkspace, [0, 1, 2])
    }

    func testTallLayout() {
        let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let rects = Layout.tile(.tall, count: 3, in: r, nMaster: 1, ratio: 0.5, gap: 0)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 500, height: 600))
        XCTAssertEqual(rects[1], CGRect(x: 500, y: 0, width: 500, height: 300))
        XCTAssertEqual(rects[2], CGRect(x: 500, y: 300, width: 500, height: 300))
    }
}

final class MouseResizeTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testRatioRoundTripsThroughTile() {
        for kind in [LayoutKind.tall, .mirrorTall] {
            let rects = Layout.tile(kind, count: 3, in: screen, nMaster: 1, ratio: 0.62, gap: 6)
            for (i, r) in rects.enumerated() {
                let back = Layout.ratio(afterResizing: r, index: i, count: 3, kind: kind, in: screen, nMaster: 1, gap: 6)!
                XCTAssertEqual(back, 0.62, accuracy: 0.01, "\(kind) window \(i)")
            }
        }
    }

    func testDraggingMasterEdge() {
        // Master dragged wider to x = 700.
        let r = Layout.ratio(afterResizing: CGRect(x: 3, y: 3, width: 694, height: 594), index: 0, count: 2,
                             kind: .tall, in: screen, nMaster: 1, gap: 6)!
        XCTAssertEqual(r, 0.7, accuracy: 0.01)
    }

    func testNoSplitToMove() {
        let f = CGRect(x: 0, y: 0, width: 400, height: 600)
        XCTAssertNil(Layout.ratio(afterResizing: f, index: 0, count: 2, kind: .full, in: screen, nMaster: 1, gap: 0))
        XCTAssertNil(Layout.ratio(afterResizing: f, index: 0, count: 2, kind: .column, in: screen, nMaster: 1, gap: 0))
        XCTAssertNil(Layout.ratio(afterResizing: f, index: 0, count: 1, kind: .tall, in: screen, nMaster: 1, gap: 0))
    }

    func testClamped() {
        let r = Layout.ratio(afterResizing: CGRect(x: 0, y: 0, width: 990, height: 600), index: 0, count: 2,
                             kind: .tall, in: screen, nMaster: 1, gap: 0)!
        XCTAssertEqual(r, 0.9)
    }
}

final class CycleTests: XCTestCase {
    func testCycleSkipsVisibleAndEmpty() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)   // screens show 1 and 2
        ss.insert(10, into: 4)                                               // workspace 5 has a window
        ss.insert(11, into: 7)                                               // workspace 8 too
        XCTAssertEqual(ss.cycleTarget(+1, skipEmpty: true), 4)
        XCTAssertEqual(ss.cycleTarget(-1, skipEmpty: true), 7)               // wraps backwards
        XCTAssertEqual(ss.cycleTarget(+1, skipEmpty: false), 2)              // 2 is on the other screen
        ss.greedyView(4)
        XCTAssertEqual(ss.cycleTarget(+1, skipEmpty: true), 7)
    }

    func testNowhereToGo() {
        let ss = StackSet(tags: ["1", "2"], screenCount: 2)
        XCTAssertNil(ss.cycleTarget(+1, skipEmpty: false))
        let one = StackSet(tags: ["1", "2", "3"], screenCount: 1)
        XCTAssertNil(one.cycleTarget(+1, skipEmpty: true))                   // all empty
    }
}

final class SwapTests: XCTestCase {
    func testSwapWithinWorkspace() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        ss.insert(1); ss.insert(2); ss.insert(3)          // [3,2,1]
        ss.swap(3, 1)
        XCTAssertEqual(ss.current.windows, [1, 2, 3])
        XCTAssertEqual(ss.current.focused, 3)              // focus stays on the dragged window
    }

    func testSwapAcrossWorkspaces() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 2)
        ss.insert(1, into: 0); ss.insert(2, into: 0)       // ws1 [2,1]
        ss.insert(9, into: 1)                              // ws2 [9]
        ss.swap(2, 9)
        XCTAssertEqual(ss.workspaces[0].windows, [9, 1])
        XCTAssertEqual(ss.workspaces[1].windows, [2])
        XCTAssertEqual(ss.workspaces[0].focused, 9)
        XCTAssertEqual(ss.workspaces[1].focused, 2)
    }

    func testSwapUnknownIsNoop() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        ss.insert(1)
        ss.swap(1, 42)
        XCTAssertEqual(ss.current.windows, [1])
    }
}

final class MinimumSizeTests: XCTestCase {
    func testDistributeEqualWithoutMinimums() {
        XCTAssertEqual(Layout.distribute(900, [nil, nil, nil]), [300, 300, 300])
    }

    func testDistributeGivesMinimumsTheirRoom() {
        // Chrome needs 375, the other two share the rest.
        XCTAssertEqual(Layout.distribute(900, [nil, 375, nil]), [262.5, 375, 262.5])
        // A minimum below the share changes nothing.
        XCTAssertEqual(Layout.distribute(900, [nil, 200, nil]), [300, 300, 300])
        // Growing one can push another over its share: both get theirs.
        XCTAssertEqual(Layout.distribute(900, [400, 280, nil]), [400, 280, 220])
    }

    func testWhenItCannotFitWindowsOverlapEvenlyAndStayOnScreen() {
        // Your stack: Claude 400 + VS Code 270 + Chrome 375 in 906.
        let cells = Layout.arrange(906, [400, 270, 375])
        XCTAssertEqual(cells.map(\.length), [400, 270, 375])          // nobody shrinks below its minimum
        XCTAssertEqual(cells[0].offset, 0)
        XCTAssertEqual(cells[2].offset + cells[2].length, 906, accuracy: 0.01)   // last one ends at the edge
        let overlap01 = cells[0].offset + cells[0].length - cells[1].offset
        let overlap12 = cells[1].offset + cells[1].length - cells[2].offset
        XCTAssertEqual(overlap01, overlap12, accuracy: 0.01)            // evenly
    }

    func testArrangeBackToBackWhenItFits() {
        let cells = Layout.arrange(900, [nil, 375, nil])
        XCTAssertEqual(cells.map(\.offset), [0, 262.5, 637.5])
    }

    func testTallStackUsesMinimums() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 906)
        let rects = Layout.tile(.tall, count: 4, in: screen, nMaster: 1, ratio: 0.5, gap: 6,
                                minSizes: [nil, nil, CGSize(width: 100, height: 375), nil])
        XCTAssertEqual(rects[2].height, 375, accuracy: 1)                       // Chrome gets its minimum
        XCTAssertEqual(rects[1].height, rects[3].height, accuracy: 1)          // the others share
        XCTAssertEqual(rects[0].height, 894, accuracy: 1)                      // master untouched (906 minus gaps)
        XCTAssertLessThanOrEqual(rects[3].maxY, 906)                           // still on screen
    }
}

final class SetScreensTests: XCTestCase {
    func testSetScreens() {
        var ss = StackSet(tags: ["1", "2", "3", "4"], screenCount: 2, ratio: 0.5)
        ss.setScreens([2, 0], current: 1)
        XCTAssertEqual(ss.screenWorkspace, [2, 0])
        XCTAssertEqual(ss.currentScreen, 1)
        XCTAssertEqual(ss.currentWorkspaceIndex, 0)
        ss.setScreens([3, 3, 9], current: 5)       // duplicate and unknown dropped
        XCTAssertEqual(ss.screenWorkspace, [3])
        XCTAssertEqual(ss.currentScreen, 0)
        ss.setScreens([], current: 0)
        XCTAssertEqual(ss.screenWorkspace, [0])
    }
}
