import AppKit
import XMonadCore

/// A second menu bar along the bottom of every screen, just above the Dock.
/// Same height, font and translucency as the real one at the top.
///
///   1  2  3  5   Tall   Safari — Apple           ↓1.2 MB/s ↑40 KB/s  ▣ 12%  ▤ 9.1 GB  Sat 14 Nov  16:43
///
/// Which widgets appear, and in what order, comes from `bar.left` / `bar.right`.
/// Click a workspace to show it on that screen; right-click for the menu.
final class Bar {
    enum TagState { case focused, shownHere, shownElsewhere, occupied, empty }

    struct Content {
        var tags: [(name: String, state: TagState)] = []
        var layout = ""
        var title = ""
        var isCurrentScreen = false
    }

    var onClickWorkspace: ((_ screen: Int, _ workspace: Int) -> Void)?
    var onToggleWidget: ((BarWidget) -> Void)?
    var menuActions: [(title: String, action: () -> Void)] = []

    let stats = Stats()
    private var panels: [BarPanel] = []
    private var clockTimer: Timer?
    private var statsTimer: Timer?
    private(set) var settings = BarSettings()

    init() {
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
            return
        }
        while panels.count > screens.count { panels.removeLast().orderOut(nil) }
        while panels.count < screens.count { panels.append(BarPanel(bar: self, index: panels.count)) }
        let h = Bar.height(for: settings)
        for (p, s) in zip(panels, screens) {
            let v = s.nsVisible
            p.setFrame(NSRect(x: v.minX, y: v.minY, width: v.width, height: h), display: true)
            p.orderFrontRegardless()
        }

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

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        view.autoresizingMask = [.width, .height]
        effect.addSubview(view)
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        view.frame = contentView?.bounds ?? .zero
    }
}

/// One clickable thing in the bar.
private struct Segment {
    enum Action { case workspace(Int), open(String) }
    var parts: [(icon: String?, text: String)]
    var state: Bar.TagState? = nil      // workspaces only
    var color: NSColor = .labelColor
    var bold = false
    var flexible = false                // takes the leftover width (title, warnings)
    var action: Action? = nil
}

private final class BarView: NSView {
    unowned let bar: Bar
    let index: Int
    var content = Bar.Content()
    var warning: String?
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
        for w in widgets {
            switch w {
            case .workspaces:
                for (i, t) in content.tags.enumerated() where !(s.hideEmptyWorkspaces && t.state == .empty) {
                    out.append(Segment(parts: [(nil, t.name)], state: t.state,
                                       color: t.state == .empty ? .tertiaryLabelColor : .labelColor,
                                       bold: t.state == .focused, action: .workspace(i)))
                }
            case .layout:
                out.append(Segment(parts: [(nil, content.layout)], color: .secondaryLabelColor))
            case .title:
                if let warning {
                    out.append(Segment(parts: [("exclamationmark.triangle.fill", warning)], color: .systemOrange, flexible: true))
                } else {
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
            case .date:
                dateFmt.dateFormat = s.dateFormat
                out.append(Segment(parts: [(nil, dateFmt.string(from: Date()))], action: .open("com.apple.iCal")))
            case .clock:
                dateFmt.dateFormat = s.clockFormat
                out.append(Segment(parts: [(nil, dateFmt.string(from: Date()))], action: .open("com.apple.iCal")))
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

    private func width(_ seg: Segment) -> CGFloat {
        let f = font(seg.bold)
        var w: CGFloat = 0
        for (i, p) in seg.parts.enumerated() {
            if i > 0 { w += partGap }
            if let n = p.icon, let img = icon(n, color: seg.color) { w += img.size.width + iconGap }
            w += (p.text as NSString).size(withAttributes: [.font: f]).width
        }
        return ceil(w) + 2 * pad
    }

    private func draw(_ seg: Segment, in rect: CGRect) {
        let h = bounds.height
        let pill = NSRect(x: rect.minX, y: 3, width: rect.width, height: h - 6)
        let path = NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5)
        let hovered = seg.action != nil && hover.map(pill.contains) == true

        switch seg.state {
        case .focused?: NSColor.labelColor.withAlphaComponent(hovered ? 0.24 : 0.18).setFill(); path.fill()
        case .shownHere?: NSColor.labelColor.withAlphaComponent(hovered ? 0.16 : 0.09).setFill(); path.fill()
        case .shownElsewhere?:
            if hovered { NSColor.labelColor.withAlphaComponent(0.1).setFill(); path.fill() }
            let inset = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            NSColor.labelColor.withAlphaComponent(0.3).setStroke(); inset.lineWidth = 1; inset.stroke()
        default:
            if hovered { NSColor.labelColor.withAlphaComponent(0.1).setFill(); path.fill() }
        }

        let f = font(seg.bold)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: seg.color, .paragraphStyle: style]
        var x = rect.minX + pad
        let maxX = rect.maxX - pad
        for (i, p) in seg.parts.enumerated() {
            if i > 0 { x += partGap }
            if let n = p.icon, let img = icon(n, color: seg.color) {
                img.draw(in: NSRect(x: x, y: (h - img.size.height) / 2, width: img.size.width, height: img.size.height))
                x += img.size.width + iconGap
            }
            let size = (p.text as NSString).size(withAttributes: attrs)
            let w = max(0, min(size.width, maxX - x))
            (p.text as NSString).draw(with: NSRect(x: x, y: (h - size.height) / 2, width: w, height: size.height),
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
            if seg.state == nil { lx += 6 }
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
