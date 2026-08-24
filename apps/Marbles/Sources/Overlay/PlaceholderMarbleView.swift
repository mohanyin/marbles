import AppKit

final class PlaceholderMarbleView: NSView {
    var agent: Agent {
        didSet { needsDisplay = true }
    }

    var marbleSize: CGFloat = 36 {
        didSet { needsDisplay = true }
    }

    var dim: CGFloat = 0 {
        didSet { alphaValue = 1 - dim * 0.55 }
    }

    init(agent: Agent) {
        self.agent = agent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        color(for: agent.seed).setFill()
        path.fill()

        let highlight = NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + rect.width * 0.18,
                y: rect.minY + rect.height * 0.52,
                width: rect.width * 0.38,
                height: rect.height * 0.32
            )
        )
        NSColor.white.withAlphaComponent(0.32).setFill()
        highlight.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func color(for seed: UInt64) -> NSColor {
        let hue = CGFloat(seed % 360) / 360
        return NSColor(calibratedHue: hue, saturation: 0.48, brightness: 0.86, alpha: 0.94)
    }
}

final class OverflowMarbleView: NSView {
    var hiddenCount: Int = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor.black.withAlphaComponent(0.55).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.stroke()

        let text = "+\(hiddenCount)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )
    }
}

final class FocusCardView: NSView {
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    var detail: String = "" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let titleRect = NSRect(x: 14, y: bounds.height - 40, width: bounds.width - 28, height: 22)
        (title as NSString).draw(in: titleRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])

        let bodyRect = NSRect(x: 14, y: 12, width: bounds.width - 28, height: bounds.height - 56)
        (detail as NSString).draw(in: bodyRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}
