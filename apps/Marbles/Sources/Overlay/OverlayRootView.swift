import AppKit

final class OverlayRootView: NSView {
    private var marbleViews: [AgentID: PlaceholderMarbleView] = [:]
    private var glassViews: [AgentID: MarbleGlassDisc] = [:]
    private var chipViews: [String: ChipView] = [:]
    private let overflowView = OverflowMarbleView()
    private let metalView: MarbleMetalView?
    let metalRenderer: MarbleRenderer?
    let focusCard = FocusCardView()

    var displayedLayout: LayoutResult?
    var agentsByID: [AgentID: Agent] = [:]
    /// Active/Focus: clicks on empty panel chrome dismiss instead of falling through.
    var capturesEmptyClicks = false
    var reducedMotion = false
    private var currentMode: OverlayMode = .cluster

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
        overflowView.isHidden = true
        focusCard.isHidden = true
        if let metalView {
            metalView.autoresizingMask = [.width, .height]
            addSubview(metalView, positioned: .below, relativeTo: nil)
        }
        addSubview(overflowView)
        addSubview(focusCard)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(layout: LayoutResult, agents: [Agent], focused: AgentID?, mode: OverlayMode) {
        displayedLayout = layout
        currentMode = mode
        agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        let ids = Set(layout.frames.keys)
        for id in marbleViews.keys where !ids.contains(id) {
            marbleViews[id]?.removeFromSuperview()
            marbleViews.removeValue(forKey: id)
            glassViews[id]?.removeFromSuperview()
            glassViews.removeValue(forKey: id)
        }
        for (id, frame) in layout.frames {
            let view = marbleViews[id] ?? PlaceholderMarbleView(agent: agentsByID[id] ?? Agent.debugDummy(index: 0))
            if marbleViews[id] == nil {
                marbleViews[id] = view
                addSubview(view, positioned: .below, relativeTo: overflowView)
            }
            if let agent = agentsByID[id] {
                view.agent = agent
            }
            view.drawsInterior = metalView == nil
            view.marbleSize = frame.size
            view.dim = frame.dim
            view.now = Date()
            view.reducedMotion = reducedMotion
            view.frame = rect(for: frame)
            let glass = glassViews[id] ?? MarbleGlassDisc(frame: .zero)
            if glassViews[id] == nil {
                glassViews[id] = glass
                if let metalView {
                    addSubview(glass, positioned: .below, relativeTo: metalView)
                } else {
                    addSubview(glass, positioned: .below, relativeTo: view)
                }
            }
            glass.frame = glassRect(for: frame)
            glass.isHidden = false
        }
        submitMetal()
        layoutChips(mode: mode, focused: focused)

        if let overflow = layout.overflow, let frame = layout.overflowFrame {
            overflowView.isHidden = false
            overflowView.hiddenCount = overflow.hiddenCount
            overflowView.frame = rect(for: frame)
        } else {
            overflowView.isHidden = true
        }

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
        case overflow
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
        if !overflowView.isHidden {
            let frame = overflowView.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)
            if hypot(point.x - center.x, point.y - center.y) <= frame.width / 2 {
                return .overflow
            }
        }
        if let layout = displayedLayout {
            for (key, chip) in chipViews where !chip.isHidden {
                let dx = point.x - chip.frame.midX
                let dy = point.y - chip.frame.midY
                if (dx * dx + dy * dy) <= (chip.frame.width / 2) * (chip.frame.width / 2),
                   let id = key.split(separator: "#").first {
                    return .marble(String(id))
                }
            }
            let ordered = layout.frames.sorted { $0.value.z > $1.value.z }
            for (id, frame) in ordered {
                let dx = point.x - frame.center.x
                let dy = point.y - frame.center.y
                if (dx * dx + dy * dy) <= (frame.size / 2) * (frame.size / 2) {
                    return .marble(id)
                }
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
        if capturesEmptyClicks, bounds.contains(point) { return self }
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
        layoutChips(mode: currentMode, focused: currentMode.focusedAgentID)
        if case .focus(let id) = currentMode, let agent = agentsByID[id], !focusCard.isHidden {
            focusCard.apply(agent: agent)
        }
        submitMetal()
    }

    private func submitMetal() {
        guard let metalView, let metalRenderer, let layout = displayedLayout else { return }
        metalView.frame = bounds
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = Date()
        let items = layout.frames.compactMap { id, frame -> MarbleDrawItem? in
            guard let agent = agentsByID[id] else { return nil }
            return MarbleDrawItem(agent: agent, frame: frame, now: now, reducedMotion: reduced)
        }
        metalRenderer.submit(items: items, viewport: bounds.size, scale: window?.backingScaleFactor ?? 2)
        metalView.setNeedsDisplay(metalView.bounds)
    }

    private func layoutChips(mode: OverlayMode, focused: AgentID?) {
        var seen = Set<String>()
        let now = Date()
        if case .focus = mode {
            for (key, view) in chipViews {
                view.isHidden = true
                _ = key
            }
            return
        }
        for (id, frame) in displayedLayout?.frames ?? [:] {
            guard let agent = agentsByID[id] else { continue }
            let chips: [(ChipKind, CGFloat)]
            switch mode {
            case .cluster:
                chips = Chips.clusterChip(for: agent).map { [($0, 1)] } ?? []
            case .active:
                chips = Chips.activeChips(for: agent, now: now)
            case .focus:
                chips = []
            }
            let size = Chips.size(for: frame.size)
            for (index, item) in chips.enumerated() {
                let key = "\(id)#\(index)"
                seen.insert(key)
                let view = chipViews[key] ?? ChipView(frame: .zero)
                if chipViews[key] == nil {
                    chipViews[key] = view
                    addSubview(view, positioned: .above, relativeTo: marbleViews[id])
                }
                view.kind = item.0
                view.fade = item.1
                view.isHidden = false
                let center = Chips.center(for: frame, index: index)
                view.frame = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            }
        }
        for key in chipViews.keys where !seen.contains(key) {
            chipViews[key]?.removeFromSuperview()
            chipViews.removeValue(forKey: key)
        }
    }

    private func rect(for frame: MarbleFrame) -> NSRect {
        NSRect(
            x: frame.center.x - frame.size / 2,
            y: frame.center.y - frame.size / 2,
            width: frame.size,
            height: frame.size
        )
    }

    /// Pull the glass disc inside the painted sphere so its material rim
    /// stays under the marble instead of drawing a bezel around it.
    private func glassRect(for frame: MarbleFrame) -> NSRect {
        let inset = max(4, frame.size * 0.12)
        return rect(for: frame).insetBy(dx: inset, dy: inset)
    }

    private func sortZ() {
        for glass in glassViews.values {
            addSubview(glass, positioned: .below, relativeTo: nil)
        }
        if let metalView {
            addSubview(metalView, positioned: .above, relativeTo: nil)
        }
        let sorted = (displayedLayout?.frames ?? [:]).sorted { $0.value.z < $1.value.z }
        let overflowZ = displayedLayout?.overflowFrame?.z ?? Int.max
        var placedOverflow = overflowView.isHidden
        for (id, frame) in sorted {
            if !placedOverflow, frame.z >= overflowZ {
                addSubview(overflowView, positioned: .above, relativeTo: nil)
                placedOverflow = true
            }
            if let view = marbleViews[id] {
                view.superview?.addSubview(view, positioned: .above, relativeTo: nil)
            }
        }
        if !placedOverflow {
            addSubview(overflowView, positioned: .above, relativeTo: nil)
        }
        for view in chipViews.values {
            addSubview(view, positioned: .above, relativeTo: nil)
        }
        addSubview(focusCard, positioned: .above, relativeTo: nil)
    }
}
