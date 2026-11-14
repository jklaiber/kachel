import XCTest
@testable import KachelCore

/// config.example.yaml in the repo root must be exactly the built-in default,
/// so the example on GitHub never goes stale. After changing the default:
///   swift run Kachel --print-default-config > config.example.yaml
final class ExampleConfigTests: XCTestCase {
    func testExampleFileMatchesBuiltInDefault() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("config.example.yaml"), encoding: .utf8)
        XCTAssertEqual(file.trimmingCharacters(in: .newlines), Settings.defaultYAML.trimmingCharacters(in: .newlines),
                       "config.example.yaml is out of date: run `swift run Kachel --print-default-config > config.example.yaml`")
        // And it's a valid config, of course.
        XCTAssertNoThrow(try Settings.parse(file))
    }
}
