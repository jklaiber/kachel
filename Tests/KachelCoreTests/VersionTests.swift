import XCTest
@testable import KachelCore

final class VersionTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(ReleaseVersion("v0.1.17")?.description, "0.1.17")
        XCTAssertEqual(ReleaseVersion("0.2")?.description, "0.2")
        XCTAssertNil(ReleaseVersion("dev"))
        XCTAssertNil(ReleaseVersion("0.0.0-dev"))
        XCTAssertNil(ReleaseVersion("0.0.0"))
        XCTAssertNil(ReleaseVersion("1.2-beta"))
        XCTAssertNil(ReleaseVersion(""))
    }

    func testOrder() {
        func v(_ s: String) -> ReleaseVersion { ReleaseVersion(s)! }
        XCTAssertLessThan(v("0.1.9"), v("0.1.10"))       // numbers, not text
        XCTAssertLessThan(v("0.1.17"), v("0.2.0"))
        XCTAssertLessThan(v("0.9.9"), v("1.0"))
        XCTAssertEqual(v("1.0"), v("1.0.0"))
        XCTAssertFalse(v("0.1.17") < v("0.1.17"))
    }

    func testCheckForUpdatesSetting() throws {
        XCTAssertTrue(try Settings.parse(Settings.defaultYAML).checkForUpdates)
        XCTAssertFalse(try Settings.parse("check-for-updates: false").checkForUpdates)
    }
}
