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
            return proseView(text, muted: false)
        case .thinking:
            return labelRow("Thinking…", color: CardPalette.ink.withAlphaComponent(0.45))
        case .tools(let calls):
            return expanded ? toolStack(calls, width: width) : collapsedRow(calls)
        }
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
