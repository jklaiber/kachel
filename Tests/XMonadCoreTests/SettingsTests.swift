import XCTest
@testable import XMonadCore

final class SettingsTests: XCTestCase {
    func testDefaultsParse() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertEqual(s.mod, [.ctrl, .alt])
        XCTAssertEqual(s.workspaces.count, 9)
        XCTAssertEqual(s.keys.count, 42)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt], key: "1")], .greedyView(0))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt, .shift], key: "9")], .shift(8))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt, .shift], key: "return")], .terminal)
        XCTAssertTrue(s.bar.enabled)
    }

    func testPartialFileKeepsDefaultKeysWithNewMod() throws {
        let s = try Settings.parse("mod: cmd+alt\ngap: 10\n")
        XCTAssertEqual(s.gap, 10)
        XCTAssertEqual(s.keys.count, 42)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.cmd, .alt], key: "j")], .focusDown)
    }

    func testCustomKeysReplaceDefaults() throws {
        let s = try Settings.parse("""
        workspaces: [web, code, chat]
        keys:
          mod-1: workspace 1
          cmd-shift-t: spawn open -na Ghostty
          ctrl+alt+f5: view 3
          mod-x: ~
        """)
        XCTAssertEqual(s.workspaces, ["web", "code", "chat"])
        XCTAssertEqual(s.keys.count, 3)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.cmd, .shift], key: "t")], .spawn("open -na Ghostty"))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt], key: "f5")], .view(2))
    }

    func testEmptyFileIsDefaults() throws {
        XCTAssertEqual(try Settings.parse("").keys.count, 42)
    }

    func testErrors() {
        XCTAssertThrowsError(try Settings.parse("gapp: 3"))
        XCTAssertThrowsError(try Settings.parse("keys:\n  mod-1: workspace 10"))
        XCTAssertThrowsError(try Settings.parse("keys:\n  hyper-1: quit"))
        XCTAssertThrowsError(try Settings.parse("keys:\n  mod-1: fly"))
        XCTAssertThrowsError(try Settings.parse("bar:\n  enabled: maybe"))
    }

    func testSetTagsShrinkMovesWindows() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        ss.greedyView(8)                 // screen 0 shows 9
        ss.insert(42)
        ss.setTags(["a", "b", "c"])
        XCTAssertEqual(ss.workspaces.map(\.tag), ["a", "b", "c"])
        XCTAssertEqual(ss.workspaceIndex(of: 42), 2)
        XCTAssertEqual(ss.screenWorkspace.count, 2)
        XCTAssertEqual(Set(ss.screenWorkspace).count, 2)
        XCTAssertTrue(ss.screenWorkspace.allSatisfy { $0 < 3 })
    }

    func testSetTagsGrow() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        ss.setTags(["1", "2", "3"])
        XCTAssertEqual(ss.workspaces.count, 3)
    }
}

final class BarConfigTests: XCTestCase {
    func testDefaultBar() throws {
        let b = try Settings.parse(Settings.defaultYAML).bar
        XCTAssertNil(b.height)
        XCTAssertEqual(b.left, [.workspaces, .layout, .title])
        XCTAssertEqual(b.right, [.network, .cpu, .memory, .date, .clock])
    }

    func testOldConfigStillLoads() throws {
        let b = try Settings.parse("bar:\n  height: 24\n  show-title: false\n  clock-format: \"HH:mm\"\n").bar
        XCTAssertEqual(b.height, 24)
        XCTAssertFalse(b.shows(.title))
    }

    func testBackgroundAndAppearance() throws {
        let d = try Settings.parse(Settings.defaultYAML).bar
        XCTAssertEqual(d.background, .transparent)
        XCTAssertEqual(d.appearance, .auto)
        let b = try Settings.parse("bar:\n  background: blur\n  appearance: dark\n").bar
        XCTAssertEqual(b.background, .blur)
        XCTAssertEqual(b.appearance, .dark)
        XCTAssertThrowsError(try Settings.parse("bar:\n  background: glass"))
    }

    func testBadWidget() {
        XCTAssertThrowsError(try Settings.parse("bar:\n  right: [cpu, gpu]"))
    }

    func testSetBarListKeepsCommentsAndOtherLines() throws {
        let text = Settings.setBarList(Settings.defaultYAML, key: "right", [.cpu, .clock])
        let s = try Settings.parse(text)
        XCTAssertEqual(s.bar.right, [.cpu, .clock])
        XCTAssertEqual(s.bar.left, [.workspaces, .layout, .title])
        XCTAssertEqual(s.keys.count, 42)
        XCTAssertTrue(text.contains("# Widgets, in order"))
    }

    func testSetBarListBlockStyleAndMissing() throws {
        let block = "gap: 4\nbar:\n  right:\n    - cpu\n    - memory\n  font-size: 14\nkeys:\n  mod-1: workspace 1\n"
        let t1 = Settings.setBarList(block, key: "right", [.clock])
        XCTAssertEqual(try Settings.parse(t1).bar.right, [.clock])
        XCTAssertEqual(try Settings.parse(t1).bar.fontSize, 14)
        let t2 = Settings.setBarList("gap: 4\n", key: "left", [])
        XCTAssertEqual(try Settings.parse(t2).bar.left, [])
    }
}
