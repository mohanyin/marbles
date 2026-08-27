import AppKit

final class OverlayRootView: NSView {
    private var marbleViews: [AgentID: PlaceholderMarbleView] = [:]
    private var lightViews: [AgentID: IndicatorLightsView] = [:]
    private let dockGlass = DockGlassView(frame: .zero)
    private let dockContent = NSView(frame: .zero)
    private let dockMask = CAShapeLayer()
    private let metalView: MarbleMetalView?
    let metalRenderer: MarbleRenderer?
    let focusCard = FocusCardView()

    var displayedLayout: LayoutResult?
    var agentsByID: [AgentID: Agent] = [:]
    var reducedMotion = false
    private var currentMode: OverlayMode = .dock

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        if let renderer = MarbleRenderer(), renderer.isReady {
            metalRenderer = renderer
            metalView = MarbleMetalView(renderer: renderer)
        } else {
            metalRenderer = nil
            metalView = nil
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        dockContent.wantsLayer = true
        dockContent.layer?.mask = dockMask
        addSubview(dockGlass)
        addSubview(dockContent)
        if let metalView {
            metalView.autoresizingMask = [.width, .height]
            dockContent.addSubview(metalView)
        }
        focusCard.isHidden = true
        addSubview(focusCard)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(layout: LayoutResult, agents: [Agent], focused: AgentID?, mode: OverlayMode) {
        displayedLayout = layout
        currentMode = mode
        agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        dockGlass.frame = layout.dockFrame
        dockContent.frame = layout.dockFrame
        updateDockMask()

        let ids = Set(layout.frames.keys)
        for id in marbleViews.keys where !ids.contains(id) {
            marbleViews[id]?.removeFromSuperview()
            marbleViews.removeValue(forKey: id)
            lightViews[id]?.removeFromSuperview()
            lightViews.removeValue(forKey: id)
        }
        for (id, frame) in layout.frames {
            let view = marbleViews[id] ?? PlaceholderMarbleView(agent: agentsByID[id] ?? Agent.debugDummy(index: 0))
            if marbleViews[id] == nil {
                marbleViews[id] = view
                dockContent.addSubview(view)
            }
            if let agent = agentsByID[id] {
                view.agent = agent
            }
            view.drawsInterior = metalView == nil
            view.marbleSize = frame.size
            view.dim = 0
            view.now = Date()
            view.reducedMotion = reducedMotion
            view.frame = dockRect(for: frame, dock: layout.dockFrame)
        }
        submitMetal()
        layoutLights()

        if let card = layout.focusCardFrame, let id = focused, let agent = agentsByID[id] {
            focusCard.isHidden = false
            focusCard.frame = card
            focusCard.apply(agent: agent)
        } else {
            focusCard.isHidden = true
        }

        sortZ()
        needsDisplay = true
    }

    enum Hit {
        case none
        case marble(AgentID)
        case dock
        case card

        var isInteractive: Bool {
            if case .none = self { return false }
            return true
        }
    }

    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        hitTestKind(at: point).isInteractive
    }

