import AppKit

/// The enlarged marble that protrudes off the top of the Focus card.
///
/// `MarbleRenderer` keeps one shared instance buffer that `submit()` replaces wholesale, so
/// this cannot share the dock's renderer — it gets its own, and falls back to the CoreGraphics
/// marble when Metal is unavailable, mirroring `OverlayRootView`'s `drawsInterior` split.
final class FocusMarbleView: NSView {
    private let renderer: MarbleRenderer?
    private let metalView: MarbleMetalView?
    private let placeholder: PlaceholderMarbleView?

    private(set) var agent: Agent?

    var reducedMotion = false

    override init(frame frameRect: NSRect) {
        if let renderer = MarbleRenderer(), renderer.isReady {
            self.renderer = renderer
            metalView = MarbleMetalView(renderer: renderer)
            placeholder = nil
        } else {
            renderer = nil
            metalView = nil
            let view = PlaceholderMarbleView(agent: Agent.debugDummy(index: 0))
            view.drawsInterior = true
            placeholder = view
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        if let metalView {
            metalView.autoresizingMask = [.width, .height]
            metalView.frame = bounds
            addSubview(metalView)
        }
        if let placeholder {
            placeholder.autoresizingMask = [.width, .height]
            placeholder.frame = bounds
            addSubview(placeholder)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Hover classification and clicks belong to the card, not the marble.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
        placeholder?.frame = bounds
        submit(now: Date())
    }

    /// Driven by the overlay's motion clock. The agent has to be re-supplied every tick: the
    /// shader's time comes from `agent.animationTime`, which the store advances frame by frame,
    /// so holding a stale copy freezes the marble until the next `apply` and makes it jump.
    func tick(agent: Agent, now: Date, reducedMotion: Bool) {
        self.agent = agent
        self.reducedMotion = reducedMotion
        placeholder?.agent = agent
        placeholder?.now = now
        placeholder?.reducedMotion = reducedMotion
        placeholder?.needsDisplay = true
        submit(now: now)
    }

    private func submit(now: Date) {
        guard let renderer, let metalView, let agent, bounds.width > 0, bounds.height > 0 else {
            return
        }
        let size = min(bounds.width, bounds.height)
        let item = MarbleDrawItem(
            agent: agent,
            frame: MarbleFrame(
                center: CGPoint(x: bounds.midX, y: bounds.midY),
                size: size,
                z: 0,
                dim: 0
            ),
            now: now,
            reducedMotion: reducedMotion
        )
        renderer.submit(
            items: [item],
            viewport: bounds.size,
            scale: window?.backingScaleFactor ?? 2
        )
        metalView.setNeedsDisplay(metalView.bounds)
    }
}
