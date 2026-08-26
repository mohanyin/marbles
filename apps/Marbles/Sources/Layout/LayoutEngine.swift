import Foundation
import AppKit

struct MarbleFrame: Equatable {
    var center: CGPoint
    var size: CGFloat
    var z: Int
    var dim: CGFloat
}

struct LayoutResult: Equatable {
    var frames: [AgentID: MarbleFrame]
    var overflow: OverflowToken?
    var overflowFrame: MarbleFrame?
    var focusCardFrame: CGRect?
    var panelSize: CGSize
}

enum LayoutEngine {
    static let clusterSize: CGFloat = 36
    static let activeSize: CGFloat = 60
    static let focusHeroSize: CGFloat = 72
    static let inset: CGFloat = 8
    static let spacingX: CGFloat = 20
    static let spacingY: CGFloat = 17
    static let spacingZ: CGFloat = 14
    static let lineStride: CGFloat = 68
    static let focusCardSize = CGSize(width: 360, height: 312)
    static let dimmed: CGFloat = 0.45
    /// Rightmost cell on the front / top lattice layer (x:2, y:0, z:0).
    static let overflowLatticeIndex = 2

    static func layout(
        agents: [Agent],
        mode: OverlayMode,
        orientation: LineOrientation,
        scrollOffset: CGFloat,
        availableLineLength: CGFloat,
        cardTowardPositivePerpendicular: Bool
    ) -> LayoutResult {
        let selection: (visible: [Agent], overflow: OverflowToken?) = visibleAgents(agents, focused: mode.focusedAgentID)
        switch mode {
        case .cluster:
            return clusterLayout(selection.visible, overflow: selection.overflow)
        case .active:
            return lineLayout(
                agents,
                orientation: orientation,
                scrollOffset: scrollOffset,
                availableLength: availableLineLength,
                focused: nil,
                cardTowardPositivePerpendicular: cardTowardPositivePerpendicular
            )
        case .focus(let id):
            return lineLayout(
                agents,
                orientation: orientation,
                scrollOffset: scrollOffset,
                availableLength: availableLineLength,
                focused: id,
                cardTowardPositivePerpendicular: cardTowardPositivePerpendicular
            )
        }
    }

    static func latticeCoordinate(index: Int) -> (x: Int, y: Int, z: Int) {
        let clamped = max(0, min(26, index))
        let z = clamped / 9
        let rem = clamped % 9
        let y = rem / 3
        let x = rem % 3
        return (x, y, z)
    }

    static func latticeCenter(index: Int) -> CGPoint {
        let (x, y, z) = latticeCoordinate(index: index)
        return CGPoint(
            x: CGFloat(x - y) * spacingX,
            y: CGFloat(x + y) * spacingY - CGFloat(z) * spacingZ
        )
    }

    private static func latticeDrawOrder(index: Int) -> Int {
        let (x, y, z) = latticeCoordinate(index: index)
        // Higher draws on top. Front lattice (z=0) must sit on the back layers.
        return (2 - z) * 100 - (x + y)
    }

    private static func visibleAgents(_ agents: [Agent], focused: AgentID?) -> ([Agent], OverflowToken?) {
        let live = agents.filter { !$0.isDemo }
        guard live.count > 27 else {
            return (live.sorted(by: slotOrder), nil)
        }
        let ranked = live.sorted { lhs, rhs in
            if lhs.id == focused { return true }
            if rhs.id == focused { return false }
            return lhs.lastEventAt > rhs.lastEventAt
        }
        let hidden = ranked.count - 26
        let withoutOverflowSlot = ranked.filter { $0.latticeIndex != overflowLatticeIndex }
        let pool = withoutOverflowSlot.count >= 26 ? withoutOverflowSlot : ranked
        let shown = Array(pool.prefix(26)).sorted(by: slotOrder)
        return (shown, OverflowToken(hiddenCount: hidden))
    }

