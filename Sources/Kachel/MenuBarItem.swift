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
            it.button?.image = MenuBarItem.stoveGlyph()
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

extension MenuBarItem {
    /// The app icon's tiled stove as a monochrome template image, so the menu
    /// bar tints it like its own icons (white on dark, black on light).
    static func stoveGlyph() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // Cornice: a cap and a wider ledge.
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 1.5, width: 9, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.75, width: 13, height: 2), xRadius: 0.8, yRadius: 0.8).fill()

            // Nine glazed tiles with thin joints, like the app icon. The
            // bottom-middle tile holds the fire door (cut out).
            let tile: CGFloat = 2.8, joint: CGFloat = 0.65
            let x0: CGFloat = 4.15, y0: CGFloat = 5.25
            let tiles = NSBezierPath()
            for row in 0..<3 {
                for col in 0..<3 {
                    let r = NSRect(x: x0 + CGFloat(col) * (tile + joint), y: y0 + CGFloat(row) * (tile + joint),
                                   width: tile, height: tile)
                    tiles.append(NSBezierPath(roundedRect: r, xRadius: 0.6, yRadius: 0.6))
                    if row == 2 && col == 1 {
                        let door = NSBezierPath()
                        let w: CGFloat = 1.5, cx = r.midX, bottom = r.maxY - 0.45
                        door.move(to: NSPoint(x: cx - w / 2, y: bottom))
                        door.line(to: NSPoint(x: cx - w / 2, y: r.minY + 0.5 + w / 2))
                        door.appendArc(withCenter: NSPoint(x: cx, y: r.minY + 0.5 + w / 2), radius: w / 2,
                                       startAngle: 180, endAngle: 0, clockwise: false)
                        door.line(to: NSPoint(x: cx + w / 2, y: bottom))
                        door.close()
                        tiles.append(door)
                    }
                }
            }
            tiles.windingRule = .evenOdd
            tiles.fill()

            // Plinth and feet.
            NSBezierPath(roundedRect: NSRect(x: 3, y: 15.2, width: 12, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            NSBezierPath(rect: NSRect(x: 4.5, y: 16.5, width: 1.8, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: 11.7, y: 16.5, width: 1.8, height: 1)).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Kachel"
        return img
    }
}
