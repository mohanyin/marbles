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
    var dockFrame: CGRect
    var focusCardFrame: CGRect?
    var panelSize: CGSize
    var scrollOffset: CGFloat
    var maxScroll: CGFloat
    var visibleCount: Int
    var orientation: LineOrientation
}

enum LayoutEngine {
    static let marbleSize: CGFloat = 36
    static let padding: CGFloat = 10
    /// Marble → 3-light row.
    static let indicatorGap: CGFloat = 4
    /// Same light `Indicators.lightSize` draws. Derived so the space the layout
    /// reserves cannot drift from the size actually rendered.
    static let indicatorSize: CGFloat = Indicators.lightSize
    /// Indicator row → next marble.
    static let itemGap: CGFloat = 12
    static let maxVisible = 9
    static let maxAgents = 50
    static let emptyThickness: CGFloat = 10
    static let emptyLength: CGFloat = 36
    static let focusCardWidth: CGFloat = 360
    static let cardGap: CGFloat = 12

    /// Marble + indicator stack, not including the 12pt gap to the next marble.
    static var itemStack: CGFloat { marbleSize + indicatorGap + indicatorSize }
    /// Distance from one marble top to the next.
    static var itemStride: CGFloat { itemStack + itemGap }
    static var occupiedThickness: CGFloat { padding * 2 + marbleSize }

    static func layout(
        agents: [Agent],
        mode: OverlayMode,
        orientation: LineOrientation,
        scrollOffset: CGFloat,
        availableLineLength: CGFloat,
        cardTowardPositivePerpendicular: Bool,
        focusCardSize: CGSize
    ) -> LayoutResult {
        let ordered = Array(agents.prefix(maxAgents))
        let focused = mode.focusedAgentID
        let count = ordered.count
        let visible = visibleCount(count: count, available: availableLineLength)
        let viewport = dockLength(visibleCount: visible)
        let maxScroll = max(0, CGFloat(max(0, count - visible)) * itemStride)
        let scroll = clampScroll(scrollOffset, maxScroll: maxScroll)

        let dockSize: CGSize
        if count == 0 {
            dockSize = emptyDockSize(axis: orientation.axis)
        } else {
            switch orientation.axis {
            case .vertical:
                dockSize = CGSize(width: occupiedThickness, height: viewport)
            case .horizontal:
                dockSize = CGSize(width: viewport, height: occupiedThickness)
            }
        }

        var frames: [AgentID: MarbleFrame] = [:]
        for (index, agent) in ordered.enumerated() {
            let alongFromStart = padding + CGFloat(index) * itemStride + marbleSize / 2 - scroll
            let cross = padding + marbleSize / 2
            let center: CGPoint
            switch orientation.axis {
            case .horizontal:
                center = CGPoint(x: alongFromStart, y: cross)
            case .vertical:
                let along = orientation.indexIncreasesAlongPositive
                    ? alongFromStart
                    : dockSize.height - alongFromStart
                center = CGPoint(x: cross, y: along)
            }
            frames[agent.id] = MarbleFrame(center: center, size: marbleSize, z: index, dim: 0)
        }

        var dock = CGRect(origin: .zero, size: dockSize)
        var card: CGRect?
        if let focused, let hero = frames[focused] {
            card = cardFrame(
                hero: hero,
                axis: orientation.axis,
                towardPositive: cardTowardPositivePerpendicular,
                size: focusCardSize
            )
            card = clampCard(card!, dock: dock, availableAlong: availableLineLength, axis: orientation.axis)
        }

        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX = dockSize.width
        var maxY = dockSize.height
        if let card {
            minX = min(minX, card.minX)
            minY = min(minY, card.minY)
            maxX = max(maxX, card.maxX)
            maxY = max(maxY, card.maxY)
        }

        let origin = CGPoint(x: minX, y: minY)
        var shifted: [AgentID: MarbleFrame] = [:]
        for (id, frame) in frames {
            shifted[id] = MarbleFrame(
                center: CGPoint(x: frame.center.x - origin.x, y: frame.center.y - origin.y),
                size: frame.size,
                z: frame.z,
                dim: 0
            )
        }
        dock.origin = CGPoint(x: dock.origin.x - origin.x, y: dock.origin.y - origin.y)
        let shiftedCard = card?.offsetBy(dx: -origin.x, dy: -origin.y)

        return LayoutResult(
            frames: shifted,
            dockFrame: dock,
            focusCardFrame: shiftedCard,
            panelSize: CGSize(width: maxX - minX, height: maxY - minY),
            scrollOffset: scroll,
            maxScroll: maxScroll,
            visibleCount: visible,
            orientation: orientation
        )
    }

    static func contentLength(count: Int) -> CGFloat {
        guard count > 0 else { return emptyLength }
        return padding + CGFloat(count) * itemStack + CGFloat(max(0, count - 1)) * itemGap + padding
    }

    static func dockLength(visibleCount: Int) -> CGFloat {
        contentLength(count: visibleCount)
    }

    static func visibleCount(count: Int, available: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let fit = Int(floor(max(0, available - padding * 2 + itemGap) / itemStride))
        return min(maxVisible, count, max(1, fit))
    }