    private static func slotOrder(_ lhs: Agent, _ rhs: Agent) -> Bool {
        switch (lhs.latticeIndex, rhs.latticeIndex) {
        case let (a?, b?):
            if a != b { return a < b }
            return lhs.id < rhs.id
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    private static func clusterLayout(_ agents: [Agent], overflow: OverflowToken?) -> LayoutResult {
        var raw: [(AgentID, CGPoint, Int)] = []
        for agent in agents {
            let index = agent.latticeIndex ?? 0
            raw.append((agent.id, latticeCenter(index: index), latticeDrawOrder(index: index)))
        }

        var overflowCenter: CGPoint?
        var overflowDrawOrder = 0
        if overflow != nil {
            overflowCenter = latticeCenter(index: overflowLatticeIndex)
            overflowDrawOrder = latticeDrawOrder(index: overflowLatticeIndex)
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        let radius = clusterSize / 2
        func expand(_ point: CGPoint) {
            minX = min(minX, point.x - radius)
            minY = min(minY, point.y - radius)
            maxX = max(maxX, point.x + radius)
            maxY = max(maxY, point.y + radius)
        }
        if raw.isEmpty, overflowCenter == nil {
            minX = 0
            minY = 0
            maxX = clusterSize
            maxY = clusterSize
        }
        raw.forEach { expand($0.1) }
        if let overflowCenter {
            expand(overflowCenter)
        }

        let origin = CGPoint(x: minX - inset, y: minY - inset)
        var frames: [AgentID: MarbleFrame] = [:]
        for item in raw {
            frames[item.0] = MarbleFrame(
                center: CGPoint(x: item.1.x - origin.x, y: item.1.y - origin.y),
                size: clusterSize,
                z: item.2,
                dim: 0
            )
        }
        var overflowFrame: MarbleFrame?
        if let overflowCenter {
            overflowFrame = MarbleFrame(
                center: CGPoint(x: overflowCenter.x - origin.x, y: overflowCenter.y - origin.y),
                size: clusterSize,
                z: overflowDrawOrder,
                dim: 0
            )
        }
        let size = CGSize(
            width: max(clusterSize + inset * 2, maxX - minX + inset * 2),
            height: max(clusterSize + inset * 2, maxY - minY + inset * 2)
        )
        return LayoutResult(
            frames: frames,
            overflow: overflow,
            overflowFrame: overflowFrame,
            focusCardFrame: nil,
            panelSize: size
        )
    }

    private static func lineLayout(
        _ agents: [Agent],
        orientation: LineOrientation,
        scrollOffset: CGFloat,
        availableLength: CGFloat,
        focused: AgentID?,
        cardTowardPositivePerpendicular: Bool
    ) -> LayoutResult {
        let sorted = agents.filter { !$0.isDemo }.sorted(by: slotOrder)
        let ordered = orientation.indexIncreasesAlongPositive ? sorted : Array(sorted.reversed())
        let count = max(ordered.count, 1)
        let totalLength = CGFloat(count) * lineStride
        let viewport = max(lineStride, min(availableLength, totalLength))
        let maxScroll = max(0, totalLength - viewport)
        let scroll = min(max(scrollOffset, 0), maxScroll)

        var frames: [AgentID: MarbleFrame] = [:]
        for (index, agent) in ordered.enumerated() {
            let along = CGFloat(index) * lineStride + lineStride / 2 - scroll
            let isHero = agent.id == focused
            let size = isHero ? focusHeroSize : activeSize
            let dim: CGFloat = focused == nil ? 0 : (isHero ? 0 : dimmed)
            let center: CGPoint
            switch orientation.axis {
            case .horizontal:
                center = CGPoint(x: along, y: inset + focusHeroSize / 2)
            case .vertical:
                center = CGPoint(x: inset + focusHeroSize / 2, y: along)
            }
            frames[agent.id] = MarbleFrame(center: center, size: size, z: isHero ? 10 : index, dim: dim)
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for frame in frames.values {
            let r = frame.size / 2
            let along: CGFloat
            switch orientation.axis {
            case .horizontal: along = frame.center.x
            case .vertical: along = frame.center.y
            }
            guard along + r > 0, along - r < viewport else { continue }
            minX = min(minX, frame.center.x - r)
            minY = min(minY, frame.center.y - r)
            maxX = max(maxX, frame.center.x + r)
            maxY = max(maxY, frame.center.y + r)
        }
        if frames.isEmpty {
            minX = 0
            minY = 0
            maxX = activeSize
            maxY = activeSize
        }

        var card: CGRect?
        if let focused, let hero = frames[focused] {
            card = clampCard(
                cardFrame(
                    hero: hero,
                    axis: orientation.axis,
                    towardPositive: cardTowardPositivePerpendicular
                ),
                axis: orientation.axis,
                viewport: viewport
            )
            minX = min(minX, card!.minX)
            minY = min(minY, card!.minY)
            maxX = max(maxX, card!.maxX)
            maxY = max(maxY, card!.maxY)
        }

        let origin = CGPoint(x: minX - inset, y: minY - inset)
        var shifted: [AgentID: MarbleFrame] = [:]
        for (id, frame) in frames {
            shifted[id] = MarbleFrame(
                center: CGPoint(x: frame.center.x - origin.x, y: frame.center.y - origin.y),
                size: frame.size,
                z: frame.z,
                dim: frame.dim
            )
        }
        let shiftedCard = card?.offsetBy(dx: -origin.x, dy: -origin.y)
        let size = CGSize(width: maxX - minX + inset * 2, height: maxY - minY + inset * 2)
        return LayoutResult(
            frames: shifted,
            overflow: nil,
            overflowFrame: nil,
            focusCardFrame: shiftedCard,
            panelSize: size
        )
    }

    private static func clampCard(_ card: CGRect, axis: LineAxis, viewport: CGFloat) -> CGRect {
        var frame = card
        switch axis {
        case .vertical:
            let maxY = max(inset, viewport - frame.height - inset)
            frame.origin.y = min(max(frame.origin.y, inset), maxY)
        case .horizontal:
            let maxX = max(inset, viewport - frame.width - inset)
            frame.origin.x = min(max(frame.origin.x, inset), maxX)
        }
        return frame
    }

    private static func cardFrame(hero: MarbleFrame, axis: LineAxis, towardPositive: Bool) -> CGRect {
        let gap: CGFloat = 12
        let size = focusCardSize
        switch axis {
        case .vertical:
            let x = towardPositive
                ? hero.center.x + hero.size / 2 + gap
                : hero.center.x - hero.size / 2 - gap - size.width
            let y = hero.center.y - size.height / 2
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        case .horizontal:
            let x = hero.center.x - size.width / 2
            let y = towardPositive
                ? hero.center.y + hero.size / 2 + gap
                : hero.center.y - hero.size / 2 - gap - size.height
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}

extension LayoutResult {
    func placed(inScreenAt origin: CGPoint) -> LayoutResult {
        shifted(by: origin)
    }

    func shifted(by delta: CGPoint) -> LayoutResult {
        var frames = self.frames
        for id in frames.keys {
            guard var frame = frames[id] else { continue }
            frame.center.x += delta.x
            frame.center.y += delta.y
            frames[id] = frame
        }
        var overflowFrame = self.overflowFrame
        if var frame = overflowFrame {
            frame.center.x += delta.x
            frame.center.y += delta.y
            overflowFrame = frame
        }
        let card = focusCardFrame?.offsetBy(dx: delta.x, dy: delta.y)
        return LayoutResult(
            frames: frames,
            overflow: overflow,
            overflowFrame: overflowFrame,
            focusCardFrame: card,
            panelSize: panelSize
        )
    }

    /// Convert a screen-space layout into a tight local layout plus panel origin.
    func localizedToPanel() -> (origin: CGPoint, local: LayoutResult) {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        func expand(_ point: CGPoint, radius: CGFloat) {
            minX = min(minX, point.x - radius)
            minY = min(minY, point.y - radius)
            maxX = max(maxX, point.x + radius)
            maxY = max(maxY, point.y + radius)
        }
        for frame in frames.values {
            expand(frame.center, radius: frame.size / 2)
        }
        if let overflowFrame {
            expand(overflowFrame.center, radius: overflowFrame.size / 2)
        }
        if let focusCardFrame {
            minX = min(minX, focusCardFrame.minX)
            minY = min(minY, focusCardFrame.minY)
            maxX = max(maxX, focusCardFrame.maxX)
            maxY = max(maxY, focusCardFrame.maxY)
        }
        if minX == .greatestFiniteMagnitude {
            return (.zero, self)
        }
        let inset = LayoutEngine.inset
        let origin = CGPoint(x: minX - inset, y: minY - inset)
        let local = shifted(by: CGPoint(x: -origin.x, y: -origin.y))
        let size = CGSize(width: maxX - minX + inset * 2, height: maxY - minY + inset * 2)
        return (
            origin,
            LayoutResult(
                frames: local.frames,
                overflow: local.overflow,
                overflowFrame: local.overflowFrame,
                focusCardFrame: local.focusCardFrame,
                panelSize: size
            )
        )
    }
}
