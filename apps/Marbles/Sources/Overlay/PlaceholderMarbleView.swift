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

    var reducedMotion = false
    var now = Date()
    var drawsInterior = true

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
        guard drawsInterior else { return }
        let uniforms = MotionEngine.uniforms(for: agent, now: now, reducedMotion: reducedMotion, dim: dim)
        let rect = bounds
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        fillColor(uniforms: uniforms).setFill()
        path.fill()
        drawSwirl(in: rect, uniforms: uniforms)
        drawHighlight(in: rect)
        if uniforms.bloom > 0 {
            drawBloom(in: rect, uniforms: uniforms)
        }
        NSGraphicsContext.restoreGraphicsState()

        rimColor(uniforms: uniforms).setStroke()
        path.lineWidth = 1 + CGFloat(uniforms.rimBoost) * 3 + CGFloat(uniforms.attention) * 1.5
        path.stroke()
    }

    private func fillColor(uniforms: MarbleFrameUniforms) -> NSColor {
        let params = Identity.params(seed: agent.seed)
        var color = NSColor(
            calibratedHue: CGFloat(params.hue),
            saturation: CGFloat(params.saturation) * 0.85,
            brightness: CGFloat(0.52 + params.luminosity * 0.42),
            alpha: 0.94
        )
        if uniforms.errorHue > 0 {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let towardRed = h > 0.5 ? h + (1 - h) * CGFloat(uniforms.errorHue) : h * (1 - CGFloat(uniforms.errorHue))
            color = NSColor(
                calibratedHue: towardRed.truncatingRemainder(dividingBy: 1),
                saturation: min(1, s + 0.25 * CGFloat(uniforms.errorHue)),
                brightness: b,
                alpha: a
            )
        }
        if uniforms.freeze > 0, uniforms.errorHue == 0 {
            color = color.blended(withFraction: 0.08, of: .white) ?? color
        }
        return color
    }

    private func drawSwirl(in rect: NSRect, uniforms: MarbleFrameUniforms) {
        let motion = max(uniforms.advection, uniforms.hold > 0 ? 0.12 : 0)
        guard motion > 0 || uniforms.pulse > 0 else { return }
        let angle = CGFloat(uniforms.time) * (0.9 + CGFloat(uniforms.advection))
        for band in 0..<3 {
            let spin = angle + CGFloat(band) * 0.7
            let inset = rect.insetBy(dx: rect.width * (0.12 + CGFloat(band) * 0.08), dy: rect.height * (0.18 + CGFloat(band) * 0.04))
            var transform = AffineTransform()
            transform.translate(x: rect.midX, y: rect.midY)
            transform.rotate(byRadians: spin)
            transform.scale(x: 1.15, y: 0.42)
            transform.translate(x: -rect.midX, y: -rect.midY)
            let swirl = NSBezierPath(ovalIn: inset)
            swirl.transform(using: transform)
            NSColor.white.withAlphaComponent(0.10 + 0.07 * CGFloat(motion)).setFill()
            swirl.fill()
        }
    }

    private func drawHighlight(in rect: NSRect) {
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
    }

    private func drawBloom(in rect: NSRect, uniforms: MarbleFrameUniforms) {
        let sweep = CGFloat(uniforms.bloom) * .pi * 1.6
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width * 0.38,
            startAngle: 200,
            endAngle: 200 + sweep * 180 / .pi,
            clockwise: false
        )
        arc.lineWidth = 3
        NSColor.white.withAlphaComponent(0.25 + 0.55 * CGFloat(uniforms.bloom)).setStroke()
        arc.stroke()
        NSColor.white.withAlphaComponent(0.12 * CGFloat(uniforms.bloom)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
    }

    private func rimColor(uniforms: MarbleFrameUniforms) -> NSColor {
        if uniforms.errorHue > 0.2 {
            return NSColor.systemRed.withAlphaComponent(0.55 + 0.45 * CGFloat(uniforms.errorHue))
        }
        if uniforms.attention > 0 {
            return NSColor.systemYellow.withAlphaComponent(0.45 + 0.55 * CGFloat(uniforms.attention))
        }
        if uniforms.rimBoost > 0 {
            return NSColor.white.withAlphaComponent(0.55 + CGFloat(uniforms.rimBoost))
        }
        if uniforms.advection > 0.7 {
            return NSColor.white.withAlphaComponent(0.7)
        }
        return NSColor.white.withAlphaComponent(0.5)
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
