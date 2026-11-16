import AppKit

/// Kachel's version, from the app bundle (set by scripts/bundle.sh; releases
/// use the tag). A plain `swift build` binary has none and says "dev".
enum AppVersion {
    static var string: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The standard macOS About window: icon, name, version, licence and links.
    static func showAbout() {
        let credits = NSMutableAttributedString(
            string: "A tiling window manager with xmonad's workspace model.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        for (title, url) in [("Documentation", "https://jklaiber.github.io/kachel/"),
                             ("Changelog", "https://github.com/jklaiber/kachel/blob/main/CHANGELOG.md"),
                             ("GitHub", "https://github.com/jklaiber/kachel")] {
            if credits.length > 0, !credits.string.hasSuffix("\n") { credits.append(NSAttributedString(string: " · ")) }
            credits.append(NSAttributedString(string: title, attributes: [.link: URL(string: url)!, .font: NSFont.systemFont(ofSize: 11)]))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "Version \(string)",
            .version: "",                                   // no build number in brackets
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Julian Klaiber · MIT licence",
        ])
    }
}
