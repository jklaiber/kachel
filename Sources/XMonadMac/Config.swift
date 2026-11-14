import AppKit
import Carbon.HIToolbox
import XMonadCore

// ─────────────────────────────────────────────────────────────────────────────
//  This file is your xmonad.hs: edit it and rebuild (scripts/bundle.sh).
// ─────────────────────────────────────────────────────────────────────────────

enum Config {
    /// modMask. Default is Ctrl+Option: on a Swiss (or any European) keyboard,
    /// Option+digit types characters like | @ # [ ], so plain Option clashes.
    /// Alternatives: UInt32(optionKey), UInt32(cmdKey | optionKey), …
    static let modMask = UInt32(controlKey | optionKey)
    static let shiftMask = UInt32(shiftKey)

    static let workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// Gap in points, between windows and at screen edges.
    static let gap: CGFloat = 6
    static let defaultRatio = 0.5
    static let ratioStep = 0.03

    /// Warp the mouse to the focused screen when focus changes screens.
    static let mouseFollowsFocus = true

    /// mod-shift-return. Examples:
    ///   "open -na Alacritty"   "open -na kitty"   "open -na WezTerm"
    ///   "open -na Ghostty"     "open -na iTerm"
    static let terminal =
        #"osascript -e 'tell application "Terminal" to do script ""' -e 'tell application "Terminal" to activate'"#

    /// Like a manageHook `doFloat`: apps whose windows never tile.
    static let floatingBundleIDs: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.calculator",
        "com.apple.archiveutility",
    ]

    static func bindKeys(_ wm: WindowManager) {
        let M = modMask, S = shiftMask
        let k = HotKeys.shared

        // mod-[1..9]        greedyView: bring workspace N to this screen
        //                   (swaps with the other screen if it's visible there)
        // mod-shift-[1..9]  send focused window to workspace N
        let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                          kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, key) in numberKeys.enumerated() where i < workspaces.count {
            k.bind(key, M) { wm.greedyView(i) }      // use wm.view(i) for plain W.view
            k.bind(key, M | S) { wm.shift(to: i) }
        }

        // mod-{w,e,r}       focus screen 1/2/3
        // mod-shift-{w,e,r} send focused window to screen 1/2/3
        for (s, key) in [kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R].enumerated() {
            k.bind(key, M) { wm.focusScreen(s) }
            k.bind(key, M | S) { wm.shiftToScreen(s) }
        }

        k.bind(kVK_ANSI_J, M) { wm.focusDown() }
        k.bind(kVK_ANSI_K, M) { wm.focusUp() }
        k.bind(kVK_Tab, M) { wm.focusDown() }
        k.bind(kVK_ANSI_M, M) { wm.focusMaster() }
        k.bind(kVK_ANSI_J, M | S) { wm.swapDown() }
        k.bind(kVK_ANSI_K, M | S) { wm.swapUp() }
        k.bind(kVK_Return, M) { wm.swapMaster() }

        k.bind(kVK_ANSI_H, M) { wm.adjustRatio(-ratioStep) }
        k.bind(kVK_ANSI_L, M) { wm.adjustRatio(+ratioStep) }
        k.bind(kVK_ANSI_Comma, M) { wm.incMaster(+1) }
        k.bind(kVK_ANSI_Period, M) { wm.incMaster(-1) }
        k.bind(kVK_Space, M) { wm.nextLayout() }
        k.bind(kVK_ANSI_T, M) { wm.toggleFloat() }       // xmonad "sink" (and float)
        k.bind(kVK_ANSI_N, M) { wm.refreshNow() }

        k.bind(kVK_Return, M | S) { wm.spawn(terminal) }
        k.bind(kVK_ANSI_C, M | S) { wm.closeFocused() }
        k.bind(kVK_ANSI_Q, M | S) { wm.quit() }
    }
}
