import XCTest
@testable import KachelCore

final class ConfigEditTests: XCTestCase {
    let base = Settings.defaultYAML

    func testTopLevelScalarKeepsComment() throws {
        let t = Settings.setTopLevel(base, key: "gap", value: "12")
        XCTAssertEqual(try Settings.parse(t).gap, 12)
        XCTAssertTrue(t.contains("gap: 12") && t.contains("# points between windows"))
    }

    func testTopLevelBlockListReplaced() throws {
        let t = Settings.setTopLevel(base, key: "floating", value: Settings.flowList(["com.apple.calculator", "My App"]))
        let s = try Settings.parse(t)
        XCTAssertEqual(s.floating, ["com.apple.calculator", "My App"])
        XCTAssertEqual(s.keys.count, try Settings.parse(base).keys.count)      // nothing else broke
        XCTAssertTrue(t.contains("# Bundle IDs whose windows always float"))
    }

    func testNested() throws {
        var t = Settings.setNested(base, section: "bar", key: "clock-format", value: "\"HH:mm:ss\"")
        t = Settings.setNested(t, section: "border", key: "color", value: "\"#5DCAA5\"")
        t = Settings.setNested(t, section: "gestures", key: "fingers", value: "4")
        let s = try Settings.parse(t)
        XCTAssertEqual(s.bar.clockFormat, "HH:mm:ss")
        XCTAssertEqual(s.border.color, "#5DCAA5")
        XCTAssertEqual(s.gestures.fingers, 4)
        XCTAssertTrue(t.contains("# Unicode date patterns"))
        // A key that isn't there yet, and a flow-style section.
        let u = Settings.setNested("bar: {enabled: false}\n", section: "bar", key: "font-size", value: "15")
        XCTAssertEqual(try Settings.parse(u).bar.fontSize, 15)
        XCTAssertFalse(try Settings.parse(u).bar.enabled)
    }

    func testSetKeyFindsTheSameKeyWrittenDifferently() throws {
        let mod: Set<Modifier> = [.alt]
        let chord = KeyChord(modifiers: [.alt], key: "j")
        var t = Settings.setKey(base, chord: chord, chordText: "alt-j", command: "focus left", mod: mod)
        var s = try Settings.parse(t)
        XCTAssertEqual(s.keys[chord], .focusDirection(.left))
        XCTAssertEqual(s.keys.count, try Settings.parse(base).keys.count)      // replaced, not added
        t = Settings.setKey(t, chord: chord, chordText: "alt-j", command: nil, mod: mod)
        s = try Settings.parse(t)
        XCTAssertNil(s.keys[chord])
        t = Settings.setKey(t, chord: KeyChord(modifiers: [.alt], key: "y"), chordText: "mod-y", command: "shortcuts", mod: mod)
        XCTAssertEqual(try Settings.parse(t).keys[KeyChord(modifiers: [.alt], key: "y")], .shortcuts)
    }

    func testQuotedHashIsNotAComment() {
        let t = Settings.setNested("border:\n  color: \"#E8965A\"   # soft orange\n", section: "border", key: "color", value: "accent")
        XCTAssertTrue(t.contains("color: accent") && t.contains("# soft orange"))
        XCTAssertFalse(t.contains("E8965A"))
    }
}

final class CommandTextTests: XCTestCase {
    func testEveryCommandRoundTrips() throws {
        let all: [Command] = [
            .greedyView(2), .view(0), .shift(8), .focusScreen(1), .shiftToScreen(0),
            .focusDown, .focusUp, .focusMaster, .swapDown, .swapUp, .swapMaster,
            .nextLayout, .shrink, .expand, .incMaster, .decMaster,
            .focusNextScreen, .focusPrevScreen, .shiftToNextScreen, .shiftToPrevScreen,
            .workspaceNext, .workspacePrev, .shiftNext, .shiftPrev,
            .toggleFloat, .refresh, .close, .terminal, .reload, .restart, .quit,
            .windowSearch, .appRule, .toggleFullscreen, .workspaceBack, .taller, .shorter, .resetSizes,
            .settings, .welcome, .shortcuts,
            .focusDirection(.left), .swapDirection(.down), .scratchpad("term"), .spawn("open -a Safari"),
        ]
        for c in all {
            XCTAssertEqual(try Settings.parseCommand(c.configText, workspaceCount: 9, context: "test"), c, c.configText)
        }
    }
}
