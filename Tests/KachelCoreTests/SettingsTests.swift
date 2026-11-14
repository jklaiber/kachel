import XCTest
import CoreGraphics
@testable import KachelCore

final class SettingsTests: XCTestCase {
    func testDefaultsParse() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertEqual(s.mod, [.alt])
        XCTAssertEqual(s.workspaces.count, 9)
        XCTAssertEqual(s.keys.count, 39)
        XCTAssertEqual(s.layouts, [.tall, .mirrorTall, .column, .full])
        XCTAssertEqual(s.gap, 5)
        XCTAssertEqual(s.ratioStep, 0.05)
        XCTAssertFalse(s.menubarIcon)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt], key: "1")], .greedyView(0))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt, .shift], key: "9")], .shift(8))
        XCTAssertTrue(s.bar.enabled)
    }

    func testPartialFileKeepsDefaultKeysWithNewMod() throws {
        let s = try Settings.parse("mod: cmd+alt\ngap: 10\n")
        XCTAssertEqual(s.gap, 10)
        XCTAssertEqual(s.keys.count, 39)
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
        XCTAssertEqual(try Settings.parse("").keys.count, 39)
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
        XCTAssertEqual(s.keys.count, 39)
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


final class AmethystKeysTests: XCTestCase {
    /// Your Amethyst config: mod1 = option, mod2 = option+shift.
    func testAmethystBindingsCarriedOver() throws {
        let k = try Settings.parse(Settings.defaultYAML).keys
        let m1: Set<Modifier> = [.alt], m2: Set<Modifier> = [.alt, .shift]
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "space")], .nextLayout)       // cycle-layout
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "h")], .shrink)               // shrink-main
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "l")], .expand)               // expand-main
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "k")], .focusUp)              // focus-ccw
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "j")], .focusDown)            // focus-cw
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "comma")], .focusNextScreen)  // focus-screen-cw
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "period")], .focusPrevScreen)
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "k")], .swapUp)               // swap-ccw
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "j")], .swapDown)             // swap-cw
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "3")], .shift(2))             // throw-space-3
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "left")], .shiftPrev)         // throw-space-left
        XCTAssertEqual(k[KeyChord(modifiers: m2, key: "right")], .shiftNext)        // throw-space-right
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "z")], .refresh)              // reevaluate-windows
        XCTAssertEqual(k[KeyChord(modifiers: m1, key: "p")], .windowSearch)
    }

    /// skhd binds lalt - q / return / f / b; those must stay free.
    func testSkhdKeysStayFree() throws {
        let k = try Settings.parse(Settings.defaultYAML).keys
        for key in ["q", "return", "f", "b"] {
            XCTAssertNil(k[KeyChord(modifiers: [.alt], key: key)], "alt-\(key) is skhd's")
        }
    }

    func testLayoutsSetting() throws {
        XCTAssertEqual(try Settings.parse("layouts: [full, fullscreen, mirror]").layouts, [.full, .full, .mirrorTall])
        XCTAssertThrowsError(try Settings.parse("layouts: [bsp]"))
    }
}

final class LayoutAndSnapshotTests: XCTestCase {
    func testColumnLayout() {
        let r = CGRect(x: 0, y: 0, width: 900, height: 600)
        let rects = Layout.tile(.column, count: 3, in: r, nMaster: 1, ratio: 0.5, gap: 0)
        XCTAssertEqual(rects.map(\.width), [300, 300, 300])
        XCTAssertEqual(rects.map(\.minX), [0, 300, 600])
    }

    func testNextLayoutFollowsOrder() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        let order: [LayoutKind] = [.tall, .full]
        ss.nextLayout(in: order); XCTAssertEqual(ss.current.layout, .full)
        ss.nextLayout(in: order); XCTAssertEqual(ss.current.layout, .tall)
    }

    func testNeighbourWraps() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        XCTAssertEqual(ss.neighbour(-1), 8)
        XCTAssertEqual(ss.neighbourScreen(+1), 1)
        ss.focusScreen(1)
        XCTAssertEqual(ss.neighbourScreen(+1), 0)
    }

    func testSnapshotRoundTripThroughJSON() throws {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        ss.insert(10); ss.insert(11)
        ss.insert(20, into: 4); ss.floating.insert(20)
        ss.greedyView(6)                         // screen 0 shows 7
        ss.nextLayout()
        let data = try JSONEncoder().encode(ss.snapshot)
        let snap = try JSONDecoder().decode(StackSet.Snapshot.self, from: data)

        var fresh = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        fresh.restore(snap, existing: [10, 20, 99])       // 11 closed meanwhile, 99 is new
        XCTAssertEqual(fresh.workspaceIndex(of: 10), 0)
        XCTAssertNil(fresh.workspaceIndex(of: 11))
        XCTAssertEqual(fresh.workspaceIndex(of: 20), 4)
        XCTAssertTrue(fresh.floating.contains(20))
        XCTAssertNil(fresh.workspaceIndex(of: 99))        // caller inserts unknown windows
        XCTAssertEqual(fresh.screenWorkspace, [6, 1])
        XCTAssertEqual(fresh.workspaces[6].layout, .mirrorTall)
    }
}


final class GestureSettingsTests: XCTestCase {
    func testDefaults() throws {
        let g = try Settings.parse(Settings.defaultYAML).gestures
        XCTAssertEqual(g, GestureSettings())
        XCTAssertEqual(g.left, .workspaceNext)
        XCTAssertNil(g.up)
        XCTAssertEqual(try Settings.parse("").gestures, GestureSettings())
    }

    func testCustom() throws {
        let g = try Settings.parse("gestures:\n  fingers: 4\n  skip-empty: false\n  swipe-up: window-search\n  swipe-left: ~\n").gestures
        XCTAssertEqual(g.fingers, 4)
        XCTAssertFalse(g.skipEmpty)
        XCTAssertEqual(g.up, .windowSearch)
        XCTAssertNil(g.left)
        XCTAssertEqual(g.right, .workspacePrev)
        XCTAssertEqual(g.direction, .auto)
        XCTAssertEqual(try Settings.parse("gestures:\n  direction: reversed").gestures.direction, .reversed)
        XCTAssertThrowsError(try Settings.parse("gestures:\n  direction: up"))
    }

    func testBad() {
        XCTAssertThrowsError(try Settings.parse("gestures:\n  fingers: 5"))
        XCTAssertThrowsError(try Settings.parse("gestures:\n  swipe-left: fly"))
        XCTAssertThrowsError(try Settings.parse("gestures:\n  pinch: quit"))
    }
}


final class FloatingAndLoginSettingsTests: XCTestCase {
    func testDefaults() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertTrue(s.floatDialogs)
        XCTAssertEqual(s.floatSmallWindows, 0)
        XCTAssertFalse(s.startAtLogin)
    }

    func testValues() throws {
        XCTAssertEqual(try Settings.parse("float-small-windows: true").floatSmallWindows, 500)
        XCTAssertEqual(try Settings.parse("float-small-windows: 300").floatSmallWindows, 300)
        XCTAssertFalse(try Settings.parse("float-dialogs: false").floatDialogs)
        XCTAssertTrue(try Settings.parse("start-at-login: true").startAtLogin)
        XCTAssertThrowsError(try Settings.parse("start-at-login: soon"))
    }
}
