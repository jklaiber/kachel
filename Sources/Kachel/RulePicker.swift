import AppKit
import KachelCore

/// "Always open <app> on …": a small panel rising from the bar.
/// 1–9 pick a workspace, F toggles floating, ⌫ removes the rule, esc cancels.
final class RulePicker: NSObject, NSWindowDelegate {
    enum Choice { case workspace(Int), toggleFloat, remove }

    var onChoose: ((Choice) -> Void)?
    var onCancel: (() -> Void)?

    private let panel = PickerPanel()
    private let view = PickerView()
    private var content: NSView!
    private var closing = false

    var isOpen: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.delegate = self
        let (glassRoot, content) = Glass.make(cornerRadius: 18)   // Liquid Glass on macOS 26
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        self.content = content
        panel.contentView = glassRoot
        view.onChoose = { [weak self] c in self?.choose(c) }
        view.onCancel = { [weak self] in self?.close(cancelled: true) }
    }

    /// `current`: the workspace the app's rule points to, if any.
    func open(app: String, icon: NSImage?, tags: [String], current: Int?, floats: Bool, hasRule: Bool,
              area: NSRect, bottom: CGFloat) {
        view.app = app
        view.icon = icon
        view.tags = tags
        view.current = current
        view.floats = floats
        view.hasRule = hasRule
        let size = view.preferredSize
        panel.setFrame(NSRect(x: area.minX + 8, y: area.minY + bottom + 6,
                              width: min(size.width, area.width - 16), height: size.height), display: true)
        content.frame = panel.contentView!.bounds
        view.frame = content.bounds
        view.needsDisplay = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func close(cancelled: Bool) {
        guard panel.isVisible, !closing else { return }
        closing = true
        panel.orderOut(nil)
        closing = false
        if cancelled { onCancel?() }
    }

    func windowDidResignKey(_ notification: Notification) { close(cancelled: true) }

    private func choose(_ c: Choice) {
        close(cancelled: false)
        onChoose?(c)
    }
}

private final class PickerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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

private final class PickerView: NSView {
    var onChoose: ((RulePicker.Choice) -> Void)?
    var onCancel: (() -> Void)?
    var app = ""
    var icon: NSImage?
    var tags: [String] = []
    var current: Int?
    var floats = false
    var hasRule = false

    private enum Target: Equatable { case tag(Int), float, remove }
    private var targets: [(Target, CGRect)] = []
    private var hover: Target?

    private let pill: CGFloat = 32, gap: CGFloat = 6, pad: CGFloat = 16

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var preferredSize: NSSize {
        let tagsW = CGFloat(tags.count) * pill + CGFloat(max(0, tags.count - 1)) * gap
        let extra = textWidth("Float", 13) + textWidth("No rule", 13) + 2 * 24 + 2 * gap + 14
        return NSSize(width: max(360, pad * 2 + tagsW + extra), height: 124)
    }

    private func textWidth(_ s: String, _ size: CGFloat) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium)]).width
    }

    override func draw(_ dirtyRect: NSRect) {
        targets = []
        // Header: icon + "Slack — always open on:"
        if let icon {
            icon.draw(in: NSRect(x: pad, y: 14, width: 22, height: 22), from: .zero, operation: .sourceOver,
                      fraction: 1, respectFlipped: true, hints: nil)
        }
        let head = NSMutableAttributedString(string: app, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                                                                        .foregroundColor: NSColor.labelColor])
        head.append(NSAttributedString(string: hasRule ? " — always open on:" : " — always open on…",
                                       attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor]))
        head.draw(at: NSPoint(x: pad + 30, y: 16))

        // Workspace pills, in the bar's language: solid = the rule's workspace.
        var x = pad
        let y: CGFloat = 50
        for (i, t) in tags.enumerated() {
            let r = CGRect(x: x, y: y, width: pill, height: pill)
            drawPill(r, text: t, on: current == i, hovered: hover == .tag(i))
            targets.append((.tag(i), r))
            x += pill + gap
        }
        x += 14
        for (target, title, on) in [(Target.float, "Float", floats), (Target.remove, "No rule", false)] {
            let w = textWidth(title, 13) + 24
            let r = CGRect(x: x, y: y, width: w, height: pill)
            drawPill(r, text: title, on: on, hovered: hover == target, dim: target == .remove && !hasRule)
            targets.append((target, r))
            x += w + gap
        }

        let hint = "1–\(min(9, tags.count)) pick     F float     ⌫ remove rule     esc cancel"
        (hint as NSString).draw(at: NSPoint(x: pad, y: 96),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
    }

    private func drawPill(_ r: CGRect, text: String, on: Bool, hovered: Bool, dim: Bool = false) {
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        var fg: NSColor = dim ? .tertiaryLabelColor : .labelColor
        if on {
            NSColor.controlAccentColor.setFill(); path.fill(); fg = .white
        } else {
            NSColor.labelColor.withAlphaComponent(hovered ? 0.14 : 0.06).setFill(); path.fill()
        }
        let font = NSFont.systemFont(ofSize: 13, weight: on ? .semibold : .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                                withAttributes: [.font: font, .foregroundColor: fg])
    }

    private func perform(_ t: Target) {
        switch t {
        case .tag(let i): onChoose?(.workspace(i))
        case .float: onChoose?(.toggleFloat)
        case .remove: if hasRule { onChoose?(.remove) }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: onCancel?(); return                       // esc
        case 51, 117: perform(.remove); return              // delete, forward delete
        default: break
        }
        let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
        if let n = Int(ch), n >= 1, n <= tags.count { perform(.tag(n - 1)); return }
        if ch == "f" { perform(.float); return }
        if ch == "0" { perform(.remove); return }
        NSSound.beep()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = targets.first { $0.1.contains(p) }?.0
        if h != hover { hover = h; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let t = targets.first(where: { $0.1.contains(p) })?.0 { perform(t) }
    }
}


extension RulePicker {
    /// Screenshots: the picker for an app, not shown on screen.
    static func demoView(app: String, icon: NSImage?, tags: [String], current: Int?, floats: Bool) -> NSView {
        let v = PickerView()
        v.app = app; v.icon = icon; v.tags = tags; v.current = current; v.floats = floats; v.hasRule = current != nil
        v.frame = NSRect(origin: .zero, size: v.preferredSize)
        return v
    }
}