    static func clampScroll(_ offset: CGFloat, maxScroll: CGFloat) -> CGFloat {
        min(max(offset, 0), max(0, maxScroll))
    }

    static func snapScroll(_ offset: CGFloat, maxScroll: CGFloat) -> CGFloat {
        let clamped = clampScroll(offset, maxScroll: maxScroll)
        guard itemStride > 0, maxScroll > 0 else { return clamped }
        let index = (clamped / itemStride).rounded()
        return clampScroll(index * itemStride, maxScroll: maxScroll)
    }

    static func scrollToReveal(index: Int, count: Int, available: CGFloat, current: CGFloat) -> CGFloat {
        let visible = visibleCount(count: count, available: available)
        let maxScroll = max(0, CGFloat(max(0, count - visible)) * itemStride)
        guard visible > 0, count > 0 else { return 0 }
        let first = Int((clampScroll(current, maxScroll: maxScroll) / itemStride).rounded(.down))
        let last = first + visible - 1
        if index < first {
            return clampScroll(CGFloat(index) * itemStride, maxScroll: maxScroll)
        }
        if index > last {
            return clampScroll(CGFloat(index - visible + 1) * itemStride, maxScroll: maxScroll)
        }
        return clampScroll(current, maxScroll: maxScroll)
    }

    private static func emptyDockSize(axis: LineAxis) -> CGSize {
        switch axis {
        case .vertical:
            return CGSize(width: emptyThickness, height: emptyLength)
        case .horizontal:
            return CGSize(width: emptyLength, height: emptyThickness)
        }
    }

    /// Keep the card on screen without breaking its centring on the hovered marble.
    ///
    /// `SnapGeometry.origin(for:size:safe:)` centres the dock along its own axis, so there is
    /// `(available - dockLength) / 2` of free screen on *each* side of the dock that the card may
    /// use. Clamping to the dock's own bounds instead — as this did — pinned the card's leading
    /// edge to the dock's leading edge whenever the hero sat near the start of the line, which
    /// read as the card being left- or bottom-aligned rather than centred.
    private static func clampCard(_ card: CGRect, dock: CGRect, availableAlong: CGFloat, axis: LineAxis) -> CGRect {
        var frame = card
        switch axis {
        case .vertical:
            let slack = max(0, (availableAlong - dock.height) / 2)
            let lower = dock.minY - slack
            let upper = dock.maxY + slack - frame.height
            frame.origin.y = min(max(frame.origin.y, lower), max(lower, upper))
        case .horizontal:
            let slack = max(0, (availableAlong - dock.width) / 2)
            let lower = dock.minX - slack
            let upper = dock.maxX + slack - frame.width
            frame.origin.x = min(max(frame.origin.x, lower), max(lower, upper))
        }
        return frame
    }

    private static func cardFrame(
        hero: MarbleFrame,
        axis: LineAxis,
        towardPositive: Bool,
        size: CGSize
    ) -> CGRect {
        switch axis {
        case .vertical:
            let x = towardPositive
                ? hero.center.x + hero.size / 2 + cardGap
                : hero.center.x - hero.size / 2 - cardGap - size.width
            // The marble overhang rides at the top (max-Y), so centre the body on the hero
            // rather than the whole frame, or the card visually sits low.
            let y = hero.center.y - (size.height - FocusCardMetrics.marbleOverhang) / 2
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        case .horizontal:
            let x = hero.center.x - size.width / 2
            let y = towardPositive
                ? hero.center.y + hero.size / 2 + cardGap
                : hero.center.y - hero.size / 2 - cardGap - size.height
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
        return LayoutResult(
            frames: frames,
            dockFrame: dockFrame.offsetBy(dx: delta.x, dy: delta.y),
            focusCardFrame: focusCardFrame?.offsetBy(dx: delta.x, dy: delta.y),
            panelSize: panelSize,
            scrollOffset: scrollOffset,
            maxScroll: maxScroll,
            visibleCount: visibleCount,
            orientation: orientation
        )
    }

    func localizedToPanel() -> (origin: CGPoint, local: LayoutResult) {
        var minX = dockFrame.minX
        var minY = dockFrame.minY
        var maxX = dockFrame.maxX
        var maxY = dockFrame.maxY
        if let focusCardFrame {
            minX = min(minX, focusCardFrame.minX)
            minY = min(minY, focusCardFrame.minY)
            maxX = max(maxX, focusCardFrame.maxX)
            maxY = max(maxY, focusCardFrame.maxY)
        }
        let origin = CGPoint(x: minX, y: minY)
        let local = shifted(by: CGPoint(x: -origin.x, y: -origin.y))
        return (
            origin,
            LayoutResult(
                frames: local.frames,
                dockFrame: local.dockFrame,
                focusCardFrame: local.focusCardFrame,
                panelSize: CGSize(width: maxX - minX, height: maxY - minY),
                scrollOffset: local.scrollOffset,
                maxScroll: local.maxScroll,
                visibleCount: local.visibleCount,
                orientation: local.orientation
            )
        )
    }
}
