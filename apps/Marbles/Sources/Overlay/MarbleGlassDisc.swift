import AppKit

/// Adaptive stadium glass for the default dock. No extra stroke; macOS glass draws the rim.
final class DockGlassView: NSView {
    private let glass: NSView

    override init(frame frameRect: NSRect) {
        #if compiler(>=6.2) // Xcode 26 / macOS 26 SDK
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView(frame: frameRect)
            view.style = .regular
            view.cornerRadius = min(frameRect.width, frameRect.height) / 2
            glass = view
        } else {
            let view = NSVisualEffectView(frame: frameRect)
            view.material = .hudWindow
            view.blendingMode = .behindWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = min(frameRect.width, frameRect.height) / 2
            view.layer?.masksToBounds = true
            glass = view
        }
        #else
        let view = NSVisualEffectView(frame: frameRect)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = min(frameRect.width, frameRect.height) / 2
        view.layer?.masksToBounds = true
        glass = view
        #endif
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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
        let radius = min(bounds.width, bounds.height) / 2
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            (glass as? NSGlassEffectView)?.cornerRadius = radius
        } else {
            glass.layer?.cornerRadius = radius
        }
        #else
        glass.layer?.cornerRadius = radius
        #endif
    }
}
