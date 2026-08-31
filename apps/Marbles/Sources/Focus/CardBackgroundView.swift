import AppKit

/// Light/dark aware ink for the Focus card. White on dark, black on light — resolved
/// against the drawing appearance, so nothing may force an appearance on the panel.
enum CardPalette {
    static let ink = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? .white : .black
    }

    /// Opaque panel fill for the pre-macOS 26 background.
    static let panel = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    }

    static var hairline: NSColor { ink.withAlphaComponent(0.2) }
    static var promptFill: NSColor { ink.withAlphaComponent(0.2) }
    static var promptText: NSColor { ink.withAlphaComponent(0.8) }
    static var responseText: NSColor { ink.withAlphaComponent(0.95) }
    static var scrollKnob: NSColor { ink.withAlphaComponent(0.35) }
}

/// Rounded card background: system glass on macOS 26, a flat adaptive panel before it.
///
/// The fallback is deliberately *not* `NSVisualEffectView` — a `.behindWindow` material is
/// composited by the window server and isn't clipped by `layer.cornerRadius`, so a blurred
/// card would have square corners on macOS 14/15.
final class CardBackgroundView: NSView {
    private let radius: CGFloat
    private var glass: NSView?

    init(cornerRadius: CGFloat) {
        self.radius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true

        #if compiler(>=6.2) // Xcode 26 / macOS 26 SDK
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView(frame: .zero)
            view.style = .regular
            view.cornerRadius = cornerRadius
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            glass = view
            return
        }
        #endif

        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        updateFlatFill()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        glass?.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFlatFill()
    }

    private func updateFlatFill() {
        guard glass == nil else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CardPalette.panel.cgColor
        }
    }
}
