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
        // rules: is a block list in the default config; replacing it drops its entries.
        let t = Settings.setTopLevel(base, key: "rules", value: "[]")
        let s = try Settings.parse(t)
        XCTAssertEqual(s.rules, [])
        XCTAssertEqual(s.keys.count, try Settings.parse(base).keys.count)      // nothing else broke
        XCTAssertTrue(t.contains("# Rules, like xmonad's manageHook"))
        XCTAssertFalse(t.contains("com.apple.archiveutility"))
    }

    func testBarWindows() throws {
        let d = try Settings.parse(Settings.defaultYAML).bar
        XCTAssertEqual(d.windows, .tabs)
        XCTAssertTrue(d.windowsFullOnly)
        XCTAssertFalse(d.workspaceCounts)
        var t = Settings.setNested(Settings.defaultYAML, section: "bar", key: "windows", value: "dots")
        t = Settings.setNested(t, section: "bar", key: "windows-full-only", value: "false")
        t = Settings.setNested(t, section: "bar", key: "workspace-counts", value: "true")
        let b = try Settings.parse(t).bar
        XCTAssertEqual(b.windows, .dots)
        XCTAssertFalse(b.windowsFullOnly)
        XCTAssertTrue(b.workspaceCounts)
        // A bare `off` is a YAML boolean.
        XCTAssertEqual(try Settings.parse("bar:\n  windows: off").bar.windows, .off)
        XCTAssertThrowsError(try Settings.parse("bar:\n  windows: list"))
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

final class ScratchpadEditAndConflictTests: XCTestCase {
    func testSetScratchpadsRoundTrip() throws {
        var notes = Scratchpad(name: "notes", app: "com.apple.TextEdit")
        notes.title = "quicknotes.txt"; notes.run = "open -a TextEdit ~/Documents/quicknotes.txt"
        notes.width = 0.4; notes.height = 0.6; notes.position = .top
        let base = try Settings.parse(Settings.defaultYAML)
        let t = Settings.setScratchpads(Settings.defaultYAML, base.scratchpads + [notes])
        let s = try Settings.parse(t)
        XCTAssertEqual(s.scratchpads.map(\.name), ["term", "notes"])
        XCTAssertEqual(s.scratchpads[1], notes)
        XCTAssertEqual(s.scratchpads[0].run, base.scratchpads[0].run)            // quoted run survives
        XCTAssertEqual(s.keys.count, base.keys.count)
        XCTAssertTrue(t.contains("# Scratchpads, like xmonad's NamedScratchpad"))
        // Remove all: the key using `term` has to go too, so test the list alone.
        let empty = Settings.setScratchpads("scratchpads:\n  - name: a\n    app: X\nkeys:\n  mod-1: workspace 1\n", [])
        XCTAssertEqual(try Settings.parse(empty).scratchpads, [])
    }

    func testSkhdParsing() {
        let rc = """
        # comment
        lalt - q: skhd --key "cmd - w"
        lalt - return: open -n -a alacritty
        lalt + cmd - f: open -n ~
        shift + alt - 0x2C : something
        """
        let c = KeyConflicts.skhd(rc)
        XCTAssertEqual(c[KeyChord(modifiers: [.alt], key: "q")], "skhd --key \"cmd - w\"")
        XCTAssertNotNil(c[KeyChord(modifiers: [.alt], key: "return")])
        XCTAssertNotNil(c[KeyChord(modifiers: [.alt, .cmd], key: "f")])
        XCTAssertEqual(c.count, 3)                                               // hex keycodes skipped
    }
}
