import CoreGraphics

/// xmonad-style layouts. Rects are in Accessibility coordinates
/// (origin top-left of the primary display, y grows downward).
public enum Layout {
    public static func tile(_ kind: LayoutKind, count n: Int, in rect: CGRect,
                            nMaster: Int, ratio: Double, gap: CGFloat) -> [CGRect] {
        guard n > 0 else { return [] }
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        let cells: [CGRect]
        switch kind {
        case .full:       cells = Array(repeating: area, count: n)
        case .tall:       cells = tall(n, area, nMaster, ratio, mirrored: false)
        case .mirrorTall: cells = tall(n, area, nMaster, ratio, mirrored: true)
        case .column:     cells = stack(n, area, true)
        }
        return cells.map { $0.insetBy(dx: gap / 2, dy: gap / 2).integral }
    }

    /// Tall: master column on the left (ratio of width), the rest stacked on the right.
    /// Mirrored: master row on top, the rest side by side below.
    static func tall(_ n: Int, _ area: CGRect, _ nMaster: Int, _ ratio: Double,
                     mirrored: Bool) -> [CGRect] {
        let nm = max(0, nMaster)
        if nm == 0 || n <= nm { return stack(n, area, mirrored) }
        let edge: CGRectEdge = mirrored ? .minYEdge : .minXEdge
        let dist = (mirrored ? area.height : area.width) * CGFloat(ratio)
        let (master, rest) = area.divided(atDistance: dist, from: edge)
        return stack(nm, master, mirrored) + stack(n - nm, rest, mirrored)
    }

    static func stack(_ k: Int, _ r: CGRect, _ mirrored: Bool) -> [CGRect] {
        (0..<k).map { i in
            if mirrored {
                let w = r.width / CGFloat(k)
                return CGRect(x: r.minX + CGFloat(i) * w, y: r.minY, width: w, height: r.height)
            }
            let h = r.height / CGFloat(k)
            return CGRect(x: r.minX, y: r.minY + CGFloat(i) * h, width: r.width, height: h)
        }
    }

    /// The master ratio implied by a window the user resized with the mouse,
    /// or nil if this layout has no split to move (Full, Column, or the
    /// window isn't next to the split). The inverse of `tile`.
    public static func ratio(afterResizing frame: CGRect, index: Int, count n: Int, kind: LayoutKind,
                             in rect: CGRect, nMaster: Int, gap: CGFloat) -> Double? {
        guard kind == .tall || kind == .mirrorTall, nMaster > 0, n > nMaster, index >= 0, index < n else { return nil }
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        let mirrored = kind == .mirrorTall
        let start = mirrored ? area.minY : area.minX
        let length = mirrored ? area.height : area.width
        guard length > 0 else { return nil }
        // Master windows: their far edge is the split. Stack windows: their near edge.
        let edge = index < nMaster
            ? (mirrored ? frame.maxY : frame.maxX) + gap / 2
            : (mirrored ? frame.minY : frame.minX) - gap / 2
        let r = Double((edge - start) / length)
        return min(0.9, max(0.1, r))
    }
}
