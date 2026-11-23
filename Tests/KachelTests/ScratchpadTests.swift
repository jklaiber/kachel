import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// Scratchpads that don't come up as expected (issue #7).
final class ScratchpadTests: WindowManagerTestCase {
    /// The config from the issue: the title holds the whole path, but MacVim's
    /// window title shows it differently, so it never matches.
    private let macvim = """
    scratchpads:
      - name: note
        app: org.vim.MacVim
        title: "quicknote.txt (~/My Docs) - VIM"
        run: "mvim ~/My\\\\ Docs/quicknote.txt"
    keys: {}

    """

    private var problem: String? { wm.scratchProblems["note"] }

    /// Pressing the key again while the app is still starting doesn't start
    /// another copy.
    func testNoSecondStartWhileStarting() throws {
        try start(config: macvim)
        try run("scratchpad note")
        clock.advance(by: 2)
        try run("scratchpad note")
        try run("scratchpad note")
        XCTAssertEqual(sys.ran.count, 1)
    }

    /// The issue's case: MacVim opens its window, but the title doesn't
    /// contain the configured text. After the wait, Kachel says so.
    func testWarnsWhenTheTitleDoesntMatch() throws {
        try start(config: macvim)
        try run("scratchpad note")
        sys.open("org.vim.MacVim", title: "quicknote.txt (/Users/me/My Docs) - VIM", pid: 5000)
        refresh()
        XCTAssertNil(problem, "not yet: titles are often set a moment later")
        clock.advance(by: 16)
        let p = try XCTUnwrap(problem)
        XCTAssertTrue(p.contains("no title contains \"quicknote.txt (~/My Docs) - VIM\""), p)
        XCTAssertTrue(p.contains("file name"), "with a hint what to use instead")
    }

    func testWarnsWhenNoWindowAppears() throws {
        try start(config: macvim)
        try run("scratchpad note")
        clock.advance(by: 16)
        XCTAssertEqual(problem, "scratchpad note: started, but no window of org.vim.MacVim appeared")
    }

    /// After the wait it may be started again (maybe you fixed something).
    func testCanStartAgainAfterTheWait() throws {
        try start(config: macvim)
        try run("scratchpad note")
        clock.advance(by: 16)
        try run("scratchpad note")
        XCTAssertEqual(sys.ran.count, 2)
    }

    /// The fixed config from the issue: a short title. The window is taken,
    /// no warning, and the next press puts it away instead of starting it.
    func testShortTitleWorks() throws {
        try start(config: macvim.replacingOccurrences(of: "\"quicknote.txt (~/My Docs) - VIM\"", with: "quicknote.txt"))
        try run("scratchpad note")
        let w = sys.open("org.vim.MacVim", title: "quicknote.txt (/Users/me/My Docs) - VIM", pid: 5000)
        refresh()
        clock.advance(by: 16)
        XCTAssertNil(problem)
        XCTAssertEqual(wm.scratchWindow["note"], w.id)
        try run("scratchpad note")                       // away
        try run("scratchpad note")                       // here again
        XCTAssertEqual(sys.ran.count, 1, "started once")
    }

    /// `run` itself fails (a typo in the path): the bar says how.
    func testFailingRunIsReported() throws {
        try start(config: macvim)
        sys.runResult = (127, "sh: mvim: command not found\n")
        try run("scratchpad note")
        XCTAssertEqual(problem, "scratchpad note: run exited with 127: sh: mvim: command not found")
    }
}
