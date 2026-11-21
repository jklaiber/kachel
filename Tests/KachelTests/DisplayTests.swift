import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// Several displays, all made up: arrangements, pins, plugging in and out.
final class DisplayTests: WindowManagerTestCase {
    // MARK: arrangements

    func testEachDisplayTilesItsOwnWorkspace() throws {
        try start(displays: [Self.laptop, Self.dell])
        let a = sys.open("com.apple.Safari")
        refresh()
        try run("focus-next-screen")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        XCTAssertEqual(workspace(of: a), "1")
        XCTAssertEqual(workspace(of: b), "2")
        XCTAssertEqual(display(of: a), "Built-in Retina Display")
        XCTAssertEqual(display(of: b), "DELL U2720Q")
        // Alone on their display: the whole usable area. Only the main display has the menu bar.
        XCTAssertEqual(a.frame, Self.laptop.visible)
        XCTAssertEqual(b.frame, Self.dell.frame)
    }

    func testDisplayAboveTheLaptop() throws {
        let above = Screen.fake(CGRect(x: -500, y: -1440, width: 2560, height: 1440), name: "LG UltraFine")
        try start(displays: [Self.laptop, above])
        // Ordered left to right: the LG starts further left, so it's display 1.
        XCTAssertEqual(wm.screens.map(\.name), ["LG UltraFine", "Built-in Retina Display"])
        let a = sys.open("com.apple.Safari")
        refresh()
        XCTAssertEqual(display(of: a), "LG UltraFine")
        XCTAssertEqual(a.frame, above.frame)
    }

    func testNoPaddingOnTheBuiltInDisplay() throws {
        try start(displays: [Self.laptop, Self.dell], config: "padding: 20\nbuiltin-display-padding: false\n")
        let a = sys.open("com.apple.Safari")
        refresh()
        try run("focus-next-screen")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        XCTAssertEqual(a.frame, Self.laptop.visible, "no space at the laptop's edges")
        XCTAssertEqual(b.frame, Self.dell.frame.insetBy(dx: 20, dy: 20))
    }

    // MARK: pins (workspace-screens)

    func testPinnedWorkspaceAppearsOnItsDisplay() throws {
        try start(displays: [Self.laptop, Self.dell], config: "workspace-screens: {\"9\": builtin, \"5\": DELL}\n")
        let mail = sys.open("com.apple.mail")
        refresh()
        wm.ss.focus(mail.id)
        try run("shift 9")
        try run("focus-next-screen")              // you're on the DELL…
        try run("workspace 9")                    // …but 9 belongs on the laptop
        XCTAssertEqual(display(of: mail), "Built-in Retina Display")
        XCTAssertEqual(wm.ss.screenWorkspace[0], wm.ss.workspaces.firstIndex { $0.tag == "9" })
    }

    func testPinToMissingDisplayFallsBackToHere() throws {
        try start(displays: [Self.laptop], config: "workspace-screens: {\"5\": DELL}\n")
        let a = sys.open("com.apple.Safari")
        refresh()
        wm.ss.focus(a.id)
        try run("shift 5")
        try run("workspace 5")
        XCTAssertEqual(display(of: a), "Built-in Retina Display")
        XCTAssertFalse(isParked(a))
    }

    // MARK: plugging in and out

    func testUnplugExternalKeepsWindowsOnTheirWorkspaces() throws {
        try start(displays: [Self.laptop, Self.dell])
        let a = sys.open("com.apple.Safari")
        refresh()
        try run("focus-next-screen")
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        connect([Self.laptop])
        XCTAssertEqual(workspace(of: a), "1")
        XCTAssertEqual(workspace(of: b), "2", "not lost, just out of sight")
        XCTAssertEqual(display(of: a), "Built-in Retina Display")
        XCTAssertTrue(isParked(b))
        XCTAssertEqual(a.frame, Self.laptop.visible)
    }

