import AppKit
import KachelCore

/// All shortcuts at a glance, on glass in the middle of the screen: shown
/// while you hold the modifier alone (shortcut-overview) or via `shortcuts`.
final class ShortcutOverview {
    private let panel: NSPanel
    private let view = OverviewView()
    private let (root, content) = Glass.make(cornerRadius: 22)

    var isOpen: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        panel.contentView = root
    }

    /// `area`: the visible frame (Cocoa coordinates) of the screen to centre on.
    func show(_ groups: [ShortcutList.Group], modifier: String, hint: String, area: NSRect) {
        view.groups = groups
        view.modifier = modifier
        view.hint = hint
        let size = view.preferredSize(maxWidth: area.width - 80)
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        content.frame = root.bounds
        view.frame = content.bounds
        view.needsDisplay = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in panel.orderOut(nil) })
    }
}

private final class OverviewView: NSView {
    var groups: [ShortcutList.Group] = []
    var modifier = ""
    var hint = ""

    private let pad: CGFloat = 28, rowH: CGFloat = 24, titleH: CGFloat = 30, groupGap: CGFloat = 14
    private let keyW: CGFloat = 96, labelW: CGFloat = 250, colGap: CGFloat = 36
    private let headerH: CGFloat = 56, footerH: CGFloat = 36

    override var isFlipped: Bool { true }

    private func height(of g: ShortcutList.Group) -> CGFloat { titleH + CGFloat(g.rows.count) * rowH + groupGap }

    /// Groups split into columns of about equal height.
    private func columns(_ n: Int) -> [[ShortcutList.Group]] {
        guard n > 1 else { return [groups] }
        let total = groups.reduce(0) { $0 + height(of: $1) }
        var cols: [[ShortcutList.Group]] = [[]], h: CGFloat = 0
        for g in groups {
            if h > 0, h + height(of: g) / 2 > total / CGFloat(n), cols.count < n {
                cols.append([]); h = 0
            }
            cols[cols.count - 1].append(g)
            h += height(of: g)
        }
        return cols
    }

    private var columnCount = 3

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let colW = keyW + labelW
        columnCount = max(1, min(3, Int((maxWidth - 2 * pad + colGap) / (colW + colGap))))
        let cols = columns(columnCount)
        let h = cols.map { $0.reduce(0) { $0 + height(of: $1) } }.max() ?? 0
        let w = CGFloat(cols.count) * colW + CGFloat(cols.count - 1) * colGap + 2 * pad
        return NSSize(width: w, height: headerH + h + footerH)
    }

    override func draw(_ dirtyRect: NSRect) {
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                                                    .foregroundColor: NSColor.labelColor]
        ("Kachel shortcuts" as NSString).draw(at: NSPoint(x: pad, y: 20), withAttributes: title)
        let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
        let modText = "mod = \(modifier)" as NSString
        modText.draw(at: NSPoint(x: bounds.width - pad - modText.size(withAttributes: sub).width, y: 23), withAttributes: sub)

        let groupFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let keyFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: 13)
        var x = pad
        for col in columns(columnCount) {
            var y = headerH
            for g in col {
                (g.title.uppercased() as NSString).draw(at: NSPoint(x: x, y: y + 8), withAttributes: [
                    .font: groupFont, .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.6])
                y += titleH
                for r in g.rows {
                    let ka: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: NSColor.labelColor]
                    let kw = (r.keys as NSString).size(withAttributes: ka).width
                    // A soft keycap behind the keys.
                    let cap = NSRect(x: x + keyW - 14 - kw - 8, y: y + 2, width: kw + 16, height: rowH - 5)
                    NSColor.labelColor.withAlphaComponent(0.08).setFill()
                    NSBezierPath(roundedRect: cap, xRadius: 6, yRadius: 6).fill()
                    (r.keys as NSString).draw(at: NSPoint(x: cap.minX + 8, y: y + 4), withAttributes: ka)
                    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
                    (r.label as NSString).draw(with: NSRect(x: x + keyW, y: y + 4, width: labelW - 8, height: rowH),
                                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                               attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor,
                                                            .paragraphStyle: style])
                    y += rowH
                }
                y += groupGap
            }
            x += keyW + labelW + colGap
        }
        let ha: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor]
        let hw = (hint as NSString).size(withAttributes: ha).width
        (hint as NSString).draw(at: NSPoint(x: (bounds.width - hw) / 2, y: bounds.height - footerH + 8), withAttributes: ha)
    }
}
