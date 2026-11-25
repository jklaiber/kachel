import AppKit
import KachelCore

/// A second menu bar along the bottom of every screen, just above the Dock.
/// Same height, font and translucency as the real one at the top.
///
///   1  2  3  5   Tall   Safari — Apple           ↓1.2 MB/s ↑40 KB/s  ▣ 12%  ▤ 9.1 GB  Sat 14 Nov  16:43
///
/// Which widgets appear, and in what order, comes from `bar.left` / `bar.right`.
/// Click a workspace to show it on that screen; right-click for the menu.
final class Bar {
    /// The three things you want to know about a workspace, independently.
    struct Tag {
        var name: String
        var active = false        // the workspace you're in (focused screen)
        var visible = false       // shown on some screen
        var hasWindows = false
        var count = 0
    }

    /// A window of the workspace on this screen, for the position, dots and tabs.
    struct Window {
        var id: UInt32
        var title: String
        var focused = false
    }

    struct Content {
        var tags: [Tag] = []
        var layout = ""
        var title = ""
        var isCurrentScreen = false
        var windows: [Window] = []
        var isFullLayout = false
    }

    var onClickWorkspace: ((_ screen: Int, _ workspace: Int) -> Void)?
    var onClickWindow: ((_ screen: Int, _ window: UInt32) -> Void)?
    var onToggleWidget: ((BarWidget) -> Void)?
    var onToggleMenuBarIcon: (() -> Void)?
    var menuBarIconShown = false
    var menuActions: [(title: String, action: () -> Void)] = []

    let stats = Stats()
    let battery: Battery
    /// Dock badges, read every few seconds while the badges widget is shown.
    var badges: [DockBadges.Badge] = []
    private var badgeTimer: Timer?
    private var appIcons: [String: NSImage] = [:]
    /// Your own widgets (bar.widgets).
    let custom = CustomWidgetRunner()
    /// Screenshots use a fixed time; nil = now.
    var fixedNow: Date?
    private var panels: [BarPanel] = []
    private var screens: [Screen] = []
    private var appearanceTimer: Timer?
    private var clockTimer: Timer?
    private var statsTimer: Timer?
    private(set) var settings = BarSettings()
    private var dock: DockWatch?

