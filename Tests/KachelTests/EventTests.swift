import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// `kachel subscribe`: an event for each change, none when nothing changed.
final class EventTests: WindowManagerTestCase {
    var got: [[String: Any]] = []

    func listen() {
        got = []
        wm.onEvent = { [unowned self] _, line in
            self.got.append(try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any])
        }
    }

    func kinds() -> [String] { got.map { $0["event"] as! String } }

    func testWorkspaceSwitch() throws {
        try start()
        refresh()
        _ = wm.currentEvents()
        listen()
        try run("workspace 3")
        let ws = try XCTUnwrap(got.first { $0["event"] as? String == "workspace" })
        XCTAssertEqual(ws["workspace"] as? String, "3")
        XCTAssertEqual(ws["previous"] as? String, "1")
        XCTAssertEqual(ws["visible"] as? [String], ["3"])
        XCTAssertEqual(kinds().filter { $0 == "workspace" }.count, 1, "once, however often the bar redraws")
        got = []
        try run("workspace 3")
        XCTAssertEqual(kinds(), [], "nothing changed")
    }

    func testWindowsFocusAndLayout() throws {
        try start()
        refresh()
        _ = wm.currentEvents()
        listen()
        let a = sys.open("com.apple.Safari", title: "Start")
        refresh()
        let windows = try XCTUnwrap(got.last { $0["event"] as? String == "windows" })
        XCTAssertEqual(windows["workspace"] as? String, "1")
        XCTAssertEqual(windows["windows"] as? [Int], [Int(a.id)])
        let focus = try XCTUnwrap(got.last { $0["event"] as? String == "focus" })
        let w = try XCTUnwrap(focus["window"] as? [String: Any])
        XCTAssertEqual(w["id"] as? Int, Int(a.id))
        XCTAssertEqual(w["title"] as? String, "Start")
        XCTAssertEqual(w["bundle-id"] as? String, "com.apple.Safari")

        got = []
        a.title = "Docs"
        wm.updateBar()
        XCTAssertEqual(kinds(), ["focus"], "a new title of the focused window")
        XCTAssertEqual((got[0]["window"] as? [String: Any])?["title"] as? String, "Docs")

        got = []
        try run("next-layout")
        let layout = try XCTUnwrap(got.first { $0["event"] as? String == "layout" })
        XCTAssertEqual(layout["workspace"] as? String, "1")
        XCTAssertNotEqual(layout["layout"] as? String, "tall")

        got = []
        try run("shift 2")
        XCTAssertEqual(Set(kinds()), ["windows", "focus"])
        XCTAssertEqual(got.filter { $0["event"] as? String == "windows" }.compactMap { $0["workspace"] as? String }.sorted(),
                       ["1", "2"])
        XCTAssertTrue(got.contains { $0["event"] as? String == "focus" && $0["window"] is NSNull }, "workspace 1 is empty now")
    }

    func testANewSubscriberHearsWhereThingsAre() throws {
        try start(screens: [Self.screen1, Self.screen2])
        let a = sys.open("com.apple.Safari", title: "Start")
        refresh()
        let now = wm.currentEvents()
        XCTAssertEqual(now.map(\.kind), ["workspace", "layout", "focus"])
        let ws = try JSONSerialization.jsonObject(with: Data(now[0].line.utf8)) as! [String: Any]
        XCTAssertEqual(ws["visible"] as? [String], ["1", "2"])
        XCTAssertTrue(ws["previous"] is NSNull)
        XCTAssertTrue(now[2].line.contains("\"id\":\(a.id)"))
    }

    func testDisplaySwap() throws {
        try start(screens: [Self.screen1, Self.screen2])
        refresh()
        _ = wm.currentEvents()
        listen()
        try run("workspace 2")             // shown on the other display: they swap
        let ws = try XCTUnwrap(got.first { $0["event"] as? String == "workspace" })
        XCTAssertEqual(ws["workspace"] as? String, "2")
        XCTAssertEqual(ws["visible"] as? [String], ["2", "1"])
    }
}

/// The bar's clock wakes up once a minute unless it shows seconds.
final class ClockTests: XCTestCase {
    func testShowsSeconds() {
        XCTAssertFalse(Bar.showsSeconds("HH:mm"))
        XCTAssertFalse(Bar.showsSeconds("EEE d MMM"))
        XCTAssertTrue(Bar.showsSeconds("HH:mm:ss"))
        XCTAssertFalse(Bar.showsSeconds("HH:mm 'minutes'"), "quoted text isn't a pattern")
        XCTAssertTrue(Bar.showsSeconds("'at' H:mm:ss"))
    }
}
