import AppKit
import KachelCore
import SwiftUI

/// `Kachel --render-screenshots <dir>`: draws the README images with Kachel's
/// real views and made-up content (no real windows, titles or wallpaper), so
/// they're reproducible and contain nothing private.
enum Screenshots {
    static let scale: CGFloat = 2
    static let dark = NSAppearance(named: .darkAqua)!
    static let orange = NSColor(srgbRed: 0xE8 / 255, green: 0x96 / 255, blue: 0x5A / 255, alpha: 1)
    static let demoNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 14; c.hour = 9; c.minute = 41
        return Calendar.current.date(from: c) ?? Date()
    }()

    static func render(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = dark
        let files: [(String, NSSize, () -> Void)] = [
            ("desktop.png", NSSize(width: 1200, height: 750), drawDesktop),
            ("bar.png", NSSize(width: 1200, height: 64), drawBarCloseUp),
            ("window-search.png", NSSize(width: 720, height: 520), { drawSearch(query: "") }),
            ("window-search-query.png", NSSize(width: 720, height: 300), { drawSearch(query: "term") }),
            ("app-rule.png", NSSize(width: 720, height: 230), drawRulePicker),
        ]
        try MainActor.assumeIsolated { try renderWelcome(to: dir.appendingPathComponent("welcome.png")) }
        for (name, size, draw) in files {
            let data = png(size) { dark.performAsCurrentDrawingAppearance(draw) }
            try data.write(to: dir.appendingPathComponent(name))
            print("wrote \(dir.appendingPathComponent(name).path)")
        }
    }

    /// The welcome window, rendered by SwiftUI itself.
    @MainActor static func renderWelcome(to url: URL) throws {
        RowBackground.plain = true
        let icon = NSImage(contentsOf: URL(fileURLWithPath: "docs/images/icon.svg")) ?? NSApp.applicationIconImage!
        let view = WelcomeView(model: .demo(), close: {}, icon: icon, rendering: true)
            .background(Color(nsColor: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1)))
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
        print("wrote \(url.path)")
    }

    // MARK: - scenes

    /// The whole screen: menu bar, three tiled windows, focus border, Kachel's bar.
    static func drawDesktop() {
        let size = NSSize(width: 1200, height: 750)
        wallpaper(NSRect(origin: .zero, size: size))
        menuBar(width: size.width, top: size.height)
        let gap: CGFloat = 8, barH: CGFloat = 30, menuH: CGFloat = 24
        let area = NSRect(x: gap, y: barH + gap, width: size.width - 2 * gap, height: size.height - barH - menuH - 2 * gap)
        let masterW = (area.width - gap) * 0.55
        let master = NSRect(x: area.minX, y: area.minY, width: masterW, height: area.height)
        let stackX = master.maxX + gap, stackW = area.maxX - stackX
        let half = (area.height - gap) / 2
        let top = NSRect(x: stackX, y: area.minY + half + gap, width: stackW, height: half)
        let bottom = NSRect(x: stackX, y: area.minY, width: stackW, height: half)

        window(master, title: "kachel — zsh", kind: .terminal([
            ("~/kachel", "swift test"),
            ("", "Executed 79 tests, with 0 failures (0 unexpected)"),
            ("~/kachel", "./scripts/bundle.sh && open build/Kachel.app"),
            ("", "Built build/Kachel.app"),
            ("~/kachel", "kachel-ctl \"workspace 2\""),
            ("~/kachel", ""),
        ]))
        window(top, title: "Kachel — a tiling window manager", kind: .browser)
        window(bottom, title: "Notes", kind: .notes)
        focusBorder(around: master)
        bar(width: size.width, height: barH, at: .zero, content: demoContent(), right: [.network, .cpu, .memory, .date, .clock])
    }

    /// The bar on its own, a little wallpaper above it.
    static func drawBarCloseUp() {
        wallpaper(NSRect(x: 0, y: 0, width: 1200, height: 64), offset: CGPoint(x: 0, y: -600))
        bar(width: 1200, height: 34, at: .zero, content: demoContent(), right: [.network, .cpu, .memory, .date, .clock],
            fontSize: 14)
    }

    /// Window search rising from the bar.
    static func drawSearch(query: String) {
        let size = query.isEmpty ? NSSize(width: 720, height: 520) : NSSize(width: 720, height: 300)
        wallpaper(NSRect(origin: .zero, size: size), offset: CGPoint(x: -200, y: -160))
        let barH: CGFloat = 30
        bar(width: size.width, height: barH, at: .zero, content: demoContent(), right: [.clock])

        let icon = { (s: String, c: NSColor) in appIcon(s, c) }
        let entries: [WindowSwitcher.Entry] = [
            .init(id: 1, app: "Terminal", title: "kachel — zsh", icon: icon("terminal", .darkGray),
                  workspace: 0, tag: "1", visible: true, active: true, recency: 0, focused: true),
            .init(id: 2, app: "Safari", title: "Kachel — a tiling window manager", icon: icon("safari", .systemBlue),
                  workspace: 0, tag: "1", visible: true, active: true, recency: 2, focused: false),
            .init(id: 3, app: "Notes", title: "Ideas for the weekend", icon: icon("note.text", .systemYellow),
                  workspace: 0, tag: "1", visible: true, active: true, recency: 4, focused: false),
            .init(id: 4, app: "Mail", title: "Inbox — 3 unread", icon: icon("envelope.fill", .systemBlue),
                  workspace: 1, tag: "2", visible: true, active: false, recency: 1, focused: false),
            .init(id: 5, app: "Terminal", title: "server — ssh", icon: icon("terminal", .darkGray),
                  workspace: 2, tag: "3", visible: false, active: false, recency: 3, focused: false),
            .init(id: 6, app: "Music", title: "Now Playing", icon: icon("music.note", .systemPink),
                  workspace: 4, tag: "5", visible: false, active: false, recency: 5, focused: false),
        ]
        let switcher = WindowSwitcher()
        let v = switcher.demoView(entries, query: query, width: 560)
        v.appearance = dark
        let origin = NSPoint(x: 8, y: barH + 6)
        panelBackground(NSRect(origin: origin, size: v.bounds.size))
        place(v, at: origin, skipping: NSVisualEffectView.self)
    }

    /// "Always open … on" for an app.
    static func drawRulePicker() {
        let size = NSSize(width: 720, height: 230)
        wallpaper(NSRect(origin: .zero, size: size), offset: CGPoint(x: -400, y: -300))
        let barH: CGFloat = 30
        bar(width: size.width, height: barH, at: .zero, content: demoContent(), right: [.clock])
        let v = RulePicker.demoView(app: "Music", icon: appIcon("music.note", .systemPink),
                                    tags: (1...9).map(String.init), current: 8, floats: false)
        v.appearance = dark
        let origin = NSPoint(x: 8, y: barH + 6)
        panelBackground(NSRect(origin: origin, size: v.bounds.size))
        place(v, at: origin)
    }

    // MARK: - Kachel's real views

    static func demoContent() -> Bar.Content {
        var c = Bar.Content()
        c.tags = (1...9).map { i in
            Bar.Tag(name: "\(i)", active: i == 1, visible: i == 1 || i == 2, hasWindows: [1, 2, 3, 5].contains(i))
        }
        c.layout = "Tall"
        c.title = "kachel — zsh"
        c.isCurrentScreen = true
        return c
    }

    static func bar(width: CGFloat, height: CGFloat, at origin: NSPoint, content: Bar.Content,
                    right: [BarWidget], fontSize: Double = 13) {
        var s = BarSettings()
        s.height = Double(height)
        s.fontSize = fontSize
        s.right = right
        let v = Bar.demoView(width: width, height: height, settings: s, content: content, now: demoNow,
                             cpu: 0.12, memory: 10_100_000_000, down: 1_240_000, up: 84_000)
        v.appearance = dark
        place(v, at: origin)
    }

    static func focusBorder(around r: NSRect) {
        let w: CGFloat = 3
        let path = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
        path.lineWidth = w
        orange.setStroke()
        path.stroke()
    }

    // MARK: - scenery (not Kachel)

    /// Our own wallpaper: a dusk gradient with soft light.
    static func wallpaper(_ rect: NSRect, offset: CGPoint = .zero) {
        let full = NSRect(x: offset.x, y: offset.y, width: 1200, height: 750)
        NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.12, blue: 0.24, alpha: 1),
                            NSColor(srgbRed: 0.13, green: 0.33, blue: 0.40, alpha: 1),
                            NSColor(srgbRed: 0.72, green: 0.42, blue: 0.30, alpha: 1)])!
            .draw(in: full, angle: 35)
        for (c, x, y, r) in [(NSColor(srgbRed: 0.95, green: 0.62, blue: 0.40, alpha: 0.25), 950.0, 120.0, 420.0),
                             (NSColor(srgbRed: 0.30, green: 0.70, blue: 0.75, alpha: 0.18), 220.0, 560.0, 380.0)] {
            let center = NSPoint(x: full.minX + x, y: full.minY + y)
            NSGradient(starting: c, ending: c.withAlphaComponent(0))!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: r, options: [])
        }
        _ = rect
    }

    static func menuBar(width: CGFloat, top: CGFloat) {
        let h: CGFloat = 24
        let font = NSFont.menuBarFont(ofSize: 13)
        let bold = NSFont.systemFont(ofSize: 13, weight: .semibold)
        var x: CGFloat = 16
        let y = top - h + (h - 16) / 2
        if let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium).applying(.init(paletteColors: [.white]))) {
            apple.draw(in: NSRect(x: x, y: y, width: apple.size.width, height: apple.size.height))
            x += apple.size.width + 18
        }
        for (i, item) in ["Terminal", "Shell", "Edit", "View", "Window", "Help"].enumerated() {
            let a: [NSAttributedString.Key: Any] = [.font: i == 0 ? bold : font, .foregroundColor: NSColor.white]
            (item as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: a)
            x += (item as NSString).size(withAttributes: a).width + 18
        }
        let clock = "Sat 14 Nov  09:41"
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        (clock as NSString).draw(at: NSPoint(x: width - 16 - (clock as NSString).size(withAttributes: a).width, y: y),
                                 withAttributes: a)
    }

    enum WindowKind { case terminal([(String, String)]), browser, notes }

    /// A plain dark window with traffic lights and some content.
    static func window(_ r: NSRect, title: String, kind: WindowKind) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        let body = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
        NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        body.setClip()
        let titleH: CGFloat = 30
        NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1).setFill()
        NSRect(x: r.minX, y: r.maxY - titleH, width: r.width, height: titleH).fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + 14 + CGFloat(i) * 20, y: r.maxY - titleH / 2 - 6, width: 12, height: 12)).fill()
        }
        let ta: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                 .foregroundColor: NSColor.secondaryLabelColor]
        let tw = (title as NSString).size(withAttributes: ta).width
        (title as NSString).draw(at: NSPoint(x: r.midX - tw / 2, y: r.maxY - titleH / 2 - 8), withAttributes: ta)

        let content = NSRect(x: r.minX + 18, y: r.minY + 16, width: r.width - 36, height: r.height - titleH - 30)
        switch kind {
        case .terminal(let lines):
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            var y = content.maxY - 18
            var lastWidth: CGFloat = 0
            for (dir, cmd) in lines {
                var s = NSMutableAttributedString()
                if !dir.isEmpty {
                    s = NSMutableAttributedString(string: dir + " ", attributes: [.font: mono, .foregroundColor: NSColor.systemTeal])
                    s.append(NSAttributedString(string: "❯ ", attributes: [.font: mono, .foregroundColor: orange]))
                    s.append(NSAttributedString(string: cmd, attributes: [.font: mono, .foregroundColor: NSColor.white]))
                } else {
                    s = NSMutableAttributedString(string: cmd, attributes: [.font: mono, .foregroundColor: NSColor.secondaryLabelColor])
                }
                s.draw(at: NSPoint(x: content.minX, y: y))
                lastWidth = s.size().width
                y -= 24
            }
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSRect(x: content.minX + lastWidth + 1, y: y + 24 + 1, width: 8, height: 15).fill()   // cursor after the last prompt
        case .browser:
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: NSRect(x: content.minX + 60, y: content.maxY - 8, width: content.width - 120, height: 22),
                         xRadius: 11, yRadius: 11).fill()
            let h: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.white]
            ("Kachel" as NSString).draw(at: NSPoint(x: content.minX, y: content.maxY - 60), withAttributes: h)
            bars(in: NSRect(x: content.minX, y: content.minY, width: content.width, height: content.height - 80), count: 7)
        case .notes:
            let h: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white]
            ("Ideas" as NSString).draw(at: NSPoint(x: content.minX, y: content.maxY - 26), withAttributes: h)
            bars(in: NSRect(x: content.minX, y: content.minY, width: content.width, height: content.height - 40), count: 6)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Text placeholder lines.
    static func bars(in r: NSRect, count: Int) {
        NSColor.white.withAlphaComponent(0.12).setFill()
        let widths: [CGFloat] = [0.92, 0.78, 0.86, 0.6, 0.9, 0.7, 0.82]
        for i in 0..<count {
            let y = r.maxY - CGFloat(i + 1) * 24
            guard y > r.minY else { break }
            NSBezierPath(roundedRect: NSRect(x: r.minX, y: y, width: r.width * widths[i % widths.count], height: 9),
                         xRadius: 4.5, yRadius: 4.5).fill()
        }
    }

    /// The popover material, painted (offscreen views can't blur what's behind them).
    static func panelBackground(_ r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        let p = NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18)   // like the glass panels
        NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.94).setFill()
        p.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        p.lineWidth = 0.5
        p.stroke()
    }

    static func appIcon(_ symbol: String, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            NSGradient(starting: color.blended(withFraction: 0.25, of: .white) ?? color, ending: color)!
                .draw(in: NSBezierPath(roundedRect: r.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14), angle: -90)
            let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                s.draw(in: NSRect(x: r.midX - s.size.width / 2, y: r.midY - s.size.height / 2,
                                  width: s.size.width, height: s.size.height))
            }
            return true
        }
    }

    // MARK: - drawing plumbing

    static func png(_ size: NSSize, _ draw: () -> Void) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// Draw a view with its own draw(_:) at `origin` (flipped views too),
    /// then its subviews. Offscreen views have no window, so AppKit's own
    /// display path renders them wrong; calling draw directly doesn't.
    static func place(_ view: NSView, at origin: NSPoint, skipping: NSView.Type? = nil) {
        guard let outer = NSGraphicsContext.current else { return }
        let cg = outer.cgContext
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.clip(to: CGRect(origin: .zero, size: view.bounds.size))
        if skipping == nil || type(of: view) != skipping! {
            drawOwn(view, in: cg)
        }
        for sub in view.subviews where !sub.isHidden {
            cg.saveGState()
            cg.translateBy(x: sub.frame.minX, y: sub.frame.minY)
            switch sub {
            case let field as NSTextField: drawText(field)
            case let image as NSImageView: drawImage(image)
            default: drawOwn(sub, in: cg)
            }
            cg.restoreGState()
        }
        cg.restoreGState()
    }

    private static func drawOwn(_ view: NSView, in cg: CGContext) {
        cg.saveGState()
        if view.isFlipped {
            cg.translateBy(x: 0, y: view.bounds.height)
            cg.scaleBy(x: 1, y: -1)
        }
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: view.isFlipped)
        view.appearance = dark
        view.draw(view.bounds)
        NSGraphicsContext.current = saved
        cg.restoreGState()
    }

    /// Text fields (the search field, the key hint), drawn in their own style.
    private static func drawText(_ f: NSTextField) {
        let empty = f.stringValue.isEmpty
        let text = empty ? (f.placeholderString ?? "") : f.stringValue
        let color: NSColor = empty ? .tertiaryLabelColor : (f.textColor ?? .labelColor)
        let font = f.font ?? .systemFont(ofSize: 13)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let h = (text as NSString).size(withAttributes: a).height
        (text as NSString).draw(at: NSPoint(x: 2, y: (f.bounds.height - h) / 2), withAttributes: a)
        if !empty && font.pointSize > 14 {      // a caret after the query
            let w = (text as NSString).size(withAttributes: a).width
            NSColor.controlAccentColor.setFill()
            NSRect(x: 4 + w, y: (f.bounds.height - h) / 2 + 2, width: 2, height: h - 4).fill()
        }
    }

    private static func drawImage(_ v: NSImageView) {
        guard let img = v.image else { return }
        let tinted = img.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [v.contentTintColor ?? .secondaryLabelColor]))) ?? img
        tinted.draw(in: NSRect(x: (v.bounds.width - tinted.size.width) / 2, y: (v.bounds.height - tinted.size.height) / 2,
                               width: tinted.size.width, height: tinted.size.height))
    }
}
