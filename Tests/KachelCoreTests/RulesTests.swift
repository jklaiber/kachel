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

    func testSetRuleAtIndex() throws {
        let text = """
        gap: 5
        # Rules: where windows go.
        rules:
          - app: com.microsoft.teams2   # Microsoft Teams: the meeting window
            title: Meeting with
            hide: minimize
          - app: com.microsoft.teams2
            workspace: 3

        # Keys
        keys:
          mod-1: workspace 1
        """
        let teams = Rule(app: "com.microsoft.teams2", title: "Meeting with", hide: .minimize)
        XCTAssertEqual(try Settings.parse(text).rules, [teams, Rule(app: "com.microsoft.teams2", workspace: "3")])

        // Change the titled rule: comment kept, the other rule untouched.
        var t = Settings.setRule(text, at: 0, rule: Rule(app: "com.microsoft.teams2", title: "Meeting in", workspace: "2", float: true, hide: .minimize))
        XCTAssertEqual(try Settings.parse(t).rules, [Rule(app: "com.microsoft.teams2", title: "Meeting in", workspace: "2", float: true, hide: .minimize),
                                                     Rule(app: "com.microsoft.teams2", workspace: "3")])
        XCTAssertTrue(t.contains("- app: com.microsoft.teams2   # Microsoft Teams: the meeting window"))
        XCTAssertTrue(t.contains("# Rules: where windows go.") && t.contains("# Keys"))

        // Clearing the title makes it app-wide; removing the second leaves the first.
        t = Settings.setRule(t, at: 0, rule: Rule(app: "com.microsoft.teams2", hide: .minimize))
        t = Settings.setRule(t, at: 1, rule: nil)
        XCTAssertEqual(try Settings.parse(t).rules, [Rule(app: "com.microsoft.teams2", hide: .minimize)])
        XCTAssertEqual(try Settings.parse(t).keys.count, 1)

        // Adding goes to the end; an empty rules: section gets its first entry.
        t = Settings.addRule(text, Rule(app: "us.zoom.xos", hide: .minimize), comment: "Zoom")
        XCTAssertEqual(try Settings.parse(t).rules.last, Rule(app: "us.zoom.xos", hide: .minimize))
        XCTAssertEqual(try Settings.parse(t).rules.count, 3)
        let empty = Settings.addRule("rules:\n\nkeys:\n  mod-1: workspace 1", Rule(app: "Notes", float: true))
        XCTAssertEqual(try Settings.parse(empty).rules, [Rule(app: "Notes", float: true)])

        // Out of range: unchanged.
        XCTAssertEqual(Settings.setRule(text, at: 5, rule: nil), text)
    }

    func testTitleNot() throws {
        let s = try Settings.parse("""
        rules:
          - app: com.microsoft.teams2
            title-not: [Microsoft Teams, teams.microsoft.com]
            hide: minimize
          - app: Mail
            title-not: Inbox
        """)
        let teams = Rule(app: "com.microsoft.teams2", titleNot: ["Microsoft Teams", "teams.microsoft.com"], hide: .minimize)
        XCTAssertEqual(s.rules, [teams, Rule(app: "Mail", titleNot: ["Inbox"])])
        for meeting in ["Daily stand-up", "Meeting with Ada", "Retro"] {
            XCTAssertEqual(s.rule(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: meeting), teams)
        }
        for main in ["Microsoft Teams", "Chat | Microsoft Teams", "teams.microsoft.com/v2/?cb=17"] {
            XCTAssertNil(s.rule(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", title: main))
        }
        // Written back (one value plain, several as a list) and read again.
        var t = Settings.addRule("rules:\n\nkeys:\n  mod-1: workspace 1", teams)
        t = Settings.addRule(t, Rule(app: "Mail", titleNot: ["Inbox"]))
        XCTAssertTrue(t.contains("title-not: [\"Microsoft Teams\", teams.microsoft.com]") && t.contains("title-not: Inbox"))
        XCTAssertEqual(try Settings.parse(t).rules, [teams, Rule(app: "Mail", titleNot: ["Inbox"])])
        // The rule picker (⌥⇧P) replaces plain rules, not ones that look at the title.
        t = Settings.setRule(t, app: "com.microsoft.teams2", rule: Rule(app: "com.microsoft.teams2", workspace: "3"))
        XCTAssertEqual(try Settings.parse(t).rules.first, teams)
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
