import XCTest
@testable import XMonadCore

final class RulesTests: XCTestCase {
    func testParseAndMatch() throws {
        let s = try Settings.parse("""
        rules:
          - app: com.tinyspeck.slackmacgap
            workspace: 9
          - app: Calculator
            float: true
          - app: com.google.Chrome
            title: Meet
            workspace: 5
        """)
        XCTAssertEqual(s.rules.count, 3)
        XCTAssertEqual(s.rule(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "x")?.workspace, "9")
        XCTAssertEqual(s.rule(bundleID: "com.apple.calculator", appName: "calculator", title: "")?.float, true)
        XCTAssertEqual(s.rule(bundleID: "com.google.Chrome", appName: "Google Chrome", title: "Daily — Google Meet")?.workspace, "5")
        XCTAssertNil(s.rule(bundleID: "com.google.Chrome", appName: "Google Chrome", title: "GitHub"))
        XCTAssertEqual(s.workspaceIndex(named: "9"), 8)
    }

    func testDefaultHasEmptyRules() throws {
        XCTAssertEqual(try Settings.parse(Settings.defaultYAML).rules, [])
    }

    func testBadRules() {
        XCTAssertThrowsError(try Settings.parse("rules:\n  - app: X\n    workspace: 12"))
        XCTAssertThrowsError(try Settings.parse("rules:\n  - workspace: 2"))
        XCTAssertThrowsError(try Settings.parse("rules:\n  - app: X\n    screen: 2"))
    }

    func testSetRuleOnDefaultConfig() throws {
        var text = Settings.setRule(Settings.defaultYAML, app: "com.tinyspeck.slackmacgap",
                                    rule: Rule(app: "com.tinyspeck.slackmacgap", workspace: "9"), comment: "Slack")
        var s = try Settings.parse(text)
        XCTAssertEqual(s.rules, [Rule(app: "com.tinyspeck.slackmacgap", workspace: "9")])
        XCTAssertEqual(s.keys.count, 37)                         // nothing else broke
        XCTAssertTrue(text.contains("# Slack"))
        XCTAssertTrue(text.contains("# Rules, like xmonad's manageHook"))

        // Second app, then change the first: order kept, no duplicates.
        text = Settings.setRule(text, app: "com.apple.calculator", rule: Rule(app: "com.apple.calculator", float: true))
        text = Settings.setRule(text, app: "com.tinyspeck.slackmacgap",
                                rule: Rule(app: "com.tinyspeck.slackmacgap", workspace: "2", float: true))
        s = try Settings.parse(text)
        XCTAssertEqual(s.rules, [Rule(app: "com.apple.calculator", float: true),
                                 Rule(app: "com.tinyspeck.slackmacgap", workspace: "2", float: true)])

        // Remove both again.
        text = Settings.setRule(text, app: "com.tinyspeck.slackmacgap", rule: nil)
        text = Settings.setRule(text, app: "com.apple.calculator", rule: nil)
        s = try Settings.parse(text)
        XCTAssertEqual(s.rules, [])
        XCTAssertEqual(s.keys.count, 37)
    }

    func testSetRuleKeepsHandWrittenTitleRules() throws {
        let text = """
        gap: 4
        rules:
          - app: com.google.Chrome
            title: Meet
            workspace: 5
          - app: com.google.Chrome
            workspace: 2
        keys:
          mod-1: workspace 1
        """
        let out = Settings.setRule(text, app: "com.google.Chrome", rule: Rule(app: "com.google.Chrome", workspace: "3"))
        let s = try Settings.parse(out)
        XCTAssertEqual(s.rules, [Rule(app: "com.google.Chrome", title: "Meet", workspace: "5"),
                                 Rule(app: "com.google.Chrome", workspace: "3")])
        XCTAssertEqual(s.gap, 4)
        XCTAssertEqual(s.keys.count, 1)
    }

    func testSetRuleWithoutSection() throws {
        let out = Settings.setRule("gap: 4\nkeys:\n  mod-1: workspace 1\n", app: "Slack", rule: Rule(app: "Slack", workspace: "1"))
        let s = try Settings.parse(out)
        XCTAssertEqual(s.rules, [Rule(app: "Slack", workspace: "1")])
        XCTAssertEqual(s.keys.count, 1)
    }
}
