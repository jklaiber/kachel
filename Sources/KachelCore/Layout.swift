import CoreGraphics

/// xmonad-style layouts. Rects are in Accessibility coordinates
/// (origin top-left of the primary display, y grows downward).
///
/// Every layout is a set of groups: a column (or row) of windows that share
/// its length by weight (xmonad's ResizableTall), with learned minimum sizes
/// honoured. Tall = master column + stack column, Wide = rows, Column = one
/// row, Three-column = master in the middle and a stack on each side.
public enum Layout {
    /// One group: windows `range` share `rect` along y (or x when `sideways`).
    struct Group {
        var range: Range<Int>
        var rect: CGRect
        var sideways: Bool
    }

    /// - minSizes: window i's known minimum size (learned from windows that
    ///   refused to get smaller); groups give those windows at least that.
    /// - weights: window i's share in its group, 1 = normal (ResizableTall).
    public static func tile(_ kind: LayoutKind, count n: Int, in rect: CGRect,
                            nMaster: Int, ratio: Double, gap: CGFloat,
                            minSizes: [CGSize?] = [], weights: [Double] = []) -> [CGRect] {
        guard n > 0 else { return [] }
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        if kind == .full {
            return Array(repeating: area.insetBy(dx: gap / 2, dy: gap / 2).integral, count: n)
        }
        var cells = [CGRect](repeating: .zero, count: n)
        for g in groups(kind, n, area, nMaster, ratio) {
            // Cells include half a gap on each side, so a window needs min + gap.
            let mins: [CGFloat?] = g.range.map { i in
                guard i < minSizes.count, let m = minSizes[i] else { return nil }
                return (g.sideways ? m.width : m.height) + gap
            }
            let w: [Double] = g.range.map { i in i < weights.count ? max(0.05, weights[i]) : 1 }
            let total = g.sideways ? g.rect.width : g.rect.height
            let start = g.sideways ? g.rect.minX : g.rect.minY
            for (i, cell) in zip(g.range, arrange(total, mins, weights: w)) {
                cells[i] = g.sideways
                    ? CGRect(x: start + cell.offset, y: g.rect.minY, width: cell.length, height: g.rect.height)
                    : CGRect(x: g.rect.minX, y: start + cell.offset, width: g.rect.width, height: cell.length)
            }
        }
        return cells.enumerated().map { i, c in
            var r = c.insetBy(dx: gap / 2, dy: gap / 2)
            // A window can't be smaller than its minimum, across the group
            // either (e.g. too wide for a side column): it grows towards the
            // middle and is kept inside the screen instead of hanging off it.
            if i < minSizes.count, let m = minSizes[i] {
                let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
                if m.width > r.width {
                    let w = min(m.width, inner.width)
                    r.origin.x = min(max(r.midX - w / 2, inner.minX), inner.maxX - w)
                    r.size.width = w
                }
                if m.height > r.height {
                    let h = min(m.height, inner.height)
                    r.origin.y = min(max(r.midY - h / 2, inner.minY), inner.maxY - h)
                    r.size.height = h
                }
            }
            return r.integral
        }
    }

    static func groups(_ kind: LayoutKind, _ n: Int, _ area: CGRect, _ nMaster: Int, _ ratio: Double) -> [Group] {
        let nm = max(0, nMaster)
        switch kind {
        case .full:
            return []
        case .column:
            return [Group(range: 0..<n, rect: area, sideways: true)]
        case .tall, .mirrorTall:
            let sideways = kind == .mirrorTall
            if nm == 0 || n <= nm { return [Group(range: 0..<n, rect: area, sideways: sideways)] }
            let edge: CGRectEdge = sideways ? .minYEdge : .minXEdge
            let dist = (sideways ? area.height : area.width) * CGFloat(ratio)
            let (master, rest) = area.divided(atDistance: dist, from: edge)
            return [Group(range: 0..<nm, rect: master, sideways: sideways),
                    Group(range: nm..<n, rect: rest, sideways: sideways)]
        case .threeColumn:
            let m = max(1, nm)
            if n <= m { return [Group(range: 0..<n, rect: area, sideways: false)] }
            if n == m + 1 { return groups(.tall, n, area, m, ratio) }        // two windows: like Tall
            let masterW = area.width * CGFloat(ratio)
            let sideW = (area.width - masterW) / 2
            let left = CGRect(x: area.minX, y: area.minY, width: sideW, height: area.height)
            let master = CGRect(x: area.minX + sideW, y: area.minY, width: masterW, height: area.height)
            let right = CGRect(x: master.maxX, y: area.minY, width: sideW, height: area.height)
            let rest = n - m
            let rightCount = (rest + 1) / 2                                   // right gets the odd one
            return [Group(range: 0..<m, rect: master, sideways: false),
                    Group(range: m..<(m + rightCount), rect: right, sideways: false),
                    Group(range: (m + rightCount)..<n, rect: left, sideways: false)]
        }
    }

