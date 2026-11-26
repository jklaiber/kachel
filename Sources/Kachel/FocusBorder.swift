import AppKit
import KachelCore

/// The frame around the focused window: a click-through window placed just
/// above it, so windows on top of it still cover the frame like they should.
final class FocusBorder {
    private let panel: NSPanel
    private let view = BorderView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        panel.contentView = view
    }

    /// `frame` in AX coordinates (top-left origin).
    /// The stroke sits on the window's edge, half inside and half outside,
    /// so there's never a gap between frame and window.
    func show(around frame: CGRect, of window: WindowID, radius: CGFloat, settings: BorderSettings) {
        guard let primary = NSScreen.screens.first else { return }
        let w = CGFloat(settings.width)
        let cocoa = NSRect(x: frame.minX - w / 2, y: primary.frame.height - frame.maxY - w / 2,
                           width: frame.width + w, height: frame.height + w)
        let color = settings.color == "accent" ? NSColor.controlAccentColor : NSColor(hex: settings.color) ?? .controlAccentColor
        // Same place, same look: nothing to do (it's asked after every refresh).
        let look = Look(frame: cocoa, width: w, radius: radius + w / 2, color: color, window: window)
        if look == shown, panel.isVisible { return }
        shown = look
        view.set(width: w, radius: radius + w / 2, color: color)
        panel.setFrame(cocoa, display: false)
        // Right above the focused window, not above everything.
        panel.order(.above, relativeTo: Int(window))
        self.window = window
    }

    private struct Look: Equatable {
        var frame: NSRect, width: CGFloat, radius: CGFloat, color: NSColor, window: WindowID
    }
    private var shown: Look?

    func hide() {
        panel.orderOut(nil)
        window = nil
        shown = nil
    }

    /// The window the frame is around, while it's shown.
    private(set) var window: WindowID?

    /// Apps bring their windows forward on their own, sometimes after we
    /// placed the frame (activation is asynchronous, Electron reorders its
    /// windows): then the window covers its own frame. Put it back on top of
    /// it. Returns whether it had to.
    @discardableResult
    func keepAbove() -> Bool {
        guard let window, panel.isVisible, isBelow(window) else { return false }
        panel.order(.above, relativeTo: Int(window))
        return true
    }

    /// Is the frame behind its window? (The window server lists windows
    /// front to back.)
    private func isBelow(_ window: WindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let order = list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        guard let mine = order.firstIndex(of: UInt32(panel.windowNumber)),
              let its = order.firstIndex(of: window) else { return false }
        return mine > its
    }
}

/// The line itself is a layer border, drawn by Core Animation: no picture
/// of the whole window's size (that took around 100 MB of graphics memory
/// on a large window, again on every redraw).
private final class BorderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous             // like macOS windows' corners
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    func set(width: CGFloat, radius: CGFloat, color: NSColor) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)        // no fade between looks
        layer.borderWidth = width
        layer.cornerRadius = radius
        layer.borderColor = color.cgColor
        CATransaction.commit()
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
