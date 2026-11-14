import AppKit
import XMonadCore

/// An xmobar-like strip along the bottom of every screen, just above the Dock:
///
///   [1] 2  3  5    Tall    Safari — Apple                       Sat 14 Nov  16:43
///
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
    var menuActions: [(title: String, action: () -> Void)] = []

    private var panels: [BarPanel] = []
    private var clockTimer: Timer?
    private var settings = BarSettings()

    init() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.panels.forEach { $0.view.needsDisplay = true }
        }
    }

    /// Create / move one panel per screen.
    func place(on screens: [Screen], settings: BarSettings) {
        self.settings = settings
        guard settings.enabled else {
            panels.forEach { $0.orderOut(nil) }
            panels.removeAll()
            return
        }
        while panels.count > screens.count { panels.removeLast().orderOut(nil) }
        while panels.count < screens.count { panels.append(BarPanel(bar: self, index: panels.count)) }
        for (p, s) in zip(panels, screens) {
            let v = s.nsVisible
            p.setFrame(NSRect(x: v.minX, y: v.minY, width: v.width, height: settings.height), display: true)
            p.view.settings = settings
            p.orderFrontRegardless()
        }
    }

    func update(_ contents: [Content], warning: String?) {
        for (p, c) in zip(panels, contents) {
            p.view.content = c
            p.view.warning = warning
            p.view.needsDisplay = true
        }
    }

    fileprivate func showMenu(for event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        for (i, item) in menuActions.enumerated() {
            if item.title == "-" { menu.addItem(.separator()); continue }
            let mi = NSMenuItem(title: item.title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
            mi.tag = i
            mi.target = MenuTarget.shared
            menu.addItem(mi)
        }
        MenuTarget.shared.actions = menuActions.map(\.action)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var actions: [() -> Void] = []
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

private final class BarView: NSView {
    unowned let bar: Bar
    let index: Int
    var content = Bar.Content()
    var warning: String?
    var settings = BarSettings()
    private var tagRects: [CGRect] = []
    private let clock = DateFormatter()

    init(bar: Bar, index: Int) {
        self.bar = bar
        self.index = index
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .semibold)
        let h = bounds.height
        let pad: CGFloat = 8
        var x: CGFloat = pad

        // Top hairline, like the edge of a menu.
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: h - 1, width: bounds.width, height: 1).fill()

        func draw(_ text: String, at x: CGFloat, font: NSFont, color: NSColor, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            let size = (text as NSString).size(withAttributes: attrs)
            let w = min(size.width, maxWidth)
            (text as NSString).draw(with: NSRect(x: x, y: (h - size.height) / 2, width: w, height: size.height),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            return w
        }

        // Workspaces
        tagRects = []
        let accent = NSColor.controlAccentColor
        for (name, state) in content.tags {
            let f = state == .focused ? bold : font
            let tw = (name as NSString).size(withAttributes: [.font: f]).width
            let pill = NSRect(x: x, y: 3, width: max(tw + 12, h - 6), height: h - 6)
            tagRects.append(pill)
            let path = NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5)
            let fg: NSColor
            switch state {
            case .focused:
                accent.setFill(); path.fill(); fg = .white
            case .shownHere:
                accent.withAlphaComponent(0.35).setFill(); path.fill(); fg = .labelColor
            case .shownElsewhere:
                accent.withAlphaComponent(0.8).setStroke(); path.lineWidth = 1; path.stroke(); fg = .labelColor
            case .occupied:
                fg = .labelColor
            case .empty:
                fg = .tertiaryLabelColor
            }
            _ = draw(name, at: pill.midX - tw / 2, font: f, color: fg)
            x = pill.maxX + 3
        }

        x += 10
        x += draw(content.layout, at: x, font: font, color: .secondaryLabelColor) + 14

        // Clock (right-aligned)
        var right = bounds.width - pad
        if !settings.clockFormat.isEmpty {
            clock.dateFormat = settings.clockFormat
            let text = clock.string(from: Date())
            let w = (text as NSString).size(withAttributes: [.font: font]).width
            right -= w
            _ = draw(text, at: right, font: font, color: .labelColor)
            right -= 14
        }

        // Warning beats title.
        if let warning {
            _ = draw("⚠ " + warning, at: x, font: font, color: .systemOrange, maxWidth: max(0, right - x))
        } else if settings.showTitle, !content.title.isEmpty {
            _ = draw(content.title, at: x, font: font,
                     color: content.isCurrentScreen ? .labelColor : .secondaryLabelColor, maxWidth: max(0, right - x))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = tagRects.firstIndex(where: { $0.insetBy(dx: -1, dy: -3).contains(p) }) {
            bar.onClickWorkspace?(index, i)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        bar.showMenu(for: event, in: self)
    }
}
