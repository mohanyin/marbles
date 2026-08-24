import AppKit

/// Root overlay view. Transparent pixels (outside the placeholder circle) are not hit-tested.
/// Click-through to other apps is implemented by OverlayController toggling `ignoresMouseEvents`.
final class OverlayView: NSView {
    static let marbleSize: CGFloat = 72
    static let inset: CGFloat = 8
    static var panelSize: CGSize {
        CGSize(
            width: marbleSize + inset * 2,
            height: marbleSize + inset * 2
        )
    }

    private var dragOffset: NSPoint?
    var isDragging: Bool { dragOffset != nil }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var marbleFrame: NSRect {
        NSRect(
            x: Self.inset,
            y: Self.inset,
            width: Self.marbleSize,
            height: Self.marbleSize
        )
    }

    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        let center = NSPoint(x: marbleFrame.midX, y: marbleFrame.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return (dx * dx + dy * dy) <= (Self.marbleSize / 2) * (Self.marbleSize / 2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsInteractivePoint(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let screenPoint = NSEvent.mouseLocation
        dragOffset = NSPoint(
            x: screenPoint.x - window.frame.origin.x,
            y: screenPoint.y - window.frame.origin.y
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragOffset else { return }
        let screenPoint = NSEvent.mouseLocation
        var origin = NSPoint(
            x: screenPoint.x - dragOffset.x,
            y: screenPoint.y - dragOffset.y
        )
        if let screen = window.screen ?? NSScreen.main {
            origin = clamped(origin, size: window.frame.size, on: screen)
        }
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = marbleFrame
        let path = NSBezierPath(ovalIn: rect)

        // W0 placeholder only — Metal marbles replace this in W4.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.92, alpha: 0.92),
            NSColor(calibratedRed: 0.28, green: 0.46, blue: 0.62, alpha: 0.88),
        ])
        gradient?.draw(in: rect, angle: 90)

        let highlight = NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + rect.width * 0.18,
                y: rect.minY + rect.height * 0.52,
                width: rect.width * 0.38,
                height: rect.height * 0.32
            )
        )
        NSColor.white.withAlphaComponent(0.35).setFill()
        highlight.fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func clamped(_ origin: NSPoint, size: CGSize, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}
