import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

final class WorkspaceLayoutTests: WindowManagerTestCase {
    private func layout(_ tag: String) -> LayoutKind? { wm.ss.workspaces.first { $0.tag == tag }?.layout }

    func testConfiguredLayoutsAtStart() throws {
        try start(config: "workspace-layouts: {\"2\": full}\n")
        XCTAssertEqual(layout("2"), .full)
        XCTAssertEqual(layout("1"), .tall)
    }

    /// Changing it (in Settings or the file) applies right away, also to a
    /// workspace that isn't on screen.
    func testChangingTheConfigApplies() throws {
        try start()
        Config.use(try Settings.parse("gap: 0\nworkspace-layouts: {\"3\": wide}\n"))
        wm.applySettings(rebindKeys: false)
        XCTAssertEqual(layout("3"), .mirrorTall)
    }

    /// Switching layouts with the keys still works; the config only sets the start.
    func testKeysStillChangeIt() throws {
        try start(config: "workspace-layouts: {\"1\": full}\n")
        try run("layout tall")
        XCTAssertEqual(layout("1"), .tall)
        wm.applySettings(rebindKeys: false)           // e.g. another setting saved
        XCTAssertEqual(layout("1"), .tall, "an unrelated config save doesn't reset it")
    }

    /// After a restart: configured workspaces start as configured, the others
    /// get back the layout they had.
    func testRestartConfiguredWinsOthersKeepTheirs() throws {
        let store = MemoryStateStore()
        try start(displays: [Self.laptop], config: "workspace-layouts: {\"1\": full}\n", store: store)
        try run("layout tall")                         // on 1
        try run("workspace 4")
        try run("layout wide")
        wm.saveSnapshot()
        try start(displays: [Self.laptop], config: "workspace-layouts: {\"1\": full}\n", store: store)
        wm.adoptExistingWindows()
        XCTAssertEqual(layout("1"), .full)
        XCTAssertEqual(layout("4"), .mirrorTall)
    }
}
