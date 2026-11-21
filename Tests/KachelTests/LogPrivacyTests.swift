import AppKit
import XCTest
@testable import Kachel
@testable import KachelCore

/// The log goes into bug reports: no window titles, no user name.
final class LogPrivacyTests: WindowManagerTestCase {
    private var lines: [String] = []

    override func tearDown() {
        Log.sink = nil
        super.tearDown()
    }

    private func capture() { Log.sink = { [unowned self] in self.lines.append($0) } }

    func testWindowTitlesNeverReachTheLog() throws {
        try start(displays: [Self.laptop, Self.dell])
        capture()
        let secret = "Q3 salary review – Anna.xlsx"
        let w = sys.open("com.microsoft.Excel", title: secret)
        let other = sys.open("com.apple.mail", title: "Re: Anna's contract", pid: 1001)
        refresh()
        wm.dumpState()                                   // kachel dump
        sys.axHidden.insert(w.id)                        // lost by Accessibility
        refresh()
        sys.axHidden.remove(w.id)                        // back
        refresh()
        try run("shift 4")
        sys.close(other.id)
        refresh()
        connect([Self.laptop])                            // display unplugged

        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertFalse(line.contains("salary") || line.contains("Anna") || line.contains("contract"), line)
        }
        XCTAssertTrue(lines.contains { $0.contains("title #") && $0.contains("(28 chars)") }, "a tag instead")
    }

    func testSameTitleSameTag() {
        XCTAssertEqual(Log.title("Budget 2027"), Log.title("Budget 2027"))
        XCTAssertNotEqual(Log.title("Budget 2027"), Log.title("Budget 2028"))
        XCTAssertEqual(Log.title(""), "no title")
        XCTAssertFalse(Log.title("Budget 2027").contains("Budget"))
    }

    func testHomeFolderBecomesTilde() {
        capture()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        Log.info("loaded \(home)/.config/kachel/config.yaml")
        XCTAssertEqual(lines, ["loaded ~/.config/kachel/config.yaml"])
        XCTAssertFalse(lines[0].contains(NSUserName()))
    }

    /// What the log now says, so a bug can be rebuilt from it.
    func testLogDescribesWindowsAndDisplays() throws {
        capture()
        try start(displays: [Self.laptop, Self.dell])
        let w = sys.open("com.apple.Safari", frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        w.hasFullscreenButton = false
        refresh()
        XCTAssertTrue(lines.contains { $0.hasPrefix("displays: Built-in Retina Display 1512×982 at (0, 0), built-in, main; DELL U2720Q 2560×1440 at (1512, 0)") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("new window \(w.id)") && $0.contains("600×400 at (100, 100)") && $0.contains("floats (no fullscreen button") }, "\(lines)")
        connect([Self.laptop])
        XCTAssertTrue(lines.contains { $0.hasPrefix("displays changed: Built-in Retina Display") }, "\(lines)")
    }
}
