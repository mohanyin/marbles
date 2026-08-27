import AppKit

enum LineAxis: Equatable {
    case horizontal
    case vertical
}

struct LineOrientation: Equatable {
    var axis: LineAxis
    /// True = increasing index goes +X (horizontal) or +Y (vertical).
    var indexIncreasesAlongPositive: Bool
}

enum SnapGeometry {
    static let inset: CGFloat = 12

    static func safeFrame(of screen: NSScreen) -> NSRect {
        screen.visibleFrame.insetBy(dx: inset, dy: inset)
    }

    static func panelOrigin(snap: SnapState, panelSize: CGSize, screen: NSScreen) -> CGPoint {
        panelOrigin(snap: snap, panelSize: panelSize, safe: safeFrame(of: screen), screenOrigin: screen.frame.origin)
    }

    static func panelOrigin(snap: SnapState, panelSize: CGSize, safe: NSRect, screenOrigin: CGPoint = .zero) -> CGPoint {
        switch snap {
        case .snap(let point):
            return origin(for: point, size: panelSize, safe: safe)
        case .free(let x, let y):
            var origin = CGPoint(x: screenOrigin.x + CGFloat(x), y: screenOrigin.y + CGFloat(y))
            origin.x = min(max(origin.x, safe.minX), safe.maxX - panelSize.width)
            origin.y = min(max(origin.y, safe.minY), safe.maxY - panelSize.height)
            return origin
        }
    }

    /// Place the dock at the snap midpoint. Panel origin is derived from the dock frame.
    static func panelOrigin(snap: SnapState, dockFrame: CGRect, panelSize: CGSize, screen: NSScreen) -> CGPoint {
        panelOrigin(snap: snap, dockFrame: dockFrame, panelSize: panelSize, safe: safeFrame(of: screen))
    }

    static func panelOrigin(snap: SnapState, dockFrame: CGRect, panelSize: CGSize, safe: NSRect) -> CGPoint {
        let dockOrigin = panelOrigin(snap: snap, panelSize: dockFrame.size, safe: safe)
        return CGPoint(x: dockOrigin.x - dockFrame.minX, y: dockOrigin.y - dockFrame.minY)
    }

    static func resolveRelease(panelFrame: NSRect, screen: NSScreen) -> SnapState {
        resolveRelease(panelFrame: panelFrame, safe: safeFrame(of: screen))
    }

    static func resolveRelease(panelFrame: NSRect, safe: NSRect) -> SnapState {
        .snap(nearestPoint(panelOrigin: panelFrame.origin, panelSize: panelFrame.size, safe: safe))
    }

    static func resolveDockRelease(dockFrame: NSRect, screen: NSScreen) -> SnapState {
        .snap(nearestPoint(panelOrigin: dockFrame.origin, panelSize: dockFrame.size, safe: safeFrame(of: screen)))
    }

    static func lineOrientation(snap: SnapState, panelOrigin: CGPoint, panelSize: CGSize, screen: NSScreen) -> LineOrientation {
        switch snap {
        case .snap(let point):
            return orientation(for: point)
        case .free:
            return orientation(for: nearestPoint(panelOrigin: panelOrigin, panelSize: panelSize, screen: screen))
        }
    }

    static func nearestPoint(panelOrigin: CGPoint, panelSize: CGSize, screen: NSScreen) -> SnapPoint {
        nearestPoint(panelOrigin: panelOrigin, panelSize: panelSize, safe: safeFrame(of: screen))
    }

    static func nearestPoint(panelOrigin: CGPoint, panelSize: CGSize, safe: NSRect) -> SnapPoint {
        var best: (SnapPoint, CGFloat)?
        for point in SnapPoint.allCases {
            let target = origin(for: point, size: panelSize, safe: safe)
            let distance = hypot(panelOrigin.x - target.x, panelOrigin.y - target.y)
            if best == nil || distance < best!.1 {
                best = (point, distance)
            }
        }
        return best?.0 ?? .right
    }

    static func orientation(for point: SnapPoint) -> LineOrientation {
        switch point {
        case .left, .right:
            // Insertion order starts at the top of a vertical dock.
            return LineOrientation(axis: .vertical, indexIncreasesAlongPositive: false)
        case .top, .bottom:
            return LineOrientation(axis: .horizontal, indexIncreasesAlongPositive: true)
        }
    }

    static func origin(for point: SnapPoint, size: CGSize, safe: NSRect) -> CGPoint {
        let xLeft = safe.minX
        let xRight = safe.maxX - size.width
        let xMid = safe.midX - size.width / 2
        let yBottom = safe.minY
        let yTop = safe.maxY - size.height
        let yMid = safe.midY - size.height / 2

        switch point {
        case .top: return CGPoint(x: xMid, y: yTop)
        case .left: return CGPoint(x: xLeft, y: yMid)
        case .right: return CGPoint(x: xRight, y: yMid)
        case .bottom: return CGPoint(x: xMid, y: yBottom)
        }
    }

    static func cardTowardPositive(for point: SnapPoint) -> Bool {
        switch point {
        case .left, .bottom: return true
        case .right, .top: return false
        }
    }
}
