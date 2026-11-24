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
        view.width = w
        view.radius = radius + w / 2
        view.color = settings.color == "accent" ? .controlAccentColor : NSColor(hex: settings.color) ?? .controlAccentColor
        panel.setFrame(cocoa, display: true)
        view.needsDisplay = true
        // Right above the focused window, not above everything.
        panel.order(.above, relativeTo: Int(window))
        self.window = window
    }

    func hide() {
        panel.orderOut(nil)
        window = nil
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

private final class BorderView: NSView {
    var width: CGFloat = 3
    var radius: CGFloat = 12
    var color: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: width / 2, dy: width / 2)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
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
