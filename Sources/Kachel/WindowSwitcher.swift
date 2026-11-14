import AppKit
import KachelCore

/// Spotlight-like search over all open windows, rising out of the bottom bar.
/// Empty query: every window grouped by workspace. Typing: best matches first.
/// ↩ go to the window, ⇧↩ bring it to this workspace, esc close.
final class WindowSwitcher: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    struct Entry {
        var id: WindowID
        var app: String
        var title: String
        var icon: NSImage?
        var workspace: Int
        var tag: String
        var visible: Bool        // its workspace is on some screen
        var active: Bool         // its workspace is the one you're in
        var recency: Int
        var focused: Bool
    }

    var onGo: ((WindowID) -> Void)?
    var onBring: ((WindowID) -> Void)?
    var onCancel: (() -> Void)?

    private let panel = SwitcherPanel()
    private let field = NSTextField()
    private let list = SwitcherList()
    private let hint = NSTextField(labelWithString: "↩ go there     ⇧↩ bring here     esc close")
    private var entries: [Entry] = []
    private var closing = false

    var isOpen: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.delegate = self

        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.contentView = root

        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        glass.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        glass.contentTintColor = .secondaryLabelColor
        glass.frame = NSRect(x: 16, y: 0, width: 20, height: 20)
        glass.autoresizingMask = [.minYMargin]
        glass.identifier = .init("glass")
        root.addSubview(glass)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.placeholderString = "Search windows"
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.autoresizingMask = [.width, .minYMargin]
        root.addSubview(field)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        root.addSubview(hint)

        list.autoresizingMask = [.width, .height]
        list.onPick = { [weak self] i, bring in self?.pick(i, bring: bring) }
        root.addSubview(list)
    }

    // MARK: open / close

    /// `area` is the screen's visible frame (Cocoa coordinates), `bottom` how
    /// much of it the bar takes.
    func open(_ entries: [Entry], area: NSRect, bottom: CGFloat) {
        self.entries = entries
        field.stringValue = ""
        let width = min(560, area.width - 16)
        panel.setFrame(NSRect(x: area.minX + 8, y: area.minY + bottom + 6, width: width, height: 200), display: false)
        refilter()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        Log.info("window search opened with \(entries.count) windows")
    }

    func close(cancelled: Bool) {
        guard panel.isVisible, !closing else { return }
        closing = true
        panel.orderOut(nil)
        closing = false
        if cancelled { onCancel?() }
    }

    func windowDidResignKey(_ notification: Notification) {
        close(cancelled: true)          // clicked somewhere else
    }

    // MARK: filtering

    private func refilter() {
        let q = field.stringValue
        let candidates = entries.map {
            WindowSearch.Candidate(id: $0.id, app: $0.app, title: $0.title, workspace: $0.workspace,
                                   recency: $0.recency, isFocused: $0.focused)
        }
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = WindowSearch.results(q, in: candidates).compactMap { byID[$0.id] }

        var rows: [SwitcherList.Row] = []
        var selected = 0
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            // Overview, grouped. Preselect the window you used before this one.
            var lastWS: Int?
            for e in ordered {
                if e.workspace != lastWS {
                    let note = e.active ? " · here" : (e.visible ? " · other screen" : "")
                    rows.append(.header("Workspace \(e.tag)\(note)"))
                    lastWS = e.workspace
                }
                rows.append(.item(e))
            }
            let items = rows.compactMap { if case .item(let e) = $0 { return e } else { return nil } }
            if let prev = items.enumerated().filter({ !$0.element.focused }).min(by: { $0.element.recency < $1.element.recency }) {
                selected = prev.offset
            }
        } else {
            rows = ordered.map { .item($0) }
        }
        list.set(rows: rows, selected: selected, emptyText: entries.isEmpty ? "No windows open" : "No matching windows")
        layout()
        list.reveal()
    }

    private func layout() {
        guard let root = panel.contentView else { return }
        let fieldH: CGFloat = 50, footerH: CGFloat = 28
        let maxList = max(120, (panel.screen?.visibleFrame.height ?? 800) * 0.6)
        let listH = min(list.contentHeight, maxList)
        var f = panel.frame
        f.size.height = fieldH + listH + footerH
        panel.setFrame(f, display: true)          // grows upward from the bar: origin stays put

        let w = f.width
        if let glass = root.subviews.first(where: { $0.identifier?.rawValue == "glass" }) {
            glass.frame.origin.y = f.height - fieldH + (fieldH - 20) / 2
        }
        field.frame = NSRect(x: 44, y: f.height - fieldH + (fieldH - 26) / 2, width: w - 60, height: 26)
        list.frame = NSRect(x: 0, y: footerH, width: w, height: listH)
        hint.frame = NSRect(x: 20, y: 7, width: w - 40, height: 15)
        root.needsDisplay = true
        list.needsDisplay = true
    }

    private func pick(_ index: Int, bring: Bool) {
        guard let e = list.item(at: index) else { return }
        close(cancelled: false)
        Log.info("window search: \(bring ? "bring" : "go to") \(e.app) \"\(e.title.prefix(40))\" on workspace \(e.tag)")
        if bring { onBring?(e.id) } else { onGo?(e.id) }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
            list.move(+1); return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)):
            list.move(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            pick(list.selected, bring: shift); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(cancelled: true); return true
        default:
            return false
        }
    }
}

private final class SwitcherPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isFloatingPanel = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
    override var canBecomeKey: Bool { true }
}

/// The result rows, drawn by hand so they look like Spotlight's.
private final class SwitcherList: NSView {
    enum Row { case header(String), item(WindowSwitcher.Entry) }

