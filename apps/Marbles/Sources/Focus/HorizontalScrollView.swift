import AppKit

/// A scroll view that only ever scrolls sideways, and hands vertical scrolling to its parent.
///
/// Code blocks and tables sit inside the transcript's own scroll view and are exactly as tall as
/// their content, so they have nothing to scroll vertically — but an `NSScrollView` still swallows
/// the wheel events, so scrolling over one stalled the transcript underneath it.
final class HorizontalScrollView: NSScrollView {
    /// A trackpad gesture is routed once, at its start, and stays routed for its whole life.
    /// Deciding per event lets a slightly diagonal flick flip back and forth mid-scroll.
    private var forwardsToParent = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = false
        verticalScrollElasticity = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        if Self.startsGesture(event) {
            forwardsToParent = Self.isVertical(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            )
        }
        guard forwardsToParent else {
            super.scrollWheel(with: event)
            return
        }
        nextResponder?.scrollWheel(with: event)
    }

    /// True at the start of a trackpad gesture, and for every classic wheel event — those carry
    /// no phase, so each one is judged on its own.
    static func startsGesture(_ event: NSEvent) -> Bool {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return true }
        return event.phase.isEmpty && event.momentumPhase.isEmpty
    }

    static func isVertical(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        abs(deltaY) > abs(deltaX)
    }
}
