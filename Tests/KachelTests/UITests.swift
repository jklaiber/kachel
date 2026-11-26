import AppKit
import SwiftUI
import XCTest
@testable import Kachel
@testable import KachelCore

/// Kachel's own UI: the bar, panels, Settings and alerts, drawn with made-up
/// content and compared with reference images (see Snapshot.swift). Plus
/// checks that hold on every macOS version, for bugs that happened before.
@MainActor
final class UITests: XCTestCase {
    override func setUp() async throws {
        Log.enabled = false
        _ = NSApplication.shared
        Config.use(Settings.defaults)
        AppVersion.override = "0.1.20"
    }

    override func tearDown() async throws {
        AppVersion.override = nil
    }

    /// A Settings page as the window shows it: grouped form on the window background.
    private func page<V: View>(_ v: V) -> some View {
        v.formStyle(.grouped).background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - the bar

    /// The bar is transparent: in front of the same wallpaper as the doc images.
    private func bar(_ settings: BarSettings, content: Bar.Content = Screenshots.demoContent(),
                     battery: Battery.State? = Battery.State(percent: 82, charging: false, onPower: false),
                     width: CGFloat = 1200) -> NSView {
        let v = Bar.demoView(width: width, height: 30, settings: settings, content: content, now: Screenshots.demoNow,
                             cpu: 0.12, memory: 9_100_000_000, down: 1_200_000, up: 40_000, battery: battery)
        let back = Wallpaper(frame: v.frame)
        back.addSubview(v)
        return back
    }



    func testBar() throws {
        var s = BarSettings()
        s.right = [.network, .cpu, .memory, .battery, .date, .clock]
        try Snapshot.check(Snapshot.image(of: bar(s)), "bar")
    }

    func testBarLightTextAndCounts() throws {
        var s = BarSettings()
        s.appearance = .light
        s.workspaceCounts = true
        var c = Screenshots.demoContent()
        for i in c.tags.indices where c.tags[i].hasWindows { c.tags[i].count = i + 1 }
        try Snapshot.check(Snapshot.image(of: bar(s, content: c), appearance: NSAppearance(named: .aqua)), "bar-light-counts")
    }

    func testBarTabsInFullLayout() throws {
        var s = BarSettings()
        s.windows = .tabs
        var c = Screenshots.demoContent()
        c.layout = "Full"
        c.isFullLayout = true
        c.windows = [.init(id: 1, title: "kachel — zsh", focused: true), .init(id: 2, title: "Notes"),
                     .init(id: 3, title: "Kachel — a tiling window manager")]
        try Snapshot.check(Snapshot.image(of: bar(s, content: c)), "bar-tabs")
    }

    /// Charging, and a Mac without a battery: no empty gap where it would be.
    func testBarBatteryStates() throws {
        var s = BarSettings()
        s.right = [.battery, .clock]
        try Snapshot.check(Snapshot.image(of: bar(s, battery: .init(percent: 40, charging: true, onPower: true), width: 600)),
                           "bar-battery-charging")
        try Snapshot.check(Snapshot.image(of: bar(s, battery: nil, width: 600)), "bar-no-battery")
    }

    // MARK: - scenes of the docs

    func testDesktop() throws {
        try Snapshot.check(Snapshot.image(size: NSSize(width: 1200, height: 750), Screenshots.drawDesktop), "desktop")
    }

    func testWindowSearch() throws {
        try Snapshot.check(Snapshot.image(size: NSSize(width: 720, height: 520)) { Screenshots.drawSearch(query: "") },
                           "window-search")
        try Snapshot.check(Snapshot.image(size: NSSize(width: 720, height: 300)) { Screenshots.drawSearch(query: "term") },
                           "window-search-query")
    }

    func testRulePicker() throws {
        try Snapshot.check(Snapshot.image(size: NSSize(width: 720, height: 230), Screenshots.drawRulePicker), "app-rule")
    }

    // MARK: - SwiftUI windows

    func testWelcomeWindow() throws {
        RowBackground.plain = true
        // Kachel's icon from the repository (the test runner has none of its own).
        let iconURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../docs/images/icon.svg").standardized
        let icon = try XCTUnwrap(NSImage(contentsOf: iconURL))
        let view = WelcomeView(model: .demo(), close: {}, icon: icon, rendering: true)
        try Snapshot.check(Snapshot.image(of: page(view), size: CGSize(width: 640, height: 900)), "welcome")
    }

    func testSettingsPanes() throws {
        let m = SettingsModel()
        let size = CGSize(width: 620, height: 1100)
        try Snapshot.check(Snapshot.image(of: page(GeneralPane(m: m)), size: size), "settings-general")
        try Snapshot.check(Snapshot.image(of: page(BarPane(m: m)), size: size), "settings-bar")
        try Snapshot.check(Snapshot.image(of: page(BorderPane(m: m)), size: CGSize(width: 620, height: 500)), "settings-border")
        try Snapshot.check(Snapshot.image(of: page(RulesPane(m: m)), size: CGSize(width: 620, height: 700)), "settings-rules")
    }

    func testAboutPane() throws {
        let iconURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../docs/images/icon.svg").standardized
        let icon = try XCTUnwrap(NSImage(contentsOf: iconURL))
        try Snapshot.check(Snapshot.image(of: page(AboutPane(m: SettingsModel(), icon: icon)), size: CGSize(width: 620, height: 820)),
                           "settings-about")
    }

    /// Warnings about ignored settings show at the top of Settings. (The
    /// sidebar is a material, which comes out blank in the picture.)
    func testSettingsShowsConfigWarnings() throws {
        Config.use(try Settings.parse("gapp: 3\n"))
        let m = SettingsModel()
        XCTAssertEqual(m.s.warnings, ["unknown setting 'gapp' ignored (did you mean 'gap'?)"])
        try Snapshot.check(Snapshot.image(of: page(SettingsView(model: m)), size: CGSize(width: 900, height: 400)),
                           "settings-warning")
    }

    // MARK: - the crash alert

    private let report = CrashReport(appVersion: "0.1.20", osVersion: "26.5", exception: "EXC_BAD_ACCESS (SIGSEGV)",
                                     frames: [], kachelSymbol: "Battery.init()")

    /// It once showed with its text cut off after "Kachel" and a stray
    /// "Do not show this message again" box (shown without being laid out).
    func testCrashAlertIsLaidOut() throws {
        let a = CrashPrompt.makeAlert(report, restarted: true)
        let content = try XCTUnwrap(a.window.contentView)
        let texts = Self.all(NSTextField.self, in: content).filter { !$0.isHidden }
        let info = try XCTUnwrap(texts.first { $0.stringValue.contains("Reporting it helps fix it") })
        XCTAssertGreaterThanOrEqual(info.frame.height + 1, info.fittingSize.height, "the text isn't cut off")
        let buttons = Self.all(NSButton.self, in: content).filter { !$0.isHidden && $0.window != nil }
        XCTAssertEqual(buttons.filter { $0.bezelStyle != .helpButton && !$0.title.isEmpty }.map(\.title).sorted(),
                       ["Not Now", "Report on GitHub…", "Show Crash Report"])
        XCTAssertFalse(buttons.contains { $0.title.contains("Do not show") }, "no suppression box")
        XCTAssertFalse(buttons.contains { $0.bezelStyle == .helpButton }, "no help button")
        // No picture: an alert draws through layers and materials, which an
        // offscreen capture leaves out. The checks above are what matters.
    }

    private static func all<T: NSView>(_ type: T.Type, in v: NSView) -> [T] {
        ((v as? T).map { [$0] } ?? []) + v.subviews.flatMap { all(type, in: $0) }
    }
}

/// Draws the docs' wallpaper itself (a layer's background wouldn't be in the picture).
final class Wallpaper: NSView {
    override func draw(_ dirtyRect: NSRect) { Screenshots.wallpaper(bounds) }
}

/// Issue #14: badges and your own widgets.
@MainActor
final class BarWidgetTests: XCTestCase {
    private let slack = DockBadges.Badge(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", label: "3", appURL: nil)
    private let outlook = DockBadges.Badge(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", label: "12", appURL: nil)
    // For the picture: apps every Mac has, so their icons are drawn.
    private let mail = DockBadges.Badge(bundleID: "com.apple.mail", name: "Mail", label: "12",
                                        appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))
    private let messages = DockBadges.Badge(bundleID: "com.apple.MobileSMS", name: "Messages", label: "3",
                                            appURL: URL(fileURLWithPath: "/System/Applications/Messages.app"))

    func testPickBadges() {
        XCTAssertEqual(DockBadges.pick([slack, outlook], apps: []), [slack, outlook], "all of them")
        XCTAssertEqual(DockBadges.pick([slack, outlook], apps: ["microsoft outlook", "com.tinyspeck.slackmacgap"]),
                       [outlook, slack], "by name or bundle ID, in the order asked")
        XCTAssertEqual(DockBadges.pick([slack], apps: ["Mail"]), [], "Mail has none now")
    }

    func testFirstLine() {
        XCTAssertEqual(CustomWidgetRunner.firstLine(of: "printf 'Connected\\nmore\\n'"), "Connected")
        XCTAssertNil(CustomWidgetRunner.firstLine(of: "true"), "nothing printed: nothing shown")
        let long = CustomWidgetRunner.firstLine(of: "printf '%060d' 0")
        XCTAssertEqual(long?.count, CustomWidgetRunner.maxLength)
        XCTAssertTrue(long?.hasSuffix("…") == true)
    }

    /// A hanging command is stopped after the timeout instead of blocking.
    func testSlowCommandIsStopped() {
        Log.enabled = false
        let start = Date()
        XCTAssertNil(CustomWidgetRunner.firstLine(of: "sleep 10; echo late"))
        XCTAssertLessThan(Date().timeIntervalSince(start), CustomWidgetRunner.timeout + 1)
    }

    /// Settings → Bar with two widgets of yours: one in the bar, one not.
    func testSettingsYourWidgets() throws {
        _ = NSApplication.shared
        AppVersion.override = "0.1.21"
        Config.use(try Settings.parse("""
        bar:
          right: [vpn, clock]
          widgets:
            vpn: {run: "scutil --nc status 'Work VPN' | head -1", interval: 10, icon: lock.fill}
            weather: {run: "curl -s wttr.in/?format=3", interval: 600, icon: cloud.sun}
        """))
        let m = SettingsModel()
        let view = BarPane(m: m).formStyle(.grouped).background(Color(nsColor: .windowBackgroundColor))
        try Snapshot.check(Snapshot.image(of: view, size: CGSize(width: 620, height: 1700)), "settings-your-widgets")
    }

    func testBarWithBadgesAndAWidget() throws {
        _ = NSApplication.shared
        var s = BarSettings()
        s.right = [.badges, BarWidget(rawValue: "vpn")!, .clock]
        s.custom = ["vpn": { var w = CustomWidget(run: "true"); w.icon = "lock.fill"; return w }()]
        let v = Bar.demoView(width: 700, height: 30, settings: s, content: Screenshots.demoContent(), now: Screenshots.demoNow,
                             cpu: 0, memory: 0, down: 0, up: 0, badges: [messages, mail], custom: ["vpn": "Work VPN"])
        let back = Wallpaper(frame: v.frame)
        back.addSubview(v)
        try Snapshot.check(Snapshot.image(of: back), "bar-badges-widget")
    }
}
