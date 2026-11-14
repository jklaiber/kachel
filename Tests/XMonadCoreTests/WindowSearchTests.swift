import XCTest
@testable import XMonadCore

final class WindowSearchTests: XCTestCase {
    let windows: [WindowSearch.Candidate] = [
        .init(id: 1, app: "Claude", title: "Claude", workspace: 0, recency: 0, isFocused: true),
        .init(id: 2, app: "Google Chrome", title: "Julian Klaiber — Software", workspace: 1, recency: 1, isFocused: false),
        .init(id: 3, app: "Hermes", title: "Hermes", workspace: 1, recency: 3, isFocused: false),
        .init(id: 4, app: "Code", title: "home-stack — chronyd.conf", workspace: 2, recency: 2, isFocused: false),
        .init(id: 5, app: "Google Chrome", title: "GitHub — xmonadmac", workspace: 4, recency: 4, isFocused: false),
    ]

    func testEmptyQueryIsOverviewByWorkspace() {
        XCTAssertEqual(WindowSearch.results("", in: windows).map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(WindowSearch.results("   ", in: windows).count, 5)
    }

    func testAppNameBeatsTitleAndRecencyBreaksTies() {
        // "chr": both Chromes by app name, then "chronyd" in a title.
        XCTAssertEqual(WindowSearch.results("chr", in: windows).map(\.id), [2, 5, 4])
    }

    func testWordStartsAcrossTitle() {
        XCTAssertEqual(WindowSearch.results("hs", in: windows).first?.id, 4)     // home-stack
        XCTAssertEqual(WindowSearch.results("xmon", in: windows).map(\.id), [5])
    }

    func testMultipleWordsMustAllMatch() {
        XCTAssertEqual(WindowSearch.results("chrome git", in: windows).map(\.id), [5])
        XCTAssertEqual(WindowSearch.results("chrome zzz", in: windows), [])
    }

    func testFocusedWindowGoesLast() {
        let r = WindowSearch.results("c", in: windows)
        XCTAssertEqual(r.last?.id, 1)
    }

    func testScore() {
        XCTAssertNil(WindowSearch.score("xyz", in: "Chrome"))
        XCTAssertNotNil(WindowSearch.score("cme", in: "Chrome"))
        XCTAssertGreaterThan(WindowSearch.score("chr", in: "Chrome")!, WindowSearch.score("chr", in: "home-stack — chronyd")!)
    }
}
