import XCTest
@testable import KachelCore

final class WindowMemoryTests: XCTestCase {
    private func mem(_ app: String, _ title: String, ws: Int, order: Int = 0, floating: Bool = false) -> RememberedWindow {
        RememberedWindow(bundleID: app, title: title, workspace: ws, floating: floating, order: order)
    }
    private func win(_ id: WindowID, _ app: String, _ title: String) -> WindowMemory.Candidate {
        .init(id: id, bundleID: app, title: title)
    }

    func testLooseTitles() {
        XCTAssertEqual(WindowMemory.loose("• notes.md — Edited"), "notes.md")
        XCTAssertEqual(WindowMemory.loose("Report.docx (2)"), "report.docx")
        XCTAssertEqual(WindowMemory.loose("main.swift ●"), "main.swift")
        XCTAssertEqual(WindowMemory.loose("Budget – Bearbeitet"), "budget")
        XCTAssertEqual(WindowMemory.loose("zsh"), "zsh")
    }

    func testTitlesAreOnlyKeptAsHashes() throws {
        let m = mem("com.microsoft.Excel", "Q3 salary review", ws: 2)
        let json = String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
        XCTAssertFalse(json.lowercased().contains("salary"))
    }

    func testExactTitleWins() {
        var memory = [mem("com.microsoft.VSCode", "home-stack", ws: 9), mem("com.microsoft.VSCode", "quictun", ws: 8)]
        let r = WindowMemory.match([win(1, "com.microsoft.VSCode", "quictun"), win(2, "com.microsoft.VSCode", "home-stack")], in: &memory)
        XCTAssertEqual(r[1]?.workspace, 8)
        XCTAssertEqual(r[2]?.workspace, 9)
        XCTAssertTrue(memory.isEmpty)
    }

    func testChangedTitleStillFound() {
        var memory = [mem("com.apple.TextEdit", "notes.txt", ws: 3), mem("com.apple.TextEdit", "todo.txt", ws: 5)]
        let r = WindowMemory.match([win(1, "com.apple.TextEdit", "todo.txt — Edited")], in: &memory)
        XCTAssertEqual(r[1]?.workspace, 5)
    }

    func testSameTitleTwiceGoesInOrder() {
        var memory = [mem("com.apple.Terminal", "zsh", ws: 2, order: 0), mem("com.apple.Terminal", "zsh", ws: 6, order: 0)]
        let r = WindowMemory.match([win(10, "com.apple.Terminal", "zsh"), win(11, "com.apple.Terminal", "zsh")], in: &memory)
        XCTAssertEqual(Set([r[10]?.workspace, r[11]?.workspace]), [2, 6], "both placed, one each")
    }

    /// Chrome shows another tab after the restart: if all Chrome windows were
    /// on one workspace, that's where it goes.
    func testUnknownTitleFollowsItsAppsWorkspace() {
        var memory = [mem("com.google.Chrome", "Inbox", ws: 2), mem("com.google.Chrome", "Calendar", ws: 2, order: 1)]
        let r = WindowMemory.match([win(1, "com.google.Chrome", "GitHub"), win(2, "com.google.Chrome", "Docs")], in: &memory)
        XCTAssertEqual(r[1]?.workspace, 2)
        XCTAssertEqual(r[2]?.workspace, 2)
    }

    /// Unknown title and the app was spread over workspaces: no guess.
    func testNoGuessWhenTheAppWasSpread() {
        var memory = [mem("com.google.Chrome", "Inbox", ws: 2), mem("com.google.Chrome", "Calendar", ws: 7)]
        let r = WindowMemory.match([win(1, "com.google.Chrome", "GitHub")], in: &memory)
        XCTAssertNil(r[1])
        XCTAssertEqual(memory.count, 2)
    }

    func testOtherAppsNeverMatch() {
        var memory = [mem("com.apple.Safari", "Start", ws: 4)]
        let r = WindowMemory.match([win(1, "com.google.Chrome", "Start")], in: &memory)
        XCTAssertNil(r[1])
    }

    func testMoreWindowsThanRemembered() {
        var memory = [mem("com.tinyspeck.slackmacgap", "Slack", ws: 4)]
        let r = WindowMemory.match([win(1, "com.tinyspeck.slackmacgap", "Slack"), win(2, "com.tinyspeck.slackmacgap", "Huddle")], in: &memory)
        XCTAssertEqual(r[1]?.workspace, 4)
        XCTAssertNil(r[2], "nothing left to go by")
    }
}
