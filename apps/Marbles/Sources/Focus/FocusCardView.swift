import AppKit

/// Focus popover: an enlarged marble protruding off the top, the agent title, a hairline
/// rule, the human's last message, and the agent's response.
///
/// The view's frame includes `FocusCardMetrics.marbleOverhang` at the top — that strip is
/// outside the card body, so only `body` clips. Sizing lives in `FocusCardMetrics` and is
/// shared with `LayoutEngine`.
/// Top-down coordinates, matching `FocusCardView.isFlipped`.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FocusCardView: NSView {
    private let body = FlippedView()
    private let background = CardBackgroundView(cornerRadius: FocusCardMetrics.cornerRadius)
    private let marble = FocusMarbleView(frame: .zero)
    private let title = NSTextField(labelWithString: "")
    private let rule = NSView()
    private let promptBox = FlippedView()
    private let promptScroll = NSScrollView()
    private let prompt = NSTextView()
    private let responseScroll = NSScrollView()
    private let response = NSTextView()

    /// `apply` runs before `layout`, and `pin(text:to:)` re-flows the text container afterwards,
    /// which can leave a scroll region parked mid-content. Reset once the frames are final.
    private var needsScrollReset = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        body.wantsLayer = true
        body.layer?.cornerRadius = FocusCardMetrics.cornerRadius
        body.layer?.masksToBounds = true
        addSubview(body)

        background.autoresizingMask = [.width, .height]
        body.addSubview(background)

        title.font = FocusCardMetrics.titleFont
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.alignment = .center
        body.addSubview(title)

        rule.wantsLayer = true
        body.addSubview(rule)

        promptBox.wantsLayer = true
        promptBox.layer?.cornerRadius = FocusCardMetrics.promptCornerRadius
        promptBox.layer?.masksToBounds = true
        body.addSubview(promptBox)

        configure(scroll: promptScroll, text: prompt, color: CardPalette.promptText)
        promptBox.addSubview(promptScroll)

        configure(scroll: responseScroll, text: response, color: CardPalette.responseText)
        body.addSubview(responseScroll)

        // Added last so the overhanging half is never covered by the body.
        addSubview(marble)

        applyPalette()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(agent: Agent) {
        marble.tick(agent: agent, now: Date(), reducedMotion: false)

        let heading = FocusPreview.title(for: agent)
        title.stringValue = heading ?? ""
        title.isHidden = heading == nil
        rule.isHidden = heading == nil

        let promptText = FocusPreview.prompt(for: agent) ?? ""
        // Guard against resetting scroll position on every hover tick.
        if prompt.string != promptText {
            prompt.string = promptText
            needsScrollReset = true
        }
        promptBox.isHidden = promptText.isEmpty

        let responseText = FocusPreview.line(for: agent)
        if response.string != responseText {
            response.string = responseText
            needsScrollReset = true
        }
        responseScroll.isHidden = responseText.isEmpty

        needsLayout = true
    }

    func tickMotion(agent: Agent, now: Date, reducedMotion: Bool) {
        marble.tick(agent: agent, now: now, reducedMotion: reducedMotion)
    }

    override func layout() {
        super.layout()
        let metrics = FocusCardMetrics.self
        let overhang = metrics.marbleOverhang

        body.frame = NSRect(
            x: 0,
            y: overhang,
            width: bounds.width,
            height: max(bounds.height - overhang, 0)
        )
        marble.frame = NSRect(
            x: (bounds.width - metrics.marbleDiameter) / 2,
            y: 0,
            width: metrics.marbleDiameter,
            height: metrics.marbleDiameter
        )

        let pad = metrics.padding
        let width = body.bounds.width - pad * 2
        // The marble's lower half overlaps the body's top; content starts below it.
        var y = overhang + pad

        if !title.isHidden {
            title.frame = NSRect(x: pad, y: y, width: width, height: metrics.titleHeight)
            y += metrics.titleHeight + metrics.gap
            rule.frame = NSRect(x: pad, y: y, width: width, height: metrics.ruleHeight)
            y += metrics.ruleHeight
        }

        if !promptBox.isHidden {
            let height = metrics.promptHeight(prompt.string)
            y += metrics.gap
            promptBox.frame = NSRect(
                x: pad + metrics.promptLeadingInset,
                y: y,
                width: width - metrics.promptLeadingInset,
                height: height
            )
            // Full width: the horizontal padding lives in the text view, so the knob rides in
            // the padding rather than hard against the text.
            promptScroll.frame = NSRect(
                x: 0,
                y: metrics.promptInset,
                width: promptBox.bounds.width,
                height: max(promptBox.bounds.height - metrics.promptInset * 2, 0)
            )
            setScroller(promptScroll, enabled: metrics.promptOverflows(prompt.string))
            pin(text: prompt, to: promptScroll, sideInset: metrics.promptInset)
            y += height
        }

        if !responseScroll.isHidden {
            let height = metrics.responseHeight(response.string)
            y += metrics.gap
            responseScroll.frame = NSRect(x: pad, y: y, width: width, height: height)
            setScroller(responseScroll, enabled: metrics.responseOverflows(response.string))
            pin(text: response, to: responseScroll, sideInset: 0)
        }

        if needsScrollReset {
            needsScrollReset = false
            scrollToTop(promptScroll)
            scrollToTop(responseScroll)
        }
    }

    /// Toggle only on a real change — reassigning this every layout re-triggers the flash.
    private func setScroller(_ scroll: NSScrollView, enabled: Bool) {
        guard scroll.hasVerticalScroller != enabled else { return }
        scroll.hasVerticalScroller = enabled
    }

    private func scrollToTop(_ scroll: NSScrollView) {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    /// Clicks anywhere on the body stay with the card; the overhang strip beside the marble
    /// is transparent and must fall through so it doesn't eat dock clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let local = convert(point, from: superview)
        return body.frame.contains(local) ? hit : nil
    }

    private func applyPalette() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            rule.layer?.backgroundColor = CardPalette.hairline.cgColor
            promptBox.layer?.backgroundColor = CardPalette.promptFill.cgColor
            prompt.textColor = CardPalette.promptText
            response.textColor = CardPalette.responseText
        }
    }

    private func configure(scroll: NSScrollView, text: NSTextView, color: NSColor) {
        let scroller = SlimScroller(frame: .zero)
        scroller.scrollerStyle = .overlay
        scroll.verticalScroller = scroller
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.documentView = text

        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = FocusCardMetrics.bodyFont
        text.textColor = color
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = false
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    /// `sideInset` pads the text on both sides; the gutter is taken off the right only, so the
    /// text column stays left-aligned and the knob gets clear space.
    private func pin(text: NSTextView, to scroll: NSScrollView, sideInset: CGFloat) {
        let inner = max(scroll.contentSize.width, 1)
        let wrap = max(inner - sideInset * 2 - FocusCardMetrics.scrollGutter, 1)
        text.textContainerInset = NSSize(width: sideInset, height: 0)
        text.minSize = NSSize(width: inner, height: 0)
        text.maxSize = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = NSSize(width: wrap, height: CGFloat.greatestFiniteMagnitude)
        text.frame.size.width = inner
    }
}
