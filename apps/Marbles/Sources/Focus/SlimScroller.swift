import AppKit

/// Narrow scroller for the Focus card's text regions.
///
/// AppKit's overlay scroller reserves 17pt (15pt at `.small`) and paints a light knob that reads
/// far too heavy against a 330pt-wide card. This one reserves `trackWidth`, skips the knob slot
/// entirely, and draws the knob in the card's own ink so it tracks light/dark with everything else.
final class SlimScroller: NSScroller {
    static var trackWidth: CGFloat { FocusCardMetrics.scrollGutter }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        trackWidth
    }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    /// No slot — the knob floats over the text.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        // Take only the vertical extent from AppKit. Even with `scrollerWidth` overridden to 8,
        // `rect(for: .knob)` comes back as x = -1, width = 6 — the knob would be drawn a point
        // outside the left bound and clipped, leaving it rounded on the right and flat on the
        // left. Deriving x/width from `bounds` gives a true pill the full width of the track.
        let slot = rect(for: .knob)
        let knob = NSRect(x: bounds.minX, y: slot.minY, width: bounds.width, height: slot.height)
        guard knob.width > 0, knob.height > 0 else { return }
        let radius = knob.width / 2
        let path = NSBezierPath(roundedRect: knob, xRadius: radius, yRadius: radius)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CardPalette.scrollKnob.setFill()
            path.fill()
        }
    }
}
