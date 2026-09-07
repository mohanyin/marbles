import AppKit

final class IndicatorLightsView: NSView {
    var lights: [LightColor] = [.off, .off, .off] {
        didSet { needsDisplay = true }
    }

    var stackVertically = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let pad = Indicators.glowBlur
        let thickness = Indicators.lightThickness
        let gap = Indicators.lightGap
        // Lights differ in length, so walk the row rather than indexing a
        // fixed stride.
        var advance: CGFloat = 0
        for (index, light) in lights.prefix(3).enumerated() {
            let length = Indicators.length(at: index)
            let radius = Indicators.cornerRadius(at: index)
            let rect: NSRect
            if stackVertically {
                rect = NSRect(
                    x: bounds.midX - thickness / 2,
                    y: bounds.maxY - pad - advance - length,
                    width: thickness,
                    height: length
                )
            } else {
                rect = NSRect(
                    x: bounds.minX + pad + advance,
                    y: bounds.midY - thickness / 2,
                    width: length,
                    height: thickness
                )
            }
            advance += length + gap
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            if light == .off {
                NSColor(srgbRed: 0.7, green: 0.7, blue: 0.7, alpha: 0.3).setFill()
                path.fill()
            } else {
                let color = Self.color(for: light)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = Indicators.glowBlur
                shadow.shadowOffset = .zero
                shadow.shadowColor = color
                shadow.set()
                color.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                color.setFill()
                path.fill()
            }
        }
    }

    private static func color(for light: LightColor) -> NSColor {
        switch light {
        case .off:
            return NSColor(srgbRed: 0.7, green: 0.7, blue: 0.7, alpha: 0.3)
        case .white:
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .green:
            return NSColor(srgbRed: 0, green: 0xE8 / 255, blue: 0x79 / 255, alpha: 1)
        case .red:
            return NSColor(srgbRed: 0xE8 / 255, green: 0x42 / 255, blue: 0, alpha: 1)
        }
    }
}