    /// Where each part goes: back to back when they fit. When the minimums
    /// can't all fit, every window keeps its size and they overlap evenly,
    /// so the last one still ends at the edge (nothing hangs off screen).
    public static func arrange(_ total: CGFloat, _ mins: [CGFloat?], weights: [Double] = [])
        -> [(offset: CGFloat, length: CGFloat)] {
        let lengths = distribute(total, mins, weights: weights)
        let k = lengths.count
        let overflow = max(0, lengths.reduce(0, +) - total)
        let pullBack = k > 1 ? overflow / CGFloat(k - 1) : 0
        var offset: CGFloat = 0
        return lengths.map { len in
            defer { offset += len - pullBack }
            return (offset: k == 1 ? 0 : offset, length: k == 1 ? min(len, total) : len)
        }
    }

    /// Split `total` by weight (equal when no weights), except that parts with
    /// a minimum get at least that and the others share what's left. If the
    /// minimums can't all fit, they keep their size, unconstrained parts get
    /// 10%, and the sum is more than `total` (arrange() overlaps them).
    public static func distribute(_ total: CGFloat, _ mins: [CGFloat?], weights: [Double] = []) -> [CGFloat] {
        let k = mins.count
        guard k > 0 else { return [] }
        let w = (0..<k).map { i in CGFloat(i < weights.count ? weights[i] : 1) }
        var fixed: [Int: CGFloat] = [:]
        func shares() -> [Int: CGFloat] {
            let free = (0..<k).filter { fixed[$0] == nil }
            let rest = total - fixed.values.reduce(0, +)
            let sum = free.reduce(CGFloat(0)) { $0 + w[$1] }
            return Dictionary(uniqueKeysWithValues: free.map { ($0, sum > 0 ? rest * w[$0] / sum : 0) })
        }
        while true {
            let s = shares()
            let grow = s.keys.filter { i in mins[i].map { $0 > s[i]! } ?? false }
            if grow.isEmpty { break }
            for i in grow { fixed[i] = mins[i]! }
        }
        let free = (0..<k).filter { fixed[$0] == nil }
        let floor = total * 0.1
        if fixed.values.reduce(0, +) > total - floor * CGFloat(free.count) {
            return (0..<k).map { fixed[$0] ?? floor }
        }
        let s = shares()
        return (0..<k).map { fixed[$0] ?? s[$0]! }
    }

    /// The master ratio implied by a window the user resized with the mouse,
    /// or nil if this layout has no split to move (Full, Column, or a single
    /// group). The inverse of `tile`.
    public static func ratio(afterResizing frame: CGRect, index: Int, count n: Int, kind: LayoutKind,
                             in rect: CGRect, nMaster: Int, gap: CGFloat) -> Double? {
        guard index >= 0, index < n else { return nil }
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        let clamp = { (r: CGFloat) -> Double in min(0.9, max(0.1, Double(r))) }
        switch kind {
        case .full, .column:
            return nil
        case .tall, .mirrorTall:
            guard nMaster > 0, n > nMaster else { return nil }
            let sideways = kind == .mirrorTall
            let start = sideways ? area.minY : area.minX
            let length = sideways ? area.height : area.width
            guard length > 0 else { return nil }
            // Master windows: their far edge is the split. Stack windows: their near edge.
            let edge = index < nMaster
                ? (sideways ? frame.maxY : frame.maxX) + gap / 2
                : (sideways ? frame.minY : frame.minX) - gap / 2
            return clamp((edge - start) / length)
        case .threeColumn:
            let m = max(1, nMaster)
            guard n > m, area.width > 0 else { return nil }
            if n == m + 1 {
                return ratio(afterResizing: frame, index: index, count: n, kind: .tall, in: rect, nMaster: m, gap: gap)
            }
            let rightCount = (n - m + 1) / 2
            // Half the master width, measured from the centre.
            let half: CGFloat
            if index < m { half = (frame.width + gap) / 2 }
            else if index < m + rightCount { half = frame.minX - gap / 2 - area.midX }
            else { half = area.midX - (frame.maxX + gap / 2) }
            return clamp(2 * half / area.width)
        }
    }

    /// New weights after the user resized window `index` along its group
    /// (e.g. made a stack window taller), or nil if it has no neighbours in
    /// its group to trade space with.
    public static func weights(afterResizing frame: CGRect, index: Int, count n: Int, kind: LayoutKind,
                               in rect: CGRect, nMaster: Int, ratio: Double, gap: CGFloat,
                               weights current: [Double]) -> [Double]? {
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)
        guard let g = groups(kind, n, area, nMaster, ratio).first(where: { $0.range.contains(index) }),
              g.range.count > 1 else { return nil }
        var w = (0..<n).map { $0 < current.count ? current[$0] : 1 }
        let total = g.sideways ? g.rect.width : g.rect.height
        guard total > 0 else { return nil }
        let p = min(0.95, max(0.05, ((g.sideways ? frame.width : frame.height) + gap) / total))
        let others = g.range.filter { $0 != index }.reduce(0.0) { $0 + w[$1] }
        w[index] = min(20, max(0.05, Double(p / (1 - p)) * others))
        return w
    }
}
