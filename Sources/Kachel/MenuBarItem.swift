import AppKit

/// Kachel's icon in the top menu bar: restart, reload, quit and friends.
final class MenuBarItem: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var actions: [() -> Void] = []
    /// Built fresh each time the menu opens.
    var entries: () -> [(title: String, action: () -> Void)] = { [] }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let img = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Kachel")
            img?.isTemplate = true
            it.button?.image = img
            it.button?.toolTip = "Kachel"
            let menu = NSMenu()
            menu.delegate = self
            it.menu = menu
            item = it
        } else if !visible, let it = item {
            NSStatusBar.system.removeStatusItem(it)
            item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actions = []
        for e in entries() {
            if e.title == "-" { menu.addItem(.separator()); continue }
            let mi = NSMenuItem(title: e.title, action: #selector(fire(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = actions.count
            actions.append(e.action)
            menu.addItem(mi)
        }
    }

    @objc private func fire(_ sender: NSMenuItem) {
        if actions.indices.contains(sender.tag) { actions[sender.tag]() }
    }
}
