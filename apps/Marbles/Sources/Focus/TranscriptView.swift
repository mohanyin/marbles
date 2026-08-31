import AppKit

/// The agent's steps for the current turn, stacked in order.
///
/// Document view of the card's transcript scroll view. Heights come from `FocusCardMetrics` so
/// the card's measured size and what actually gets laid out cannot drift — the same contract the
/// rest of the card follows.
final class TranscriptView: FlippedView {
    private var runViews: [NSView] = []
    private(set) var contentHeight: CGFloat = 0

    /// Rebuild for `turn`. `fallback` is the status word shown before any step lands (PRD §5.2).
    func apply(turn: TranscriptTurn, fallback: String) {
        runViews.forEach { $0.removeFromSuperview() }
        runViews = []

        let metrics = FocusCardMetrics.self
        let width = metrics.responseTextWidth
        let runs = turn.runs

        var y: CGFloat = 0
        if runs.isEmpty {
            let view = Self.proseView(fallback, muted: true)
            view.frame = NSRect(x: 0, y: 0, width: width, height: metrics.textHeight(
                fallback, font: metrics.bodyFont, width: width))
            add(view)
            y = view.frame.maxY
        } else {
            for (index, run) in runs.enumerated() {
                if index > 0 { y += metrics.runSpacing }
                let isLast = index == runs.count - 1
                let height = metrics.runHeight(run, isLast: isLast)
                let view = Self.view(for: run, expanded: metrics.runIsExpanded(run, isLast: isLast), width: width)
                view.frame = NSRect(x: 0, y: y, width: width, height: height)
                add(view)
                y += height
            }
        }

        contentHeight = ceil(y)
        setFrameSize(NSSize(width: width, height: contentHeight))
        needsLayout = true
    }

    private func add(_ view: NSView) {
        runViews.append(view)
        addSubview(view)
    }

    // MARK: - Row construction

    private static func view(for run: TranscriptRun, expanded: Bool, width: CGFloat) -> NSView {
        switch run {
        case .prose(let text):
            return proseStack(text, width: width)
        case .thinking:
            return labelRow("Thinking…", color: CardPalette.ink.withAlphaComponent(0.45))
        case .tools(let calls):
            return expanded ? toolStack(calls, width: width) : collapsedRow(calls)
        }
    }

    /// One prose run becomes a stack of markdown blocks: paragraphs, headings and list items as
    /// attributed text; fenced code in its own non-wrapping, horizontally scrollable box.
    private static func proseStack(_ source: String, width: CGFloat) -> NSView {
        let container = FlippedView()
        let style = cardStyle()
        var y: CGFloat = 0
        for (index, block) in MarkdownParser.blocks(source).enumerated() {
            if index > 0 { y += FocusCardMetrics.blockSpacing }
            let height = FocusCardMetrics.blockHeight(block, style: style, width: width)
            let view: NSView
            if case .code(_, let lines) = block {
                view = codeBlock(lines)
            } else {
                view = attributedView(MarkdownRenderer.attributed(block, style: style), width: width)
            }
            view.frame = NSRect(x: 0, y: y, width: width, height: height)
            container.addSubview(view)
            y += height
        }
        container.setFrameSize(NSSize(width: width, height: ceil(y)))
        return container
    }

    private static func cardStyle() -> MarkdownRenderer.Style {
        FocusCardMetrics.markdownStyle(
            text: CardPalette.responseText,
            codeText: CardPalette.ink.withAlphaComponent(0.85)
        )
    }

    private static func attributedView(_ text: NSAttributedString, width: CGFloat) -> NSView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textStorage?.setAttributedString(text)
        return view
    }

    private static func codeBlock(_ lines: [String]) -> NSView {
        CodeBlockView(lines: lines)
    }

    private static func proseView(_ text: String, muted: Bool) -> NSView {
        let view = NSTextView()
        view.string = text
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.font = FocusCardMetrics.bodyFont
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(
            width: FocusCardMetrics.responseTextWidth,
            height: .greatestFiniteMagnitude
        )
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        applyDrawing(to: view) {
            view.textColor = muted
                ? CardPalette.ink.withAlphaComponent(0.55)
                : CardPalette.responseText
        }
        return view
    }

    private static func collapsedRow(_ calls: [TranscriptToolCall]) -> NSView {
        let failed = calls.contains { $0.status == .failed }
        let text = calls.count == 1
            ? calls[0].label
            : "Ran \(calls.count) commands"
        return labelRow(
            text,
            color: failed ? errorColor : CardPalette.ink.withAlphaComponent(0.7)
        )
    }

    private static func toolStack(_ calls: [TranscriptToolCall], width: CGFloat) -> NSView {
        let container = FlippedView()
        var y: CGFloat = 0
        for call in calls {
            let row = labelRow(call.label, color: color(for: call.status))
            row.frame = NSRect(x: 0, y: y, width: width, height: FocusCardMetrics.toolRowHeight)
            container.addSubview(row)
            y += FocusCardMetrics.toolRowHeight + FocusCardMetrics.toolRowSpacing
        }
        return container
    }

    private static func labelRow(_ text: String, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = FocusCardMetrics.bodyFont
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        applyDrawing(to: field) { field.textColor = color }
        return field
    }

    private static func color(for status: TranscriptToolCall.Status) -> NSColor {
        switch status {
        case .running: return CardPalette.ink.withAlphaComponent(0.55)
        case .succeeded: return CardPalette.ink.withAlphaComponent(0.7)
        case .failed: return errorColor
        }
    }

    private static var errorColor: NSColor {
        NSColor(srgbRed: 0xE8 / 255, green: 0x42 / 255, blue: 0, alpha: 1)
    }

    /// Dynamic colours resolve against the drawing appearance, so pin it while assigning.
    private static func applyDrawing(to view: NSView, _ body: () -> Void) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance(body)
    }
}

/// A fenced code block: rounded background, monospaced, and scrolling sideways rather than
/// wrapping — wrapped code is unreadable, and the card is only 360pt wide.
final class CodeBlockView: NSView {
    private let scroll = NSScrollView()
    private let text = NSTextView()

    init(lines: [String]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = FocusCardMetrics.codeCornerRadius
        layer?.masksToBounds = true

        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        // Overlay so the scroller floats instead of stealing height the metrics didn't budget.
        scroll.scrollerStyle = .overlay

        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = FocusCardMetrics.monoFont
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // Both axes resizable so `sizeToFit` can size the document view to the code; with
        // vertical resizing off it stays 0pt tall and the block renders empty.
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.minSize = .zero
        text.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        text.string = lines.joined(separator: "\n")

        scroll.documentView = text
        addSubview(scroll)
        applyPalette()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset = FocusCardMetrics.codeInset
        scroll.frame = bounds.insetBy(dx: inset, dy: inset)
        text.sizeToFit()
        // Only offer a scroller when the code actually runs past the edge.
        scroll.hasHorizontalScroller = text.frame.width > scroll.contentSize.width
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CardPalette.ink.withAlphaComponent(0.08).cgColor
            text.textColor = CardPalette.ink.withAlphaComponent(0.85)
        }
    }
}
