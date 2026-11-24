import AppKit
import ApplicationServices
import KachelCore

extension WindowManager {
    // MARK: - shortcut overview

    func modifierEvent(_ e: NSEvent) {
        // A key or click of yours: focus changes after it are your doing.
        if e.type == .keyDown || e.type == .leftMouseDown || e.type == .rightMouseDown {
            lastUserInput = clock.now
        }
        let delay = Config.current.shortcutOverview
        if e.type == .flagsChanged {
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            holdTimer?.invalidate()
            if delay > 0, managing, mods == Self.flags(Config.current.mod), Self.rightSide(e) {
                holdTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [unowned self] _ in
                    let now = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
                    guard now == Self.flags(Config.current.mod) else { return }
                    self.showOverview(hint: "Release \(ShortcutList.glyphs(Config.current.mod)) to close")
                }
            } else {
                overview.hide()
            }
        } else {
            holdTimer?.invalidate()
            overview.hide()
        }
    }

    /// With `mod: left-alt`, holding right Option is typing, not mod.
    static func rightSide(_ e: NSEvent) -> Bool {
        let raw = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
        return Config.current.modSides.allSatisfy { raw.contains(HotKeys.deviceFlag($0.key, $0.value)) }
    }

    static func flags(_ mods: Set<Modifier>) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if mods.contains(.cmd) { f.insert(.command) }
        if mods.contains(.alt) { f.insert(.option) }
        if mods.contains(.ctrl) { f.insert(.control) }
        if mods.contains(.shift) { f.insert(.shift) }
        return f
    }

    func showOverview(hint: String) {
        let cfg = Config.current
        guard ss.currentScreen < screens.count else { return }
        overview.show(ShortcutList.groups(cfg.keys, workspaces: cfg.workspaces),
                      modifier: ShortcutList.glyphs(cfg.mod), hint: hint, area: screens[ss.currentScreen].nsVisible)
        Log.info("shortcut overview shown")
    }

    // MARK: - focus border

    /// After a focus change, check twice that the frame is still on top of
    /// its window (the app may bring the window forward after we placed it).
    func keepBorderAbove() {
        guard !headless else { return }
        for delay in [0.15, 0.5] {
            clock.after(delay) { [weak self] in
                guard let self, let id = self.border.window, id == self.ss.current.focused else { return }
                if self.border.keepAbove() {
                    Log.info("focus border was behind window \(id): put it back on top")
                }
            }
        }
    }

    /// Frame the focused window (if it's on screen and the border is wanted).
    func updateBorder() {
        guard !headless else { return }
        let cfg = Config.current.border
        guard managing, cfg.enabled, !switcher.isOpen, !rulePicker.isOpen,
              let f = ss.current.focused, let w = windows[f], !hidden.contains(f), !scratchParked.contains(f),
              let frame = w.frame else { border.hide(); return }
        if cfg.smart, !ss.floating.contains(f),
           ss.current.windows.filter({ windows[$0] != nil && !ss.floating.contains($0) }).count == 1 {
            border.hide(); return
        }
        border.show(around: frame, of: f, radius: cfg.radius.map { CGFloat($0) } ?? WindowCorners.radius(of: w),
                    settings: cfg)
    }
}
