import AppKit
import XMonadCore

/// A tiny xmobar in the menu bar:  [1] <2> 4 5  Tall
///   [n]  workspace on the focused screen
///   <n>  workspace visible on another screen
///    n   hidden workspace that has windows
final class StatusBar: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let wm: WindowManager

    init(wm: WindowManager) {
        self.wm = wm
        super.init()
        item.button?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.addItem(withTitle: "Re-tile", action: #selector(retile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit XMonadMac", action: #selector(quit), keyEquivalent: "").target = self
        item.menu = menu
    }

    func update(_ ss: StackSet) {
        var parts: [String] = []
        for (i, ws) in ss.workspaces.enumerated() {
            if i == ss.currentWorkspaceIndex {
                parts.append("[\(ws.tag)]")
            } else if ss.isVisible(workspace: i) {
                parts.append("<\(ws.tag)>")
            } else if !ws.windows.isEmpty {
                parts.append(ws.tag)
            }
        }
        item.button?.title = parts.joined(separator: " ") + "  " + ss.current.layout.rawValue
    }

    @objc private func retile() { wm.refreshNow() }
    @objc private func quit() { wm.quit() }
}
