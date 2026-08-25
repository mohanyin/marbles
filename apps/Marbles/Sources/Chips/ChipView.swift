import AppKit

final class ChipView: NSView {
    var kind: ChipKind = .thinking {
        didSet { needsDisplay = true }
    }

    var fade: CGFloat = 1 {
        didSet { alphaValue = fade }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds)
        NSColor.black.withAlphaComponent(0.55).setFill()
        circle.fill()

        let pointSize = max(10, bounds.width * 0.62)
        let symbol = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
        let sized = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let colored = sized.applying(.init(hierarchicalColor: .white))
        guard let image = symbol?.withSymbolConfiguration(colored) else { return }
        let inset = bounds.width * 0.18
        let box = bounds.insetBy(dx: inset, dy: inset)
        let native = image.size
        guard native.width > 0, native.height > 0 else { return }
        let scale = min(box.width / native.width, box.height / native.height)
        let drawSize = NSSize(width: native.width * scale, height: native.height * scale)
        let dest = NSRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(
            in: dest,
            from: NSRect(origin: .zero, size: native),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
