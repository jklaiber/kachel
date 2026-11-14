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
}
