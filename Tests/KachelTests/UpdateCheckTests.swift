import XCTest
@testable import Kachel
@testable import KachelCore

/// The update check against made-up GitHub answers.
final class UpdateCheckTests: XCTestCase {
    private var sent: [URLRequest] = []
    private var answers: [(Int?, String?)] = []      // status (nil: no connection), tag

    private func makeCheck(running: String) -> UpdateCheck {
        Log.enabled = false
        let u = UpdateCheck()
        u.version = { running }
        u.fetch = { [unowned self] req, done in
            self.sent.append(req)
            let (status, tag) = self.answers.removeFirst()
            guard let status else { done(nil, nil, URLError(.notConnectedToInternet)); return }
            let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: ["ETag": "\"abc\""])
            let body = tag.map { #"{"tag_name": "\#($0)", "html_url": "https://github.com/jklaiber/kachel/releases/tag/\#($0)"}"# }
            done(body.map { Data($0.utf8) }, r, nil)
        }
        return u
    }

    private func check(_ u: UpdateCheck) -> UpdateCheck.Outcome? {
        let e = expectation(description: "answer")
        var out: UpdateCheck.Outcome?
        u.checkNow { out = $0; e.fulfill() }
        wait(for: [e], timeout: 2)
        return out
    }

    func testNewerReleaseIsOffered() {
        let u = makeCheck(running: "0.1.22")
        answers = [(200, "v0.1.23")]
        guard case .available(let r)? = check(u) else { return XCTFail("not offered") }
        XCTAssertEqual(r.version, ReleaseVersion("0.1.23"))
        XCTAssertEqual(u.available, r)
        XCTAssertNil(sent[0].value(forHTTPHeaderField: "If-None-Match"), "nothing to compare with yet")
    }

    func testUpToDate() {
        let u = makeCheck(running: "0.1.23")
        answers = [(200, "v0.1.23")]
        XCTAssertEqual(check(u), .upToDate)
        XCTAssertNil(u.available)
        XCTAssertNotNil(u.lastChecked)
    }

    /// The next look asks "anything new since?": GitHub's short "no" keeps the answer.
    func testNothingNewKeepsTheLastAnswer() {
        let u = makeCheck(running: "0.1.22")
        answers = [(200, "v0.1.23"), (304, nil)]
        _ = check(u)
        guard case .available? = check(u) else { return XCTFail("lost the update") }
        XCTAssertEqual(sent[1].value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
        XCTAssertEqual(sent[1].cachePolicy, .reloadIgnoringLocalCacheData)
    }

    /// No connection: says so, and keeps what it knew.
    func testNoConnection() {
        let u = makeCheck(running: "0.1.22")
        answers = [(200, "v0.1.23"), (nil, nil)]
        _ = check(u)
        guard case .failed? = check(u) else { return XCTFail("not a failure") }
        XCTAssertTrue(u.failed)
        XCTAssertNotNil(u.available)
    }

    /// GitHub's limit reached (403): a failure, not "up to date".
    func testRateLimited() {
        let u = makeCheck(running: "0.1.22")
        answers = [(403, nil)]
        XCTAssertEqual(check(u), .failed("GitHub answered 403"))
    }

    func testDevBuildDoesNotAsk() {
        let u = makeCheck(running: "0.0.0-dev")
        XCTAssertNil(check(u))
        XCTAssertTrue(sent.isEmpty)
    }
}
