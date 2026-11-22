import AppKit

/// Kachel's panel background: Apple's Liquid Glass. Put subviews into `content`.
enum Glass {
    static func make(cornerRadius: CGFloat) -> (root: NSView, content: NSView) {
        let content = NSView()
        content.autoresizingMask = [.width, .height]
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        glass.contentView = content
        return (glass, content)
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
