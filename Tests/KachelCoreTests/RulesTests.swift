import XCTest
@testable import KachelCore

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

    func testBadRules() {
        XCTAssertThrowsError(try Settings.parse("rules:\n  - app: X\n    workspace: 12"))
        XCTAssertThrowsError(try Settings.parse("rules:\n  - workspace: 2"))
        XCTAssertThrowsError(try Settings.parse("rules:\n  - app: X\n    screen: 2"))
        XCTAssertThrowsError(try Settings.parse("rules:\n  - app: X\n    hide: away"))
    }

    func testHideMinimize() throws {
        let s = try Settings.parse("rules:\n  - app: com.microsoft.teams2\n    title: Meeting with\n    hide: minimize\n  - app: Slack\n    workspace: 2")
        XCTAssertEqual(s.rules, [Rule(app: "com.microsoft.teams2", title: "Meeting with", hide: .minimize),
                                 Rule(app: "Slack", workspace: "2")])
        XCTAssertEqual(s.rule(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: "Meeting with Ada")?.hide, .minimize)
        XCTAssertNil(s.rule(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: "Chat"))

        // Written back by the settings window (app-wide rule), and read again.
        let text = Settings.setRule(Settings.defaultYAML, app: "us.zoom.xos",
                                    rule: Rule(app: "us.zoom.xos", hide: .minimize), comment: "Zoom")
        XCTAssertTrue(text.contains("hide: minimize"))
        XCTAssertEqual(try Settings.parse(text).rules.last, Rule(app: "us.zoom.xos", hide: .minimize))
    }

    func testSetRuleOnDefaultConfig() throws {
        let defaults = [Rule(app: "com.apple.systempreferences", float: true),
                        Rule(app: "com.apple.calculator", float: true),
                        Rule(app: "com.apple.archiveutility", float: true)]
        XCTAssertEqual(try Settings.parse(Settings.defaultYAML).rules, defaults)

        var text = Settings.setRule(Settings.defaultYAML, app: "com.tinyspeck.slackmacgap",
                                    rule: Rule(app: "com.tinyspeck.slackmacgap", workspace: "9"), comment: "Slack")
        var s = try Settings.parse(text)
        XCTAssertEqual(s.rules, defaults + [Rule(app: "com.tinyspeck.slackmacgap", workspace: "9")])
        XCTAssertEqual(s.keys.count, 52)                         // nothing else broke
        XCTAssertTrue(text.contains("# Slack"))
        XCTAssertTrue(text.contains("# Rules, like xmonad's manageHook"))

        // Change an existing app and the new one: no duplicates.
        text = Settings.setRule(text, app: "com.apple.calculator", rule: Rule(app: "com.apple.calculator", workspace: "3"))
        text = Settings.setRule(text, app: "com.tinyspeck.slackmacgap",
                                rule: Rule(app: "com.tinyspeck.slackmacgap", workspace: "2", float: true))
        s = try Settings.parse(text)
        XCTAssertEqual(s.rules, [defaults[0], defaults[2],
                                 Rule(app: "com.apple.calculator", workspace: "3"),
                                 Rule(app: "com.tinyspeck.slackmacgap", workspace: "2", float: true)])

        // Remove them all.
        for app in ["com.tinyspeck.slackmacgap", "com.apple.calculator", "com.apple.systempreferences", "com.apple.archiveutility"] {
            text = Settings.setRule(text, app: app, rule: nil)
        }
        s = try Settings.parse(text)
        XCTAssertEqual(s.rules, [])
        XCTAssertEqual(s.keys.count, 52)
        XCTAssertNoThrow(try Settings.parse(text))
    }

    func testFloatingListIsGone() {
        XCTAssertThrowsError(try Settings.parse("floating:\n  - com.apple.calculator"))
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

final class TopLevelEditTests: XCTestCase {
    func testToggleMenubarIcon() throws {
        let on = Settings.setTopLevel(Settings.defaultYAML, key: "menubar-icon", value: "true")
        XCTAssertTrue(try Settings.parse(on).menubarIcon)
        XCTAssertTrue(on.contains("menubar-icon: true") && on.contains("# Kachel icon in the top menu bar"))
        let off = Settings.setTopLevel(on, key: "menubar-icon", value: "false")
        XCTAssertFalse(try Settings.parse(off).menubarIcon)
        XCTAssertEqual(try Settings.parse(off).keys.count, 52)
        let added = Settings.setTopLevel("gap: 3\nkeys:\n  mod-1: workspace 1\n", key: "menubar-icon", value: "true")
        XCTAssertTrue(try Settings.parse(added).menubarIcon)
    }
}