    func hitTestKind(at point: NSPoint) -> Hit {
        if !focusCard.isHidden, focusCard.frame.contains(point) {
            return .card
        }
        if let layout = displayedLayout {
            let ordered = layout.frames.sorted { $0.value.z > $1.value.z }
            for (id, frame) in ordered {
                let dx = point.x - frame.center.x
                let dy = point.y - frame.center.y
                if (dx * dx + dy * dy) <= (frame.size / 2) * (frame.size / 2),
                   stadiumContains(point, in: layout.dockFrame)
                {
                    return .marble(id)
                }
            }
            if stadiumContains(point, in: layout.dockFrame) {
                return .dock
            }
        }
        return .none
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !focusCard.isHidden, focusCard.frame.contains(point) {
            let local = convert(point, to: focusCard)
            return focusCard.hitTest(local) ?? focusCard
        }
        if containsInteractivePoint(point) { return self }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tickMotion(agents: [Agent], reducedMotion: Bool) {
        agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let now = Date()
        for (id, view) in marbleViews {
            if let agent = agentsByID[id] {
                view.agent = agent
                view.now = now
                view.reducedMotion = reducedMotion
                view.needsDisplay = true
            }
        }
        layoutLights()
        if case .focus(let id) = currentMode, let agent = agentsByID[id], !focusCard.isHidden {
            focusCard.apply(agent: agent)
        }
        submitMetal()
    }

    private func submitMetal() {
        guard let metalView, let metalRenderer, let layout = displayedLayout else { return }
        metalView.frame = dockContent.bounds
        let now = Date()
        let items = layout.frames.compactMap { id, frame -> MarbleDrawItem? in
            guard let agent = agentsByID[id] else { return nil }
            var local = frame
            local.center = CGPoint(
                x: frame.center.x - layout.dockFrame.minX,
                y: frame.center.y - layout.dockFrame.minY
            )
            return MarbleDrawItem(agent: agent, frame: local, now: now, reducedMotion: reducedMotion)
        }
        metalRenderer.submit(items: items, viewport: dockContent.bounds.size, scale: window?.backingScaleFactor ?? 2)
        metalView.setNeedsDisplay(metalView.bounds)
    }

    private func layoutLights() {
        guard let layout = displayedLayout else { return }
        var seen = Set<AgentID>()
        for (id, frame) in layout.frames {
            guard let agent = agentsByID[id] else { continue }
            seen.insert(id)
            let view = lightViews[id] ?? IndicatorLightsView(frame: .zero)
            if lightViews[id] == nil {
                lightViews[id] = view
                dockContent.addSubview(view, positioned: .above, relativeTo: metalView ?? marbleViews[id])
            }
            let local = MarbleFrame(
                center: CGPoint(
                    x: frame.center.x - layout.dockFrame.minX,
                    y: frame.center.y - layout.dockFrame.minY
                ),
                size: frame.size,
                z: frame.z,
                dim: 0
            )
            view.stackVertically = layout.orientation.axis == .horizontal
            view.lights = Indicators.lights(for: agent, now: Date(), reducedMotion: reducedMotion)
            view.frame = Indicators.viewFrame(marble: local, orientation: layout.orientation)
            view.isHidden = false
        }
        for id in lightViews.keys where !seen.contains(id) {
            lightViews[id]?.removeFromSuperview()
            lightViews.removeValue(forKey: id)
        }
    }

    private func dockRect(for frame: MarbleFrame, dock: CGRect) -> NSRect {
        NSRect(
            x: frame.center.x - frame.size / 2 - dock.minX,
            y: frame.center.y - frame.size / 2 - dock.minY,
            width: frame.size,
            height: frame.size
        )
    }

    private func updateDockMask() {
        let bounds = dockContent.bounds
        let radius = min(bounds.width, bounds.height) / 2
        dockMask.frame = bounds
        dockMask.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func stadiumContains(_ point: CGPoint, in rect: CGRect) -> Bool {
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        return path.contains(point)
    }

    private func sortZ() {
        addSubview(dockGlass, positioned: .below, relativeTo: nil)
        addSubview(dockContent, positioned: .above, relativeTo: dockGlass)
        if let metalView {
            dockContent.addSubview(metalView, positioned: .above, relativeTo: nil)
        }
        let sorted = (displayedLayout?.frames ?? [:]).sorted { $0.value.z < $1.value.z }
        for (id, _) in sorted {
            if let view = marbleViews[id] {
                dockContent.addSubview(view, positioned: .above, relativeTo: nil)
            }
        }
        for view in lightViews.values {
            dockContent.addSubview(view, positioned: .above, relativeTo: nil)
        }
        addSubview(focusCard, positioned: .above, relativeTo: nil)
    }
}
