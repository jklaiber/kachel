import XCTest
@testable import KachelCore

/// The layouts tall-right, two-pane, rows, widescreen-tall, BSP and floating.
final class LayoutTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func tile(_ k: LayoutKind, _ n: Int, nMaster: Int = 1, ratio: Double = 0.5) -> [CGRect] {
        Layout.tile(k, count: n, in: screen, nMaster: nMaster, ratio: ratio, gap: 0)
    }

    func testConfigNames() {
        for k in LayoutKind.allCases {
            XCTAssertEqual(LayoutKind(configName: k.configName), k, k.configName)
        }
        XCTAssertEqual(LayoutKind(configName: "row"), .row)
        XCTAssertEqual(LayoutKind(configName: "binary-space-partitioning"), .bsp)
    }

    func testTallRight() {
        let r = tile(.tallRight, 3, ratio: 0.6)
        XCTAssertEqual(r[0], CGRect(x: 400, y: 0, width: 600, height: 600))     // master on the right
        XCTAssertEqual(r[1], CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(r[2], CGRect(x: 0, y: 300, width: 400, height: 300))
        XCTAssertEqual(tile(.tallRight, 1), [screen])
    }

    func testTwoPane() {
        let r = tile(.twoPane, 4)
        XCTAssertEqual(r[0], CGRect(x: 0, y: 0, width: 500, height: 600))
        // The rest share the second pane, on top of each other.
        // (No Set of CGRect: that needs macOS 15, Kachel runs from 13.)
        XCTAssertTrue(r[1...].allSatisfy { $0 == CGRect(x: 500, y: 0, width: 500, height: 600) })
        XCTAssertEqual(tile(.twoPane, 1), [screen])
    }

    func testRows() {
        let r = tile(.row, 3)
        XCTAssertEqual(r.map(\.width), [1000, 1000, 1000])
        XCTAssertEqual(r.map(\.minY), [0, 200, 400])
    }

    func testWidescreenTall() {
        let r = tile(.widescreenTall, 4, nMaster: 2, ratio: 0.6)
        XCTAssertEqual(r[0], CGRect(x: 0, y: 0, width: 300, height: 600))        // masters side by side
        XCTAssertEqual(r[1], CGRect(x: 300, y: 0, width: 300, height: 600))
        XCTAssertEqual(r[2], CGRect(x: 600, y: 0, width: 400, height: 300))      // stack on the right
        XCTAssertEqual(r[3], CGRect(x: 600, y: 300, width: 400, height: 300))
    }

    func testBSP() {
        let r = tile(.bsp, 4)
        XCTAssertEqual(r[0], CGRect(x: 0, y: 0, width: 500, height: 600))        // left half
        XCTAssertEqual(r[1], CGRect(x: 500, y: 0, width: 500, height: 300))      // top right
        XCTAssertEqual(r[2], CGRect(x: 500, y: 300, width: 250, height: 300))
        XCTAssertEqual(r[3], CGRect(x: 750, y: 300, width: 250, height: 300))
        // Nothing overlaps and together they fill the screen.
        XCTAssertEqual(r.reduce(0) { $0 + $1.width * $1.height }, 1000 * 600)
    }

    func testFloatingPlacesNothing() {
        XCTAssertEqual(tile(.floating, 3), [])
    }

    func testPrevAndSetLayout() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        let order: [LayoutKind] = [.tall, .full, .bsp]
        ss.setLayout(.full)
        XCTAssertEqual(ss.current.layout, .full)
        ss.prevLayout(in: order)
        XCTAssertEqual(ss.current.layout, .tall)
        ss.prevLayout(in: order)
        XCTAssertEqual(ss.current.layout, .bsp)                                  // wraps around
    }

    func testResizingTallRightMovesTheSplit() {
        let r = tile(.tallRight, 2, ratio: 0.5)
        var master = r[0]
        master.origin.x -= 100; master.size.width += 100                          // dragged its left edge left
        let ratio = Layout.ratio(afterResizing: master, index: 0, count: 2, kind: .tallRight,
                                 in: screen, nMaster: 1, gap: 0)
        XCTAssertEqual(ratio ?? 0, 0.6, accuracy: 0.001)
    }
}

/// Padding, smart gaps, window limit, follow, and the layout and tiling commands.
final class TilingOptionsTests: XCTestCase {
    func testDefaults() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertNil(s.padding)
        XCTAssertTrue(s.builtinPadding)
        XCTAssertFalse(s.smartGaps)
        XCTAssertEqual(s.windowLimit, 0)
        XCTAssertFalse(s.followMovedWindows)
    }

    func testParse() throws {
        let s = try Settings.parse("""
        padding: 20
        builtin-display-padding: false
        smart-gaps: true
        window-limit: 3
        follow-moved-windows: true
        layouts: [tall, tall-right, two-pane, rows, widescreen-tall, bsp, floating]
        """)
        XCTAssertEqual(s.padding, 20)
        XCTAssertFalse(s.builtinPadding)
        XCTAssertTrue(s.smartGaps)
        XCTAssertEqual(s.windowLimit, 3)
        XCTAssertTrue(s.followMovedWindows)
        XCTAssertEqual(s.layouts, [.tall, .tallRight, .twoPane, .row, .widescreenTall, .bsp, .floating])
        XCTAssertNil(try Settings.parse("padding: auto").padding)
    }

    func testCommands() throws {
        func cmd(_ t: String) throws -> Command { try Settings.parseCommand(t, workspaceCount: 9, context: "test") }
        XCTAssertEqual(try cmd("layout full"), .setLayout(.full))
        XCTAssertEqual(try cmd("layout bsp"), .setLayout(.bsp))
        XCTAssertEqual(try cmd("prev-layout"), .prevLayout)
        XCTAssertEqual(try cmd("toggle-tiling"), .toggleTiling)
        XCTAssertEqual(try cmd("toggle-focus-follows-mouse"), .toggleFocusFollowsMouse)
        XCTAssertEqual(try cmd("increase-window-limit"), .increaseWindowLimit)
        XCTAssertEqual(try cmd("decrease-window-limit"), .decreaseWindowLimit)
        XCTAssertThrowsError(try cmd("layout spiral"))
        // Written back as they're read.
        for c: Command in [.setLayout(.tallRight), .prevLayout, .toggleTiling, .toggleFocusFollowsMouse,
                           .increaseWindowLimit, .decreaseWindowLimit] {
            XCTAssertEqual(try cmd(c.configText), c, c.configText)
        }
    }

    func testEveryLayoutInSettingsOrder() {
        XCTAssertEqual(Set(Settings.layoutOrder), Set(LayoutKind.allCases))
    }
}

final class NativeTabsTests: XCTestCase {
    func testReplaceKeepsPlaceAndFocus() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        for w: WindowID in [1, 2, 3] { ss.insert(w) }
        ss.focus(2)
        ss.setWeights([2: 1.5], workspace: 0)
        ss.floating.insert(2)
        let before = ss.workspaces[0].windows
        ss.replace(2, with: 9)                     // a tab switch in window 2
        XCTAssertEqual(ss.workspaces[0].windows, before.map { $0 == 2 ? 9 : $0 })
        XCTAssertEqual(ss.workspaces[0].focused, 9)
        XCTAssertEqual(ss.workspaces[0].weights[9], 1.5)
        XCTAssertTrue(ss.floating.contains(9))
        XCTAssertFalse(ss.floating.contains(2))
        XCTAssertNil(ss.workspaceIndex(of: 2))
        // Switching back swaps again.
        ss.replace(9, with: 2)
        XCTAssertEqual(ss.workspaces[0].windows, before)
    }
}