    var onPick: ((Int, Bool) -> Void)?
    private(set) var selected = 0          // index among item rows
    private var rows: [Row] = []
    private var emptyText = ""
    private var scroll: CGFloat = 0

    private let rowH: CGFloat = 38, headerH: CGFloat = 26, inset: CGFloat = 8

    override var isFlipped: Bool { true }

    private var items: [WindowSwitcher.Entry] {
        rows.compactMap { if case .item(let e) = $0 { return e } else { return nil } }
    }
    func item(at i: Int) -> WindowSwitcher.Entry? { items.indices.contains(i) ? items[i] : nil }

    var contentHeight: CGFloat {
        if rows.isEmpty { return 44 }
        return rows.reduce(inset * 2) { h, r in
            if case .header = r { return h + headerH } else { return h + rowH }
        }
    }

    func set(rows: [Row], selected: Int, emptyText: String) {
        self.rows = rows
        self.emptyText = emptyText
        self.selected = min(selected, max(0, items.count - 1))
        scroll = 0
        needsDisplay = true
    }

    /// Call once the view has its final size: scrolls only if the selected
    /// row really doesn't fit.
    func reveal() {
        scroll = 0
        keepSelectionVisible()
        needsDisplay = true
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + d + items.count) % items.count
        keepSelectionVisible()
        needsDisplay = true
    }

    /// y range of each row, before scrolling.
    private func frames() -> [(row: Row, rect: CGRect, item: Int?)] {
        var y = inset, n = 0
        var out: [(Row, CGRect, Int?)] = []
        for r in rows {
            switch r {
            case .header:
                out.append((r, CGRect(x: 0, y: y, width: bounds.width, height: headerH), nil)); y += headerH
            case .item:
                out.append((r, CGRect(x: 0, y: y, width: bounds.width, height: rowH), n)); y += rowH; n += 1
            }
        }
        return out
    }

    private func keepSelectionVisible() {
        guard let f = frames().first(where: { $0.item == selected })?.rect else { return }
        let h = bounds.height
        if f.minY - scroll < 0 { scroll = max(0, f.minY - inset - headerH) }
        if f.maxY - scroll > h { scroll = f.maxY - h + inset }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Hairline between the search field and the results.
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()

        if rows.isEmpty {
            draw(emptyText, at: NSPoint(x: 20, y: 13), font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        for (row, r0, idx) in frames() {
            let r = r0.offsetBy(dx: 0, dy: -scroll)
            guard r.maxY > 0, r.minY < bounds.height else { continue }
            switch row {
            case .header(let text):
                draw(text, at: NSPoint(x: 20, y: r.minY + 8), font: .systemFont(ofSize: 11, weight: .semibold),
                     color: .secondaryLabelColor)
            case .item(let e):
                drawItem(e, in: r, selected: idx == selected)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawItem(_ e: WindowSwitcher.Entry, in r: CGRect, selected: Bool) {
        let box = r.insetBy(dx: inset, dy: 1)
        if selected {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        }
        let fg: NSColor = selected ? .white : .labelColor
        let fg2: NSColor = selected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor

        let iconSize: CGFloat = 22
        if let icon = e.icon {
            icon.draw(in: NSRect(x: box.minX + 8, y: box.midY - iconSize / 2, width: iconSize, height: iconSize),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        // Workspace badge, same language as the bar: solid = here, outline = on a screen.
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let tw = (e.tag as NSString).size(withAttributes: [.font: font]).width
        let badge = NSRect(x: box.maxX - 10 - max(20, tw + 10), y: box.midY - 10, width: max(20, tw + 10), height: 20)
        let path = NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5)
        var badgeText = fg2
        if e.active {
            fg.withAlphaComponent(0.9).setFill(); path.fill()
            badgeText = selected ? .controlAccentColor : .windowBackgroundColor
        } else if e.visible {
            fg.withAlphaComponent(0.6).setStroke(); path.lineWidth = 1.2; path.stroke()
            badgeText = fg
        } else {
            fg2.withAlphaComponent(0.35).setStroke(); path.lineWidth = 0.8; path.stroke()
        }
        draw(e.tag, at: NSPoint(x: badge.midX - tw / 2, y: badge.minY + 3), font: font, color: badgeText)

        // Title, then the app name in grey.
        let x = box.minX + 8 + iconSize + 10
        let maxW = badge.minX - 12 - x
        let title = e.title.isEmpty ? e.app : e.title
        let titleFont = NSFont.systemFont(ofSize: 14)
        let tW = min((title as NSString).size(withAttributes: [.font: titleFont]).width, maxW)
        draw(title, in: NSRect(x: x, y: box.midY - 9, width: tW, height: 18), font: titleFont, color: fg)
        if !e.title.isEmpty, e.title != e.app, tW + 8 < maxW {
            draw(e.app, in: NSRect(x: x + tW + 8, y: box.midY - 8, width: maxW - tW - 8, height: 17),
                 font: .systemFont(ofSize: 12), color: fg2)
        }
    }

    private func draw(_ s: String, at p: NSPoint, font: NSFont, color: NSColor) {
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func draw(_ s: String, in r: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    // MARK: mouse

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self))
    }

    private func itemIndex(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return frames().first { $0.item != nil && $0.rect.offsetBy(dx: 0, dy: -scroll).contains(p) }?.item
    }

    override func mouseMoved(with event: NSEvent) {
        if let i = itemIndex(at: event), i != selected { selected = i; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        if let i = itemIndex(at: event) { onPick?(i, event.modifierFlags.contains(.shift)) }
    }

    override func scrollWheel(with event: NSEvent) {
        scroll = min(max(0, scroll - event.scrollingDeltaY), max(0, contentHeight - bounds.height))
        needsDisplay = true
    }
}
