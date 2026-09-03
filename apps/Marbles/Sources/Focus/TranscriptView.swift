import AppKit

/// The agent's steps for the current turn, stacked in order.
///
/// Document view of the card's transcript scroll view. Heights come from `FocusCardMetrics` so
/// the card's measured size and what actually gets laid out cannot drift — the same contract the
/// rest of the card follows.
final class TranscriptView: FlippedView {
    private var runViews: [NSView] = []
    private(set) var contentHeight: CGFloat = 0
    /// Raised when a run is clicked open or shut — the card has to remeasure and relayout.
    var onToggleRun: (([TranscriptToolCall], Bool) -> Void)?

    /// Rebuild for `turn`. `fallback` is the status word shown before any step lands (PRD §5.2).
    /// `animatingKey` is the run the reader just clicked; its chevron turns rather than snapping.
    func apply(
        turn: TranscriptTurn,
        fallback: String,
        expansion: TranscriptExpansion,
        animatingKey: String? = nil
    ) {
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
                let height = metrics.runHeight(run, isLast: isLast, expansion: expansion)
                let expanded = metrics.runIsExpanded(run, isLast: isLast, expansion: expansion)
                let view = makeView(
                    for: run,
                    expanded: expanded,
                    isLast: isLast,
                    width: width,
                    animatingKey: animatingKey
                )
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

    private func makeView(
        for run: TranscriptRun,
        expanded: Bool,
        isLast: Bool,
        width: CGFloat,
        animatingKey: String?
    ) -> NSView {
        switch run {
        case .prose(let text):
            return Self.proseStack(text, width: width)
        case .thinking:
            return Self.labelRow(
                "Thinking…",
                color: CardPalette.ink.withAlphaComponent(0.45),
                symbol: "brain"
            )
        case .tools(let calls):
            // A single call already shows everything, so it needs no header or chevron.
            guard calls.count > 1 else { return Self.collapsedRow(calls) }
            let animates = animatingKey != nil && animatingKey == TranscriptExpansion.key(calls)
            let body = Self.runBody(calls, expanded: expanded, width: width, animates: animates)
            return ToggleRunView(content: body) { [weak self] in
                self?.onToggleRun?(calls, isLast)
            }
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
            } else if case .table(let table) = block {
                view = TableBlockView(table: table, style: style)
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
        guard let only = calls.first, calls.count == 1 else {
            return labelRow(summaryText(calls), color: summaryColor(calls))
        }
        return labelRow(only.label, color: color(for: only.status))
    }

    /// Header row plus, when open, one row per call. The header is always present so there is
    /// something to click to close an expanded run.
    private static func runBody(
        _ calls: [TranscriptToolCall],
        expanded: Bool,
        width: CGFloat,
        animates: Bool
    ) -> NSView {
        let container = FlippedView()
        let metrics = FocusCardMetrics.self

        let header = FlippedView()
        header.frame = NSRect(x: 0, y: 0, width: width, height: metrics.toolHeaderHeight)
        let chevron = ChevronView(frame: NSRect(
            x: 0,
            y: (metrics.toolHeaderHeight - metrics.rowIconSize) / 2,
            width: metrics.rowIconSize,
            height: metrics.rowIconSize
        ))
        chevron.tint = summaryColor(calls)
        chevron.setOpen(expanded, animated: animates)
        header.addSubview(chevron)

        let label = labelRow(summaryText(calls), color: summaryColor(calls))
        let inset = metrics.rowIconSize + metrics.rowIconGap
        label.frame = NSRect(x: inset, y: 0, width: width - inset, height: metrics.toolHeaderHeight)
        header.addSubview(label)
        container.addSubview(header)

        var y = metrics.toolHeaderHeight
        if expanded {
            y += metrics.toolRowSpacing
            for call in calls {
                let row = labelRow(call.label, color: color(for: call.status))
                row.frame = NSRect(x: inset, y: y, width: width - inset, height: metrics.toolRowHeight)
                container.addSubview(row)
                y += metrics.toolRowHeight + metrics.toolRowSpacing
            }
            y -= metrics.toolRowSpacing
        }
        container.setFrameSize(NSSize(width: width, height: y))
        return container
    }

    private static func summaryText(_ calls: [TranscriptToolCall]) -> String {
        if calls.contains(where: { $0.status == .running }) {
            return "Running \(calls.count) commands…"
        }
        return "Ran \(calls.count) commands"
    }

    private static func summaryColor(_ calls: [TranscriptToolCall]) -> NSColor {
        calls.contains { $0.status == .failed }
            ? errorColor
            : CardPalette.ink.withAlphaComponent(0.7)
    }

    private static func labelRow(
        _ text: String,
        color: NSColor,
        symbol: String? = nil
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = FocusCardMetrics.bodyFont
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        applyDrawing(to: field) {
            field.textColor = color
            guard let symbol, let image = symbolImage(symbol, color: color) else { return }
            // An attachment keeps the row one view, so it still measures as one line.
            let out = NSMutableAttributedString()
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = FocusCardMetrics.rowIconSize
            attachment.bounds = NSRect(
                x: 0,
                y: FocusCardMetrics.bodyFont.descender + 1,
                width: size,
                height: size
            )
            out.append(NSAttributedString(attachment: attachment))
            out.append(NSAttributedString(
                string: "  " + text,
                attributes: [.font: FocusCardMetrics.bodyFont, .foregroundColor: color]
            ))
            field.attributedStringValue = out
        }
        return field
    }

    /// Tinted SF Symbol at the row icon size, or nil when the symbol is unavailable — callers
    /// fall back to text alone rather than showing a blank.
    static func symbolImage(_ name: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(
            pointSize: FocusCardMetrics.rowIconSize,
            weight: .medium
        ).applying(.init(paletteColors: [color]))
        return base.withSymbolConfiguration(config)
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
    private let scroll = HorizontalScrollView()
    private let text = NSTextView()

    init(lines: [String]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = FocusCardMetrics.codeCornerRadius
        layer?.masksToBounds = true

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

/// Wraps a tool run so clicking it opens or collapses the run.
///
/// A plain `mouseDown` override rather than a button: the rows are laid out by hand at measured
/// heights, and a button's own intrinsic sizing and focus ring would fight that.
private final class ToggleRunView: NSView {
    private let onClick: () -> Void

    init(content: NSView, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Disclosure chevron that turns between pointing right (closed) and down (open).
///
/// Layer-hosting with a sublayer we position ourselves: rotating a layer-backed `NSView` means
/// fighting AppKit over `anchorPoint`, since it rewrites the layer's geometry on every layout.
final class ChevronView: NSView {
    private let arrow = CALayer()
    private(set) var isOpen = false

    var tint: NSColor = .labelColor {
        didSet { updateImage() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        arrow.contentsGravity = .resizeAspect
        arrow.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(arrow)
        updateImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrow.bounds = CGRect(origin: .zero, size: bounds.size)
        arrow.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateImage()
    }

    func setOpen(_ open: Bool, animated: Bool) {
        isOpen = open
        // Views are rebuilt on every refresh, so an un-animated set must not inherit the
        // implicit animation CALayer would otherwise give it.
        let transform = CATransform3DMakeRotation(open ? -.pi / 2 : 0, 0, 0, 1)
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            // Start from the closed/open opposite so the turn is visible on a fresh view.
            arrow.transform = CATransform3DMakeRotation(open ? 0 : -.pi / 2, 0, 0, 1)
            arrow.transform = transform
        } else {
            CATransaction.setDisableActions(true)
            arrow.transform = transform
        }
        CATransaction.commit()
    }

    private func updateImage() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let image = TranscriptView.symbolImage("chevron.right", color: tint) else { return }
            arrow.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
}

/// A markdown table. Columns take their natural width and the whole grid scrolls sideways, the
/// same bargain fenced code makes — at 322pt of text width, fitting real tables in place would
/// mean wrapping every description column to a couple of characters.
private final class TableBlockView: NSView {
    private let scroll = HorizontalScrollView()
    private let grid: NSView
    private let table: MarkdownTable
    private let style: MarkdownRenderer.Style
    private let geometry: FocusCardMetrics.TableLayout

    init(table: MarkdownTable, style: MarkdownRenderer.Style) {
        self.table = table
        self.style = style
        self.geometry = FocusCardMetrics.tableLayout(table, style: style)
        self.grid = FlippedView(frame: NSRect(x: 0, y: 0, width: geometry.width, height: geometry.height))
        super.init(frame: .zero)

        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = grid
        addSubview(scroll)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        scroll.hasHorizontalScroller = geometry.width > scroll.contentSize.width
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        build()
    }

    private func build() {
        grid.subviews.forEach { $0.removeFromSuperview() }
        grid.setFrameSize(NSSize(width: geometry.width, height: geometry.height))

        effectiveAppearance.performAsCurrentDrawingAppearance {
            var y: CGFloat = 0
            if geometry.showsHeader {
                addRow(table.header, y: y, header: true)
                y += geometry.rowHeight

                let rule = NSView(frame: NSRect(
                    x: 0,
                    y: y,
                    width: geometry.width,
                    height: FocusCardMetrics.tableRuleHeight
                ))
                rule.wantsLayer = true
                rule.layer?.backgroundColor = CardPalette.hairline.cgColor
                grid.addSubview(rule)
                y += FocusCardMetrics.tableRuleHeight
            }

            for row in table.rows {
                addRow(row, y: y, header: false)
                y += geometry.rowHeight
            }
        }
    }

    private func addRow(_ cells: [String], y: CGFloat, header: Bool) {
        var x: CGFloat = 0
        for (column, source) in cells.enumerated() where column < geometry.columnWidths.count {
            let width = geometry.columnWidths[column]
            x += FocusCardMetrics.tableCellPadding
            let field = MarkdownRenderer.cellField(
                source,
                style: style,
                header: header,
                alignment: FocusCardMetrics.cellAlignment(table.alignments, column: column)
            )
            field.isSelectable = true
            field.frame = NSRect(
                x: x,
                y: y + FocusCardMetrics.tableRowPadding,
                width: width,
                height: geometry.rowHeight - FocusCardMetrics.tableRowPadding * 2
            )
            grid.addSubview(field)
            x += width + FocusCardMetrics.tableCellPadding
        }
    }
}
