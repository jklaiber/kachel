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