    /// - demo: a sample bar (settings preview, screenshots). It's redrawn and
    ///   thrown away all the time, so it watches nothing: no battery, timers or
    ///   notifications that would outlive it.
    private let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        battery = Battery(watch: !demo)
        if demo { return }
        battery.onChange = { [weak self] in self?.redraw() }
        custom.onChange = { [weak self] in self?.redraw() }
        // Follow wallpaper, Space and light/dark changes, like the menu bar does.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.desktop"), object: "BackgroundChanged",
                                                            queue: .main) { [weak self] _ in self?.updateAppearance() }
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in self?.updateAppearance() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.updateAppearance() }
        // Dynamic wallpapers change over the day.
        appearanceTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.updateAppearance()
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.settings.shows(.clock) || self.settings.shows(.date) else { return }
            self.redraw()
        }
    }

    /// The bar's height: the configured one, or the top menu bar's.
    static func height(for s: BarSettings) -> CGFloat {
        if let h = s.height { return CGFloat(h) }
        if let p = NSScreen.screens.first {
            let menu = p.frame.maxY - p.visibleFrame.maxY      // 0 when the menu bar auto-hides
            if menu >= 20 { return menu }
        }
        return NSStatusBar.system.thickness
    }

    /// Create / move one panel per screen.
    func place(on screens: [Screen], settings: BarSettings) {
        self.settings = settings
        guard settings.enabled else {
            panels.forEach { $0.orderOut(nil) }
            panels.removeAll()
            statsTimer?.invalidate()
            dock = nil
            return
        }
        if settings.makeWayForDock, !isDemo {
            if dock == nil {
                let d = DockWatch()
                d.onChange = { [weak self] r in self?.makeWay(for: r) }
                d.start()
                dock = d
            }
        } else {
            dock = nil
        }
        while panels.count > screens.count { panels.removeLast().orderOut(nil) }
        while panels.count < screens.count { panels.append(BarPanel(bar: self, index: panels.count)) }
        let h = Bar.height(for: settings)
        self.screens = screens
        for (p, s) in zip(panels, screens) {
            let v = s.nsVisible
            p.setFrame(NSRect(x: v.minX, y: v.minY, width: v.width, height: h), display: true)
            p.setBackground(settings.background)
            p.orderFrontRegardless()
        }
        makeWay(for: dock?.shownOn)
        updateAppearance()

        // Dock badges and your widgets: only while they're in the bar.
        badgeTimer?.invalidate()
        badgeTimer = nil
        if settings.shows(.badges), !isDemo {
            readBadges()
            badgeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.readBadges() }
        }
        if !isDemo { custom.apply(settings.custom, shown: Set((settings.left + settings.right).map(\.rawValue))) }

        statsTimer?.invalidate()
        let needStats = settings.shows(.cpu) || settings.shows(.memory) || settings.shows(.network)
        if needStats {
            sampleStats()
            statsTimer = Timer.scheduledTimer(withTimeInterval: settings.interval, repeats: true) { [weak self] _ in
                self?.sampleStats()
                self?.redraw()
            }
        }
        redraw()
    }

    private func readBadges() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = DockBadges.read()
            DispatchQueue.main.async {
                guard let self, found != self.badges else { return }
                self.badges = found
                self.redraw()
            }
        }
    }

    /// An app's icon for the badges widget (cached).
    func appIcon(_ b: DockBadges.Badge) -> NSImage? {
        guard let url = b.appURL else { return nil }
        if let i = appIcons[url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[url.path] = i
        return i
    }

    /// Fade out the bar on the screen the Dock slid up on, back in once it's gone.
    private func makeWay(for dockScreen: CGRect?) {
        for p in panels {
            let away = dockScreen.map { $0.contains(CGPoint(x: p.frame.midX, y: p.frame.midY)) } ?? false
            p.ignoresMouseEvents = away
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = away ? 0.12 : 0.2
                p.animator().alphaValue = away ? 0 : 1
            }
        }
    }

    /// White text on dark wallpapers, black on light ones (per screen), unless
    /// the config forces one.
    func updateAppearance() {
        for (p, s) in zip(panels, screens) {
            let dark: Bool
            switch settings.appearance {
            case .light: dark = false
            case .dark: dark = true
            case .auto:
                if settings.background == .blur {
                    dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                } else {
                    // The wallpaper behind the bar; if we can't read it (a
                    // protected folder), the colour macOS gives the menu bar,
                    // which follows the wallpaper too.
                    dark = s.ns.flatMap { Wallpaper.isDark(behind: p.frame, on: $0) }
                        ?? MenuBarLook.shared.isDark { [weak self] in self?.updateAppearance() }
                        ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
                }
            }
            p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            p.view.transparent = settings.background == .transparent
            p.view.needsDisplay = true
        }
    }

    private func sampleStats() {
        stats.sample(cpu: settings.shows(.cpu), memory: settings.shows(.memory), network: settings.shows(.network))
    }

    func update(_ contents: [Content], warning: String?) {
        for (p, c) in zip(panels, contents) {
            p.view.content = c
            p.view.warning = warning
        }
        redraw()
    }

    private func redraw() { panels.forEach { $0.view.needsDisplay = true } }

    fileprivate func showMenu(for event: NSEvent, in view: NSView) {
        let target = MenuTarget.shared
        target.actions = []
        let menu = NSMenu()

        let show = NSMenu()
        for w in BarWidget.allCases {
            let mi = NSMenuItem(title: w.menuTitle, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
            mi.state = settings.shows(w) ? .on : .off
            mi.tag = target.add { [weak self] in self?.onToggleWidget?(w) }
            mi.target = target
            show.addItem(mi)
        }
        show.addItem(.separator())
        let icon = NSMenuItem(title: "Icon in Top Menu Bar", action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
        icon.state = menuBarIconShown ? .on : .off
        icon.tag = target.add { [weak self] in self?.onToggleMenuBarIcon?() }
        icon.target = target
        show.addItem(icon)
        let showItem = NSMenuItem(title: "Show in Bar", action: nil, keyEquivalent: "")
        showItem.submenu = show
        menu.addItem(showItem)
        menu.addItem(.separator())

        for item in menuActions {
            if item.title == "-" { menu.addItem(.separator()); continue }
            let mi = NSMenuItem(title: item.title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
            mi.tag = target.add(item.action)
            mi.target = target
            menu.addItem(mi)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

extension BarWidget {
    var menuTitle: String {
        switch self {
        case .workspaces: return "Workspaces"
        case .layout: return "Layout"
        case .title: return "Window Title"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .date: return "Date"
        case .clock: return "Clock"
        case .battery: return "Battery"
        case .badges: return "App Badges"
        default: return rawValue          // one of yours (bar.widgets)
        }
    }
}

private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var actions: [() -> Void] = []
    func add(_ a: @escaping () -> Void) -> Int { actions.append(a); return actions.count - 1 }
    @objc func fire(_ sender: NSMenuItem) {
        if actions.indices.contains(sender.tag) { actions[sender.tag]() }
    }
}

private final class BarPanel: NSPanel {
    let view: BarView

    init(bar: Bar, index: Int) {
        view = BarView(bar: bar, index: index)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        view.autoresizingMask = [.width, .height]
        let root = NSView()
        root.addSubview(effect)
        root.addSubview(view)
        contentView = root
    }

    private let effect = NSVisualEffectView()

    func setBackground(_ b: BarSettings.Background) {
        effect.isHidden = b == .transparent
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        view.frame = contentView?.bounds ?? .zero
        effect.frame = contentView?.bounds ?? .zero
    }
}

/// One clickable thing in the bar.
private struct Segment {
    enum Action { case workspace(Int), open(String), window(UInt32), url(String), shell(String) }
    var parts: [(icon: String?, text: String)]
    var dots: (count: Int, focused: Int)? = nil  // one dot per window
    var tab: Bool? = nil                // a window tab; true = the focused one
    var tag: Bar.Tag? = nil             // workspaces only
    var color: NSColor = .labelColor
    /// An app's icon in front (badges).
    var appIcon: NSImage? = nil
    var bold = false
    var flexible = false                // takes the leftover width (title, warnings)
    var action: Action? = nil
}

private final class BarView: NSView {
    unowned let bar: Bar
    let index: Int
    var content = Bar.Content()
    var warning: String?
    /// No background: give text a soft shadow so it reads on busy wallpapers.
    var transparent = true
    private var hits: [(rect: CGRect, action: Segment.Action)] = []
    private var hover: CGPoint?
    private let dateFmt = DateFormatter()

    init(bar: Bar, index: Int) {
        self.bar = bar
        self.index = index
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseMoved(with event: NSEvent) { hover = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    // MARK: building segments

    private func segments(_ widgets: [BarWidget]) -> [Segment] {
        let s = bar.settings
        var out: [Segment] = []
        let wins = content.windows
        let focusedAt = wins.firstIndex(where: \.focused)
        // Position, dots or tabs: on, with more than one window, and in Full if asked.
        let style: BarSettings.WindowsStyle = s.windows == .off || wins.count < 2
            || (s.windowsFullOnly && !content.isFullLayout) ? .off : s.windows
        for w in widgets {
            switch w {
            case .workspaces:
                for (i, t) in content.tags.enumerated()
                where !(s.hideEmptyWorkspaces && !t.hasWindows && !t.visible) {
                    out.append(Segment(parts: [(nil, t.name)], tag: t,
                                       color: t.hasWindows || t.visible ? .labelColor : .tertiaryLabelColor,
                                       bold: t.active, action: .workspace(i)))
                }
            case .layout:
                var text = content.layout
                // Many windows don't fit as dots: the position says it shorter.
                if style == .position || (style == .dots && wins.count > 8) {
                    text += " \((focusedAt ?? 0) + 1)/\(wins.count)"
                }
                out.append(Segment(parts: [(nil, text)], color: .secondaryLabelColor))
            case .title:
                if let warning {
                    out.append(Segment(parts: [("exclamationmark.triangle.fill", warning)], color: .systemOrange, flexible: true))
                } else if style == .tabs {
                    for w in wins {
                        out.append(Segment(parts: [(nil, w.title)], tab: w.focused,
                                           color: w.focused ? .labelColor : .secondaryLabelColor,
                                           bold: w.focused && content.isCurrentScreen, flexible: true,
                                           action: .window(w.id)))
                    }
                } else {
                    if style == .dots, wins.count <= 8 {
                        out.append(Segment(parts: [], dots: (wins.count, focusedAt ?? -1),
                                           color: content.isCurrentScreen ? .labelColor : .secondaryLabelColor))
                    }
                    out.append(Segment(parts: [(nil, content.title)],
                                       color: content.isCurrentScreen ? .labelColor : .secondaryLabelColor,
                                       bold: content.isCurrentScreen, flexible: true))
                }
            case .cpu:
                out.append(Segment(parts: [("cpu", "\(Int((bar.stats.cpu * 100).rounded()))%")],
                                   action: .open("com.apple.ActivityMonitor")))
            case .memory:
                out.append(Segment(parts: [("memorychip", Stats.gigabytes(bar.stats.memoryUsed))],
                                   action: .open("com.apple.ActivityMonitor")))
            case .network:
                out.append(Segment(parts: [("arrow.down", Stats.rate(bar.stats.down)),
                                           ("arrow.up", Stats.rate(bar.stats.up))],
                                   action: .open("com.apple.ActivityMonitor")))
            case .battery:
                // No battery (iMac, Mac mini): nothing to show.
                guard let b = bar.battery.state else { continue }
                out.append(Segment(parts: [(Battery.symbol(b), s.batteryPercentage ? "\(b.percent)%" : "")],
                                   color: Battery.isLow(b) ? .systemRed : .labelColor,
                                   action: .url(Battery.settingsURL)))
            case .date:
                dateFmt.dateFormat = s.dateFormat
                out.append(Segment(parts: [(nil, dateFmt.string(from: bar.fixedNow ?? Date()))], action: .open("com.apple.iCal")))
            case .clock:
                dateFmt.dateFormat = s.clockFormat
                out.append(Segment(parts: [(nil, dateFmt.string(from: bar.fixedNow ?? Date()))], action: .open("com.apple.iCal")))
            case .badges:
                // Nothing unread: nothing shown.
                for b in DockBadges.pick(bar.badges, apps: s.badgeApps) {
                    out.append(Segment(parts: [(nil, b.label)], appIcon: bar.appIcon(b),
                                       action: b.bundleID.map { .open($0) }))
                }
            default:
                // One of yours: the first line its command printed (nothing until then).
                guard let def = s.custom[w.rawValue], let text = bar.custom.text[w.rawValue] else { continue }
                out.append(Segment(parts: [(def.icon, text)], action: def.click.map { .shell($0) }))
            }
        }
        // Without a title widget, problems still need to be visible.
        if warning != nil, !s.shows(.title), widgets == s.left {
            out.append(Segment(parts: [("exclamationmark.triangle.fill", warning!)], color: .systemOrange, flexible: true))
        }
        return out
    }

    // MARK: drawing

    private let pad: CGFloat = 7       // inside a segment, like a menu bar item
    private let iconGap: CGFloat = 4
    private let partGap: CGFloat = 8

    private func font(_ bold: Bool) -> NSFont {
        let size = CGFloat(bar.settings.fontSize)
        let base = NSFont.menuBarFont(ofSize: size)
        // Tabular digits so numbers don't jiggle as they change.
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
            .traits: [NSFontDescriptor.TraitKey.weight: bold ? NSFont.Weight.semibold : NSFont.Weight.regular],
        ])
        return NSFont(descriptor: desc, size: size) ?? base
    }

    private func icon(_ name: String, color: NSColor) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(bar.settings.fontSize) - 1, weight: .regular)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }

    private var appIconSize: CGFloat { CGFloat(bar.settings.fontSize) + 3 }
    private var dotSize: CGFloat { max(5, CGFloat(bar.settings.fontSize) * 0.45) }
    private var countFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: max(8, CGFloat(bar.settings.fontSize) * 0.65), weight: .medium) }

    private func countText(_ seg: Segment) -> String? {
        guard bar.settings.workspaceCounts, let t = seg.tag, t.count > 0 else { return nil }
        return "\(t.count)"
    }

    private func width(_ seg: Segment) -> CGFloat {
        if let d = seg.dots {
            return ceil(CGFloat(d.count) * dotSize + CGFloat(d.count - 1) * dotSize * 0.7) + 2 * pad
        }
        let f = font(seg.bold)
        var w: CGFloat = seg.appIcon == nil ? 0 : appIconSize + iconGap
        for (i, p) in seg.parts.enumerated() {
            if i > 0 { w += partGap }
            if let n = p.icon, let img = icon(n, color: seg.color) { w += img.size.width + (p.text.isEmpty ? 0 : iconGap) }
            w += (p.text as NSString).size(withAttributes: [.font: f]).width
        }
        if let c = countText(seg) { w += (c as NSString).size(withAttributes: [.font: countFont]).width + 1 }
        let total = ceil(w) + 2 * pad
        // Workspace pills are at least square, so 1…9 line up evenly.
        return seg.tag != nil ? max(total, bounds.height - 6) : total
    }

    private func draw(_ seg: Segment, in rect: CGRect) {
        let h = bounds.height
        let pill = NSRect(x: rect.minX, y: 3, width: rect.width, height: h - 6)
        let path = NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5)
        let hovered = seg.action != nil && hover.map(pill.contains) == true

        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var color = seg.color
        if let t = seg.tag, t.active {
            // Active: solid pill, text cut in the opposite color.
            NSColor.labelColor.withAlphaComponent(hovered ? 0.8 : 0.9).setFill(); path.fill()
            color = dark ? NSColor.black.withAlphaComponent(0.85) : .white
        } else if seg.tab == true {
            // The focused tab: a quiet raised pill, like a selected segment.
            NSColor.labelColor.withAlphaComponent(hovered ? 0.22 : 0.16).setFill(); path.fill()
        } else {
            if hovered { NSColor.labelColor.withAlphaComponent(0.12).setFill(); path.fill() }
            if seg.tag?.visible == true {
                let ring = NSBezierPath(roundedRect: pill.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
                ring.lineWidth = 1.5
                NSColor.labelColor.withAlphaComponent(0.55).setStroke(); ring.stroke()
            }
        }
        if let d = seg.dots {
            let size = dotSize, step = dotSize * 1.7
            var x = rect.minX + pad
            for i in 0..<d.count {
                let r = NSRect(x: x, y: (h - size) / 2, width: size, height: size)
                if i == d.focused {
                    color.setFill(); NSBezierPath(ovalIn: r).fill()
                } else {
                    let o = NSBezierPath(ovalIn: r.insetBy(dx: 0.6, dy: 0.6))
                    o.lineWidth = 1.2
                    color.withAlphaComponent(0.7).setStroke(); o.stroke()
                }
                x += step
            }
            return
        }
        if seg.tag?.hasWindows == true, countText(seg) == nil {
            // One dot = has windows, like a running app in the Dock.
            let d: CGFloat = 3.5
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: pill.midX - d / 2, y: pill.minY + 2.5, width: d, height: d)).fill()
        }
        // Workspace numbers sit a little higher to leave room for the dot.
        let lift: CGFloat = seg.tag != nil ? 1.5 : 0

        let f = font(seg.bold)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: style]
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if transparent, seg.tag?.active != true {
            let shadow = NSShadow()
            shadow.shadowColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = .zero
            shadow.set()
        }
        var x = rect.minX + pad
        if seg.tag != nil, let t = seg.parts.first?.text {
            let textW = (t as NSString).size(withAttributes: attrs).width
            if let c = countText(seg) {
                // The number and its window count, centred together; the count
                // sits up and to the right, like a superscript.
                let cAttrs: [NSAttributedString.Key: Any] = [.font: countFont, .foregroundColor: color.withAlphaComponent(0.75)]
                let cSize = (c as NSString).size(withAttributes: cAttrs)
                x = rect.midX - (textW + 1 + cSize.width) / 2
                (c as NSString).draw(at: NSPoint(x: x + textW + 1, y: h / 2 - 1), withAttributes: cAttrs)
            } else {
                x = rect.midX - textW / 2
            }
        }
        let maxX = rect.maxX - pad
        if let img = seg.appIcon {
            img.draw(in: NSRect(x: x, y: (h - appIconSize) / 2, width: appIconSize, height: appIconSize))
            x += appIconSize + iconGap
        }
        for (i, p) in seg.parts.enumerated() {
            if i > 0 { x += partGap }
            if let n = p.icon, let img = icon(n, color: color) {
                img.draw(in: NSRect(x: x, y: (h - img.size.height) / 2, width: img.size.width, height: img.size.height))
                x += img.size.width + (p.text.isEmpty ? 0 : iconGap)
            }
            let size = (p.text as NSString).size(withAttributes: attrs)
            let w = max(0, min(size.width, maxX - x))
            (p.text as NSString).draw(with: NSRect(x: x, y: (h - size.height) / 2 + lift, width: w, height: size.height),
                                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            x += w
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        let s = bar.settings
        let left = segments(s.left), right = segments(s.right)
        let edge: CGFloat = 6
        let gap: CGFloat = 2

        // Right block, laid out from the right edge.
        var rightRects: [CGRect] = []
        var rx = bounds.width - edge
        for seg in right.reversed() {
            let w = seg.flexible ? 0 : width(seg)
            rx -= w
            rightRects.insert(CGRect(x: rx, y: 0, width: w, height: bounds.height), at: 0)
            rx -= gap
        }

        // Left block; a flexible segment gets whatever is left before the right block.
        let fixed = left.filter { !$0.flexible }.reduce(CGFloat(0)) { $0 + width($1) + gap }
        let flexCount = CGFloat(left.filter(\.flexible).count)
        let room = max(0, rx - edge - 12 - fixed)
        var lx = edge
        for seg in left {
            let w = seg.flexible ? min(width(seg), room / max(1, flexCount)) : width(seg)
            let r = CGRect(x: lx, y: 0, width: w, height: bounds.height)
            if w > 2 * pad { draw(seg, in: r) }
            if let a = seg.action { hits.append((r, a)) }
            lx += w + gap
            // A little more room between widget groups than between workspaces.
            if seg.tag == nil { lx += 6 }
        }
        for (seg, r) in zip(right, rightRects) where r.minX >= lx {
            draw(seg, in: r)
            if let a = seg.action { hits.append((r, a)) }
        }
    }

    // MARK: clicks

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = hits.first(where: { $0.rect.contains(p) }) else { return }
        switch hit.action {
        case .workspace(let i):
            Log.info("bar click: workspace \(i + 1) on screen \(index)")
            bar.onClickWorkspace?(index, i)
        case .window(let id):
            bar.onClickWindow?(index, id)
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .shell(let command):
            CustomWidgetRunner.click(command)
        case .open(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        bar.showMenu(for: event, in: self)
    }
}

/// Whether macOS draws the top menu bar with white text, which it decides from
/// the wallpaper. Read from an invisible, zero-width status item, so it needs
/// no access to the wallpaper file. Only created when it's needed.
final class MenuBarLook {
    static let shared = MenuBarLook()
    private var item: NSStatusItem?
    private var watch: NSKeyValueObservation?
    private var onChange: (() -> Void)?

    func isDark(onChange: @escaping () -> Void) -> Bool? {
        self.onChange = onChange
        if item == nil {
            let it = NSStatusBar.system.statusItem(withLength: 0)
            it.button?.title = ""
            item = it
            // The menu bar turns light or dark when the wallpaper changes.
            watch = it.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.onChange?() }
            }
        }
        guard let look = item?.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) else { return nil }
        return look == .darkAqua
    }
}

