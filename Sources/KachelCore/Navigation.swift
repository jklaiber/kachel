import CoreGraphics

public enum Direction: String, CaseIterable {
    case left, right, up, down
}

/// Which window is "to the left" (etc.) of another, across screens, like
/// xmonad's Navigation2D or i3/AeroSpace focus left. Frames are in AX
/// coordinates (y grows downward).
public enum Navigation {
    public static func neighbour(of from: CGRect, in direction: Direction,
                                 among candidates: [(id: WindowID, frame: CGRect)]) -> WindowID? {
        var best: (id: WindowID, score: CGFloat)?
        for c in candidates where c.frame != from {
            let f = c.frame
            // How far it lies in the wanted direction (edge to edge, small
            // overlaps from gaps allowed) and how far off to the side.
            let ahead: CGFloat, overlap: CGFloat, side: CGFloat
            switch direction {
            case .left:  ahead = from.minX - f.maxX
            case .right: ahead = f.minX - from.maxX
            case .up:    ahead = from.minY - f.maxY
            case .down:  ahead = f.minY - from.maxY
            }
            guard ahead > -40 else { continue }            // not in that direction
            switch direction {
            case .left, .right:
                overlap = min(from.maxY, f.maxY) - max(from.minY, f.minY)
                side = abs(f.midY - from.midY)
            case .up, .down:
                overlap = min(from.maxX, f.maxX) - max(from.minX, f.minX)
                side = abs(f.midX - from.midX)
            }
            // Windows that line up with this one win; then the nearest.
            let score = max(0, ahead) + (overlap > 0 ? side * 0.1 : side * 2 + 10_000)
            if best == nil || score < best!.score { best = (c.id, score) }
        }
        return best?.id
    }
}
