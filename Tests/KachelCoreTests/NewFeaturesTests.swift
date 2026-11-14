import XCTest
import CoreGraphics
@testable import KachelCore

final class FullscreenToggleTests: XCTestCase {
    func testToggleAndNextLayoutClearsIt() {
        var ss = StackSet(tags: ["1"], screenCount: 1)
        ss.toggleFullscreen()
        XCTAssertEqual(ss.current.effectiveLayout, .full)
        XCTAssertEqual(ss.current.layout, .tall)               // the real layout is kept
        ss.toggleFullscreen()
        XCTAssertEqual(ss.current.effectiveLayout, .tall)
        ss.toggleFullscreen(); ss.nextLayout(in: [.tall, .column])
        XCTAssertFalse(ss.current.fullscreen)
        XCTAssertEqual(ss.current.effectiveLayout, .column)
    }

    func testSurvivesSnapshot() throws {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        ss.insert(1); ss.toggleFullscreen()
        let snap = try JSONDecoder().decode(StackSet.Snapshot.self, from: JSONEncoder().encode(ss.snapshot))
        var fresh = StackSet(tags: ["1", "2"], screenCount: 1)
        fresh.restore(snap, existing: [1])
        XCTAssertTrue(fresh.current.fullscreen)
    }
}

final class NavigationTests: XCTestCase {
    // Two screens side by side: master + 2 stack on the left screen, one window on the right one.
    let master = CGRect(x: 0, y: 0, width: 500, height: 900)
    let top = CGRect(x: 506, y: 0, width: 500, height: 447)
    let bottom = CGRect(x: 506, y: 453, width: 500, height: 447)
    let other = CGRect(x: 1512, y: 0, width: 1000, height: 900)
    var all: [(id: WindowID, frame: CGRect)] { [(1, master), (2, top), (3, bottom), (4, other)] }

    func testNeighbours() {
        XCTAssertEqual(Navigation.neighbour(of: master, in: .right, among: all), 2)   // aligned, nearest
        XCTAssertEqual(Navigation.neighbour(of: top, in: .down, among: all), 3)
        XCTAssertEqual(Navigation.neighbour(of: bottom, in: .up, among: all), 2)
        XCTAssertEqual(Navigation.neighbour(of: top, in: .left, among: all), 1)
        XCTAssertEqual(Navigation.neighbour(of: bottom, in: .right, among: all), 4)   // across screens
        XCTAssertNil(Navigation.neighbour(of: master, in: .left, among: all))
        XCTAssertNil(Navigation.neighbour(of: top, in: .up, among: all))
    }
}

final class ScratchpadAndBorderSettingsTests: XCTestCase {
    func testDefaults() throws {
        let s = try Settings.parse(Settings.defaultYAML)
        XCTAssertEqual(s.scratchpads.map(\.name), ["term"])
        XCTAssertEqual(s.scratchpads[0].title, "scratchpad")
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt], key: "s")], .scratchpad("term"))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt, .shift], key: "f")], .toggleFullscreen)
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt], key: "left")], .focusDirection(.left))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.ctrl, .alt, .shift], key: "down")], .swapDirection(.down))
        XCTAssertEqual(s.keys[KeyChord(modifiers: [.alt], key: "j")], .focusDown)     // next/previous stay
        XCTAssertEqual(s.border, BorderSettings())
    }

    func testCustomScratchpad() throws {
        let s = try Settings.parse("""
        scratchpads:
          - name: music
            app: com.spotify.client
            run: open -a Spotify
            size: [0.5, 0.4]
            position: top
        keys:
          mod-m: scratchpad music
        """)
        XCTAssertEqual(s.scratchpads[0].width, 0.5)
        XCTAssertEqual(s.scratchpads[0].position, .top)
        XCTAssertNil(s.scratchpads[0].title)
    }

    func testErrors() {
        XCTAssertThrowsError(try Settings.parse("keys:\n  mod-x: scratchpad nope"))            // unknown name
        XCTAssertThrowsError(try Settings.parse("scratchpads:\n  - name: a\n    app: X\n    size: [2, 1]"))
        XCTAssertThrowsError(try Settings.parse("scratchpads:\n  - name: a\n    app: X\n  - name: a\n    app: Y"))
        XCTAssertThrowsError(try Settings.parse("border:\n  color: red"))
        XCTAssertNoThrow(try Settings.parse("border:\n  color: \"#5DCAA5\"\n  width: 4"))
        XCTAssertNil(try Settings.parse(Settings.defaultYAML).border.radius)                 // auto
        XCTAssertEqual(try Settings.parse("border:\n  radius: 18").border.radius, 18)
    }
}
