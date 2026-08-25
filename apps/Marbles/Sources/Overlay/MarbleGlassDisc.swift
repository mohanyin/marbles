import AppKit

/// Circular system glass seated under a marble. Sized smaller than the sphere
/// so the material rim stays inside the painted disc instead of halo-ing it.
final class MarbleGlassDisc: NSView {
    private let glass: NSView
    private let maskLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView(frame: frameRect)
            view.style = .clear
            view.cornerRadius = min(frameRect.width, frameRect.height) / 2
            glass = view
        } else {
            glass = NSView(frame: frameRect)
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = maskLayer
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        glass.frame = bounds
        if #available(macOS 26.0, *) {
            (glass as? NSGlassEffectView)?.cornerRadius = min(bounds.width, bounds.height) / 2
        }
        maskLayer.frame = bounds
        maskLayer.path = CGPath(ellipseIn: bounds, transform: nil)
    }
}