/// Brightness of the wallpaper behind the bar, so the text can be white or
/// black like the menu bar's.
enum Wallpaper {
    private static var cache: [String: Bool] = [:]

    /// Folders macOS guards with a privacy prompt ("Kachel would like to
    /// access files in your Downloads folder"). A wallpaper picked from one of
    /// them isn't worth that: the bar follows light/dark mode instead.
    static func isProtected(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let guarded = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { home + "/" + $0 + "/" }
            + ["/Volumes/"]
        let path = url.standardizedFileURL.path
        return guarded.contains { path.hasPrefix($0) }
    }

    static func isDark(behind barFrame: NSRect, on screen: NSScreen) -> Bool? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen), !isProtected(url) else { return nil }
        let f = screen.frame
        // Bar position as a fraction of the screen, measured from the top (image rows).
        let top = (f.maxY - barFrame.maxY) / f.height
        let height = barFrame.height / f.height
        let key = "\(url.path)|\(top)|\(height)|\((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)"
        if let hit = cache[key] { return hit }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }

        // The wallpaper is scaled to fill the screen; crop the band behind the bar.
        let scale = max(f.width / CGFloat(img.width), f.height / CGFloat(img.height))
        let shownW = f.width / scale, shownH = f.height / scale
        let x0 = (CGFloat(img.width) - shownW) / 2, y0 = (CGFloat(img.height) - shownH) / 2
        let band = CGRect(x: x0, y: y0 + top * shownH, width: shownW, height: max(1, height * shownH)).integral
        guard let crop = img.cropping(to: band) else { return nil }

        var px = [UInt8](repeating: 0, count: 16 * 4)
        guard let ctx = CGContext(data: &px, width: 16, height: 1, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 16, height: 1))
        var lum = 0.0
        for i in 0..<16 {
            let r = Double(px[i * 4]), g = Double(px[i * 4 + 1]), b = Double(px[i * 4 + 2])
            lum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        lum /= 16
        let dark = lum < 0.6
        Log.info("wallpaper: brightness behind bar \(String(format: "%.2f", lum)) → \(dark ? "white" : "black") text")
        cache[key] = dark
        return dark
    }
}


extension Bar {
    /// For README screenshots (`Kachel --render-screenshots`): a bar view with
    /// made-up content, not attached to any screen.
    static func demoView(width: CGFloat, height: CGFloat, settings: BarSettings, content: Content,
                         now: Date, cpu: Double, memory: UInt64, down: Double, up: Double,
                         battery: Battery.State? = Battery.State(percent: 82, charging: false, onPower: false),
                         badges: [DockBadges.Badge] = [], custom: [String: String] = [:]) -> NSView {
        let bar = Bar(demo: true)
        bar.badges = badges
        for (name, line) in custom { bar.custom.setDemo(name, line) }
        bar.battery.setDemo(battery)
        bar.settings = settings
        bar.fixedNow = now
        bar.stats.setDemo(cpu: cpu, memory: memory, down: down, up: up)
        let v = BarView(bar: bar, index: 0)
        v.frame = NSRect(x: 0, y: 0, width: width, height: height)
        v.content = content
        v.transparent = settings.background == .transparent
        objc_setAssociatedObject(v, &demoBarKey, bar, .OBJC_ASSOCIATION_RETAIN)   // BarView holds it unowned
        return v
    }
}
private var demoBarKey = 0
