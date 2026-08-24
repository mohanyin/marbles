import AppKit

final class OverlayRootView: NSView {
    private var marbleViews: [AgentID: PlaceholderMarbleView] = [:]
    private let overflowView = OverflowMarbleView()
    let focusCard = FocusCardView()

    var displayedLayout: LayoutResult?
    var agentsByID: [AgentID: Agent] = [:]
    /// Active/Focus: clicks on empty panel chrome dismiss instead of falling through.
    var capturesEmptyClicks = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        overflowView.isHidden = true
        focusCard.isHidden = true
        addSubview(overflowView)
        addSubview(focusCard)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(layout: LayoutResult, agents: [Agent], focused: AgentID?) {
        displayedLayout = layout
        agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        let ids = Set(layout.frames.keys)
        for id in marbleViews.keys where !ids.contains(id) {
            marbleViews[id]?.removeFromSuperview()
            marbleViews.removeValue(forKey: id)
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
            view.marbleSize = frame.size
            view.dim = frame.dim
            view.frame = rect(for: frame)
        }

        if let overflow = layout.overflow, let frame = layout.overflowFrame {
            overflowView.isHidden = false
            overflowView.hiddenCount = overflow.hiddenCount
            overflowView.frame = rect(for: frame)
        } else {
            overflowView.isHidden = true
        }

        if let card = layout.focusCardFrame, let id = focused {
            focusCard.isHidden = false
            focusCard.frame = card
            let agent = agentsByID[id]
            focusCard.title = agent.map { "Agent \($0.id)" } ?? "Agent"
            let status = agent.map { String(describing: $0.status) } ?? ""
            let preview = agent?.lastAssistantPreview ?? ""
            let tool = agent?.currentTool.map { "Tool: \($0.name)" } ?? "No tool"
            focusCard.detail = "W1 placeholder card.\n\(status)\n\(tool)\n\(preview)\nClick the hero marble to leave. Esc also works."
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
        if containsInteractivePoint(point) { return self }
        if capturesEmptyClicks, bounds.contains(point) { return self }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rect(for frame: MarbleFrame) -> NSRect {
        NSRect(
            x: frame.center.x - frame.size / 2,
            y: frame.center.y - frame.size / 2,
            width: frame.size,
            height: frame.size
        )
    }

    private func sortZ() {
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
        addSubview(focusCard, positioned: .above, relativeTo: nil)
    }
}
