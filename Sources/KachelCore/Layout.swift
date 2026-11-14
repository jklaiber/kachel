import CoreGraphics

/// xmonad-style layouts. Rects are in Accessibility coordinates
/// (origin top-left of the primary display, y grows downward).
public enum Layout {
    /// `minSizes[i]` is window i's known minimum size (learned from windows
    /// that refused to get smaller); stacks give those windows at least that
    /// much and share the rest.
    public static func tile(_ kind: LayoutKind, count n: Int, in rect: CGRect,
                            nMaster: Int, ratio: Double, gap: CGFloat,
                            minSizes: [CGSize?] = []) -> [CGRect] {
        guard n > 0 else { return [] }
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        // Cells include half a gap on each side, so a window needs min + gap.
        let mins: [CGSize?] = (0..<n).map { i in
            i < minSizes.count ? minSizes[i].map { CGSize(width: $0.width + gap, height: $0.height + gap) } : nil
        }
        let cells: [CGRect]
        switch kind {
        case .full:       cells = Array(repeating: area, count: n)
        case .tall:       cells = tall(n, area, nMaster, ratio, mirrored: false, mins)
        case .mirrorTall: cells = tall(n, area, nMaster, ratio, mirrored: true, mins)
        case .column:     cells = stack(n, area, true, mins)
        }
        return cells.map { $0.insetBy(dx: gap / 2, dy: gap / 2).integral }
    }

    /// Tall: master column on the left (ratio of width), the rest stacked on the right.
    /// Mirrored: master row on top, the rest side by side below.
    static func tall(_ n: Int, _ area: CGRect, _ nMaster: Int, _ ratio: Double,
                     mirrored: Bool, _ mins: [CGSize?]) -> [CGRect] {
        let nm = max(0, nMaster)
        if nm == 0 || n <= nm { return stack(n, area, mirrored, mins) }
        let edge: CGRectEdge = mirrored ? .minYEdge : .minXEdge
        let dist = (mirrored ? area.height : area.width) * CGFloat(ratio)
        let (master, rest) = area.divided(atDistance: dist, from: edge)
        return stack(nm, master, mirrored, Array(mins[0..<nm])) + stack(n - nm, rest, mirrored, Array(mins[nm...]))
    }

    /// k windows side by side (mirrored) or on top of each other.
    static func stack(_ k: Int, _ r: CGRect, _ mirrored: Bool, _ mins: [CGSize?] = []) -> [CGRect] {
        let total = mirrored ? r.width : r.height
        let start = mirrored ? r.minX : r.minY
        return arrange(total, (0..<k).map { i in
            i < mins.count ? mins[i].map { mirrored ? $0.width : $0.height } : nil
        }).map { cell in
            mirrored
                ? CGRect(x: start + cell.offset, y: r.minY, width: cell.length, height: r.height)
                : CGRect(x: r.minX, y: start + cell.offset, width: r.width, height: cell.length)
        }
    }

    /// Where each part goes: back to back when they fit. When the minimums
    /// can't all fit, every window keeps its size and they overlap evenly,
    /// so the last one still ends at the edge (nothing hangs off screen).
    public static func arrange(_ total: CGFloat, _ mins: [CGFloat?]) -> [(offset: CGFloat, length: CGFloat)] {
        let lengths = distribute(total, mins)
        let k = lengths.count
        let overflow = max(0, lengths.reduce(0, +) - total)
        let pullBack = k > 1 ? overflow / CGFloat(k - 1) : 0
        var offset: CGFloat = 0
        return lengths.enumerated().map { i, len in
            defer { offset += len - pullBack }
            return (offset: k == 1 ? 0 : offset, length: k == 1 ? min(len, total) : len)
        }
    }

    /// Split `total` into equal parts, except that parts with a minimum get at
    /// least that (the others share what's left). If the minimums can't all
    /// fit, they keep their size, unconstrained parts get 10%, and the sum is
    /// more than `total` (arrange() overlaps them).
    public static func distribute(_ total: CGFloat, _ mins: [CGFloat?]) -> [CGFloat] {
        let k = mins.count
        guard k > 0 else { return [] }
        var fixed: [Int: CGFloat] = [:]
        while true {
            let free = (0..<k).filter { fixed[$0] == nil }
            let share = free.isEmpty ? 0 : (total - fixed.values.reduce(0, +)) / CGFloat(free.count)
            let grow = free.filter { i in mins[i].map { $0 > share } ?? false }
            if grow.isEmpty { break }
            for i in grow { fixed[i] = mins[i]! }
        }
        let free = (0..<k).filter { fixed[$0] == nil }
        let used = fixed.values.reduce(0, +)
        let floor = total * 0.1
        if used > total - floor * CGFloat(free.count) {
            return (0..<k).map { fixed[$0] ?? floor }
        }
        let share = free.isEmpty ? 0 : (total - used) / CGFloat(free.count)
        return (0..<k).map { fixed[$0] ?? share }
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
