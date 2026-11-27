import CoreGraphics

/// A small picture of each layout, for the bar (and the same shapes as the
/// website's layout cards): four windows in a unit square, y down.
public enum LayoutIcon {
    public enum Role: Equatable { case master, window, behind }
    public struct Cell: Equatable {
        public var rect: CGRect
        public var role: Role
    }

    /// - portrait: the display is taller than wide (two-pane splits top and bottom there).
    public static func cells(_ kind: LayoutKind, portrait: Bool = false) -> [Cell] {
        func c(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ role: Role = .window) -> Cell {
            Cell(rect: CGRect(x: x, y: y, width: w, height: h), role: role)
        }
        let third: CGFloat = 1 / 3
        switch kind {
        case .tall:
            return [c(0, 0, 0.5, 1, .master), c(0.5, 0, 0.5, third), c(0.5, third, 0.5, third), c(0.5, 2 * third, 0.5, third)]
        case .tallRight:
            return [c(0.5, 0, 0.5, 1, .master), c(0, 0, 0.5, third), c(0, third, 0.5, third), c(0, 2 * third, 0.5, third)]
        case .mirrorTall:
            return [c(0, 0, 1, 0.5, .master), c(0, 0.5, third, 0.5), c(third, 0.5, third, 0.5), c(2 * third, 0.5, third, 0.5)]
        case .widescreenTall:
            return [c(0, 0, 0.3, 1, .master), c(0.3, 0, 0.3, 1, .master), c(0.6, 0, 0.4, 0.5), c(0.6, 0.5, 0.4, 0.5)]
        case .threeColumn:
            return [c(0.25, 0, 0.5, 1, .master), c(0.75, 0, 0.25, 0.5), c(0.75, 0.5, 0.25, 0.5), c(0, 0, 0.25, 1)]
        case .twoPane:
            // The other windows wait behind the second pane.
            return portrait
                ? [c(0.1, 0.5, 0.8, 0.5, .behind), c(0, 0, 1, 0.5, .master), c(0, 0.62, 1, 0.38)]
                : [c(0.58, 0, 0.42, 1, .behind), c(0, 0, 0.5, 1, .master), c(0.5, 0.2, 0.5, 0.8)]
        case .column:
            return (0..<4).map { c(CGFloat($0) * 0.25, 0, 0.25, 1, $0 == 0 ? .master : .window) }
        case .row:
            return (0..<4).map { c(0, CGFloat($0) * 0.25, 1, 0.25, $0 == 0 ? .master : .window) }
        case .bsp:
            return [c(0, 0, 0.5, 1, .master), c(0.5, 0, 0.5, 0.5), c(0.5, 0.5, 0.25, 0.5), c(0.75, 0.5, 0.25, 0.5)]
        case .full:
            return [c(0.12, 0, 0.76, 1, .behind), c(0, 0.24, 1, 0.76, .master)]
        case .floating:
            return [c(0.42, 0.3, 0.55, 0.62), c(0.2, 0.55, 0.38, 0.45), c(0, 0, 0.55, 0.6, .master)]
        }
    }
}
