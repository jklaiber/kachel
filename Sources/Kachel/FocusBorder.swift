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
    }

    func hide() { panel.orderOut(nil) }
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