    /// The display that stays keeps showing what it showed, even when the
    /// one you unplug is to its left.
    func testUnplugLeftDisplayKeepsTheOtherOnesWorkspace() throws {
        let leftDell = Screen.fake(CGRect(x: -2560, y: 0, width: 2560, height: 1440), name: "DELL U2720Q")
        try start(displays: [Self.laptop, leftDell])
        // Display order: DELL (left) shows 1, laptop shows 2.
        let onLaptop = sys.open("com.apple.Notes", pid: 1001, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        try run("focus-next-screen")
        refresh()
        XCTAssertEqual(workspace(of: onLaptop), "2")
        connect([Self.laptop])
        XCTAssertEqual(wm.ss.workspaces[wm.ss.screenWorkspace[0]].tag, "2", "the laptop still shows 2")
        XCTAssertEqual(display(of: onLaptop), "Built-in Retina Display")
        XCTAssertFalse(isParked(onLaptop))
    }

    /// Plugged back in, the display shows what it showed before.
    func testReplugBringsBackTheDisplaysWorkspace() throws {
        try start(displays: [Self.laptop, Self.dell])
        try run("focus-next-screen")
        try run("workspace 5")                    // the DELL shows 5
        let b = sys.open("com.apple.Notes", pid: 1001)
        refresh()
        XCTAssertEqual(workspace(of: b), "5")
        connect([Self.laptop])
        try run("workspace 3")                    // meanwhile on the laptop
        connect([Self.laptop, Self.dell])
        XCTAssertEqual(display(of: b), "DELL U2720Q")
        XCTAssertFalse(isParked(b))
        XCTAssertEqual(wm.ss.workspaces[wm.ss.screenWorkspace[0]].tag, "3", "the laptop keeps 3")
    }

    /// A pinned workspace goes back to its display when that's plugged in.
    func testReplugBringsPinnedWorkspaceHome() throws {
        try start(displays: [Self.laptop], config: "workspace-screens: {\"8\": DELL}\n")
        let slack = sys.open("com.tinyspeck.slackmacgap")
        refresh()
        wm.ss.focus(slack.id)
        try run("shift 8")
        connect([Self.laptop, Self.dell])
        XCTAssertEqual(display(of: slack), "DELL U2720Q")
        XCTAssertFalse(isParked(slack))
    }

    /// Saving the config re-reads the displays: nothing may move.
    func testConfigReloadKeepsEverything() throws {
        try start(displays: [Self.laptop, Self.dell])
        try run("workspace 4")
        try run("focus-next-screen")
        try run("workspace 7")
        let before = (wm.ss.screenWorkspace, wm.ss.currentScreen)
        connect([Self.laptop, Self.dell])        // same displays, like a reload
        XCTAssertEqual(wm.ss.screenWorkspace, before.0)
        XCTAssertEqual(wm.ss.currentScreen, before.1)
    }

    /// Lid closed: only the external display is left, and it keeps its
    /// workspace and the focus moves to it.
    func testLidClosedKeepsTheExternalDisplay() throws {
        try start(displays: [Self.laptop, Self.dell])
        try run("focus-next-screen")
        try run("workspace 6")
        try run("focus-next-screen")              // back on the laptop
        connect([Self.dell])
        XCTAssertEqual(wm.ss.workspaces[wm.ss.screenWorkspace[0]].tag, "6")
        XCTAssertEqual(wm.ss.currentScreen, 0)
    }

    /// Two monitors of the same model: unplugging the right one and plugging
    /// it back in gives each its own workspace again.
    func testTwoIdenticalMonitors() throws {
        let left = Screen.fake(CGRect(x: 0, y: 0, width: 2560, height: 1440), name: "DELL U2720Q", main: true)
        let right = Screen.fake(CGRect(x: 2560, y: 0, width: 2560, height: 1440), name: "DELL U2720Q")
        try start(displays: [left, right])
        try run("workspace 3")
        try run("focus-next-screen")
        try run("workspace 4")
        connect([left])
        XCTAssertEqual(wm.ss.workspaces[wm.ss.screenWorkspace[0]].tag, "3")
        connect([left, right])
        XCTAssertEqual(wm.ss.screenWorkspace.map { wm.ss.workspaces[$0].tag }, ["3", "4"])
    }
}
