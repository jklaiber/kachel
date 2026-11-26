import AppKit

extension NSApplication {
    /// Bring Kachel in front of the app you're in, for one of its own windows.
    /// The cooperative `activate()` lets the app in front refuse, and it often
    /// does when you pick something from Kachel's menus: the window then opens
    /// behind it and it takes a second try (#15, the Settings window). The
    /// forceful (deprecated) call isn't refused.
    func comeForward() {
        activate(ignoringOtherApps: true)
    }
}
