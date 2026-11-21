import AppKit

/// Kachel's panel background: Apple's Liquid Glass on macOS 26, the frosted
/// popover material before that. Put subviews into `content`.
enum Glass {
    static func make(cornerRadius: CGFloat) -> (root: NSView, content: NSView) {
        let content = NSView()
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return (glass, content)
        }
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.separatorColor.cgColor
        content.frame = blur.bounds
        blur.addSubview(content)
        return (blur, content)
    }
}

/// A light tap on the trackpad, like native gestures and snapping give.
/// Only felt on Force Touch trackpads, and only while a finger is on it.
enum Haptics {
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard Config.current.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
