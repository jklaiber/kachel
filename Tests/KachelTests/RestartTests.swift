import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// The Mac restarts: window IDs start over, apps open their windows again
/// (some right away, some later), titles may have changed.
final class RestartTests: WindowManagerTestCase {
    private let store = MemoryStateStore()

    /// Before: windows spread over workspaces, a layout changed. Kachel
    /// remembers that when it quits (which a restart of the Mac does).
    private func before() throws {
        try start(displays: [Self.laptop], store: store, bootTime: 1_000)
        let code1 = sys.open("com.microsoft.VSCode", title: "README.md — home-stack", pid: 10)
        let code2 = sys.open("com.microsoft.VSCode", title: "main.go — quictun", pid: 10)
        let term = sys.open("com.apple.Terminal", title: "zsh", pid: 11)
        let chrome1 = sys.open("com.google.Chrome", title: "Inbox", pid: 12)
        let chrome2 = sys.open("com.google.Chrome", title: "Calendar", pid: 12)
        refresh()
        for (w, ws) in [(code1, "9"), (code2, "8"), (chrome1, "2"), (chrome2, "2")] {
            wm.ss.focus(w.id)
            try run("shift \(ws)")
        }
        _ = term                                          // stays on 1
        try run("workspace 9")
        try run("layout full")
        try run("workspace 1")
        wm.rememberWindows()
        wm.saveSnapshot()
    }

    /// After: a new Kachel on a freshly started Mac (new boot time), same saved state.
    private func after() throws {
        try start(displays: [Self.laptop], store: store, bootTime: 2_000)
    }

    func testWindowsGoBackToTheirWorkspaces() throws {
        try before()
        try after()
        // Apps that start with the Mac: their windows are there when Kachel starts.
        let code1 = sys.open("com.microsoft.VSCode", title: "README.md — home-stack", pid: 20)
        let code2 = sys.open("com.microsoft.VSCode", title: "• main.go — quictun", pid: 20)   // unsaved now
        let term = sys.open("com.apple.Terminal", title: "zsh", pid: 21)
        wm.adoptExistingWindows()
        XCTAssertEqual(workspace(of: code1), "9")
        XCTAssertEqual(workspace(of: code2), "8", "the title changed a bit")
        XCTAssertEqual(workspace(of: term), "1")
        // Chrome starts a minute later, showing other tabs.
        clock.advance(by: 60)
        let chrome = sys.open("com.google.Chrome", title: "GitHub", pid: 22)
        refresh()
        XCTAssertEqual(workspace(of: chrome), "2", "all its windows were on 2")
        XCTAssertTrue(isParked(chrome), "2 isn't on screen")
    }

    func testLayoutsComeBackToo() throws {
        try before()
        try after()
        wm.adoptExistingWindows()
        let nine = try XCTUnwrap(wm.ss.workspaces.first { $0.tag == "9" })
        XCTAssertEqual(nine.layout, .full)
    }

    /// Long after the start, a window is just a new window again.
    func testOnlyForTheFirstMinutes() throws {
        try before()
        try after()
        wm.adoptExistingWindows()
        clock.advance(by: 15 * 60)
        let code = sys.open("com.microsoft.VSCode", title: "README.md — home-stack", pid: 20)
        refresh()
        XCTAssertEqual(workspace(of: code), "1", "on the current workspace, like any new window")
    }

    /// Same boot (Kachel restarted, the Mac didn't): window IDs still hold, as before.
    func testKachelRestartWithoutRebootUsesWindowIDs() throws {
        try start(displays: [Self.laptop], store: store, bootTime: 1_000)
        let a = sys.open("com.apple.Notes", title: "Shopping", pid: 30)
        refresh()
        wm.ss.focus(a.id)
        try run("shift 5")
        wm.saveSnapshot()
        let windowsBefore = sys.all
        try start(displays: [Self.laptop], store: store, bootTime: 1_000)
        for (_, w) in windowsBefore { sys.adopt(w) }
        wm.adoptExistingWindows()
        XCTAssertEqual(wm.ss.workspaceIndex(of: a.id).map { wm.ss.workspaces[$0].tag }, "5")
    }

    /// The saved state holds no readable titles.
    func testSavedStateHasNoTitles() throws {
        try before()
        let text = String(decoding: try XCTUnwrap(store.data), as: UTF8.self)
        for t in ["home-stack", "quictun", "Inbox", "Calendar"] { XCTAssertFalse(text.contains(t), t) }
    }
}
