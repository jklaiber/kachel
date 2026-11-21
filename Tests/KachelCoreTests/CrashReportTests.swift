import XCTest
@testable import KachelCore

final class CrashReportTests: XCTestCase {
    /// A real crash (trimmed): the battery watcher of 0.1.15.
    private func fixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/battery-crash.ips")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesRealReport() throws {
        let r = try XCTUnwrap(CrashReport.parse(try fixture()))
        XCTAssertEqual(r.appVersion, "0.0.0-dev")
        XCTAssertEqual(r.osVersion, "26.5.2 (25F84)")
        XCTAssertEqual(r.exception, "EXC_BAD_ACCESS (SIGBUS)")
        XCTAssertEqual(r.kachelSymbol, "closure #1 in Battery.init()")
        XCTAssertTrue(r.frames[1].contains("Kachel"))
        XCTAssertTrue(r.frames[1].hasSuffix("Battery.swift:25"))
        XCTAssertFalse(r.summary.contains("/Users/"), "no paths in the report")
    }

    func testIssueURLFillsTheBugForm() throws {
        let r = try XCTUnwrap(CrashReport.parse(try fixture()))
        let url = try XCTUnwrap(r.issueURL())
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["template"], "bug_report.yml")
        XCTAssertEqual(q["title"], "Crash: EXC_BAD_ACCESS (SIGBUS) in closure #1 in Battery.init()")
        XCTAssertEqual(q["kachel"], "0.0.0-dev")
        XCTAssertTrue(q["log"]?.contains("Crashed thread:") == true)
        XCTAssertLessThan(url.absoluteString.count, 8000, "GitHub cuts off long URLs")
    }

    func testGarbageIsNil() {
        XCTAssertNil(CrashReport.parse("not a crash report"))
        XCTAssertNil(CrashReport.parse("{}\nnope"))
    }
}
