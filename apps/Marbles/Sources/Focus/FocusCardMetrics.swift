import AppKit

/// Geometry for the Focus card, shared by `FocusCardView.layout()` and `LayoutEngine`
/// so the measured size and the drawn size can't drift.
///
/// The card's frame includes the marble that protrudes off the top: the top
/// `marbleOverhang` points of the frame are outside the card body, and only the body
/// draws a background. Everything below is measured from the body's top edge.
enum FocusCardMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 15
    static let gap: CGFloat = 12

    static let marbleDiameter: CGFloat = 72
    /// Half the marble sits above the body; the other half overlaps the body's top padding.
    static var marbleOverhang: CGFloat { marbleDiameter / 2 }

    static let titleHeight: CGFloat = 19
    static let ruleHeight: CGFloat = 1
    static let promptInset: CGFloat = 10
    /// The human's message is indented from the response below it, so the two read as a pair
    /// rather than one block of text.
    static let promptLeadingInset: CGFloat = 20
    static let promptCornerRadius: CGFloat = 8
    static let cornerRadius: CGFloat = 12

    /// Reserved on the right of every scrolling region so the knob never sits on the text.
    /// `SlimScroller` takes its track width from here — metrics stays free of the view layer so
    /// it can be compiled into the test target.
    static let scrollGutter: CGFloat = 8

    static let maxPromptHeight: CGFloat = 72
    /// Transcript viewport ceiling; it grows to this then scrolls (PRD §5).
    static let maxTranscriptHeight: CGFloat = 320

    /// Gap between transcript runs, and between tool rows inside one expanded run (PRD §10.5).
    static let runSpacing: CGFloat = 10
    static let toolRowSpacing: CGFloat = 6
    static let toolRowHeight: CGFloat = 18
    static let thinkingRowHeight: CGFloat = 18

    /// Gap between markdown blocks inside one prose run.
    static let blockSpacing: CGFloat = 6
    /// Inset inside a fenced code block's background.
    static let codeInset: CGFloat = 8
    static let codeCornerRadius: CGFloat = 6

    static var monoFont: NSFont { .monospacedSystemFont(ofSize: bodyFont.pointSize - 1, weight: .regular) }

    /// Style used for every measurement here; the view must render with the same one or the
    /// card's height and its contents drift apart.
    static func markdownStyle(text: NSColor, codeText: NSColor) -> MarkdownRenderer.Style {
        MarkdownRenderer.Style.card(body: bodyFont, text: text, codeText: codeText)
    }

    static let titleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)

    static var contentWidth: CGFloat { width - padding * 2 }
    /// Outer width of the prompt container, indented from the content column.
    static var promptWidth: CGFloat { contentWidth - promptLeadingInset }
    /// Text wraps inside the prompt container's inset, short of the scroll gutter.
    static var promptTextWidth: CGFloat { promptWidth - promptInset * 2 - scrollGutter }
    static var responseTextWidth: CGFloat { contentWidth - scrollGutter }

    /// Outer height of the prompt container, or 0 when there is no prompt to show.
    static func promptHeight(_ prompt: String?) -> CGFloat {
        guard let prompt, !prompt.isEmpty else { return 0 }
        let text = textHeight(prompt, font: bodyFont, width: promptTextWidth)
        return min(text + promptInset * 2, maxPromptHeight)
    }

    /// Whether a region's text exceeds its cap. `NSScrollView` flashes overlay scrollers every
    /// time the document size changes — and the response text changes on every store update — so
    /// the scroller is only attached when it is genuinely needed, rather than left to AppKit.
    static func promptOverflows(_ prompt: String?) -> Bool {
        guard let prompt, !prompt.isEmpty else { return false }
        return textHeight(prompt, font: bodyFont, width: promptTextWidth) + promptInset * 2 > maxPromptHeight
    }

    static func responseOverflows(_ response: String) -> Bool {
        guard !response.isEmpty else { return false }
        return textHeight(response, font: bodyFont, width: responseTextWidth) > maxTranscriptHeight
    }

    // MARK: - Transcript

    /// Defaults to no overrides, which is the PRD rule: newest and still working is open.
    static func runIsExpanded(
        _ run: TranscriptRun,
        isLast: Bool,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> Bool {
        guard case .tools(let calls) = run else { return false }
        return expansion.isExpanded(calls, isLast: isLast)
    }

    static func runHeight(
        _ run: TranscriptRun,
        isLast: Bool,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> CGFloat {
        switch run {
        case .prose(let text):
            return proseHeight(text, width: responseTextWidth)
        case .thinking:
            return thinkingRowHeight
        case .tools(let calls):
            guard runIsExpanded(run, isLast: isLast, expansion: expansion) else { return toolRowHeight }
            let n = CGFloat(calls.count)
            return n * toolRowHeight + max(n - 1, 0) * toolRowSpacing
        }
    }

    /// Height of one prose run once its markdown is broken into blocks.
    static func proseHeight(_ source: String, width: CGFloat) -> CGFloat {
        let blocks = MarkdownParser.blocks(source)
        guard !blocks.isEmpty else { return 0 }
        // Measurement is colour-independent; any opaque colour gives the same metrics.
        let style = markdownStyle(text: .labelColor, codeText: .labelColor)
        var height: CGFloat = 0
        for (index, block) in blocks.enumerated() {
            if index > 0 { height += blockSpacing }
            height += blockHeight(block, style: style, width: width)
        }
        return ceil(height)
    }

    static func blockHeight(
        _ block: MarkdownBlock,
        style: MarkdownRenderer.Style,
        width: CGFloat
    ) -> CGFloat {
        if case .code(_, let lines) = block {
            return codeHeight(lines)
        }
        return attributedHeight(MarkdownRenderer.attributed(block, style: style), width: width)
    }

    /// Fenced code never wraps, so its height is width-independent — but it must still be
    /// measured through TextKit. Deriving it from font metrics under-measured and clipped the
    /// last line, the same way `boundingRect` did for prose.
    static func codeHeight(_ lines: [String]) -> CGFloat {
        let body = lines.isEmpty ? " " : lines.joined(separator: "\n")
        let text = NSAttributedString(string: body, attributes: [.font: monoFont])
        return attributedHeight(text, width: .greatestFiniteMagnitude) + codeInset * 2
    }

    static func attributedHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0, width > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: text)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    /// Height the transcript wants before clamping.
    static func transcriptContentHeight(
        _ turn: TranscriptTurn,
        fallback: String,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> CGFloat {
        let runs = turn.runs
        guard !runs.isEmpty else {
            return textHeight(fallback, font: bodyFont, width: responseTextWidth)
        }
        var height: CGFloat = 0
        for (index, run) in runs.enumerated() {
            if index > 0 { height += runSpacing }
            height += runHeight(run, isLast: index == runs.count - 1, expansion: expansion)
        }
        return height
    }

    static func transcriptHeight(
        _ turn: TranscriptTurn,
        fallback: String,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> CGFloat {
        min(transcriptContentHeight(turn, fallback: fallback, expansion: expansion), maxTranscriptHeight)
    }

    static func transcriptOverflows(
        _ turn: TranscriptTurn,
        fallback: String,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> Bool {
        transcriptContentHeight(turn, fallback: fallback, expansion: expansion) > maxTranscriptHeight
    }

    static func responseHeight(_ response: String) -> CGFloat {
        guard !response.isEmpty else { return 0 }
        return min(textHeight(response, font: bodyFont, width: responseTextWidth), maxTranscriptHeight)
    }

    /// Total card size, marble included.
    ///
    /// The diameter is reserved, not the overhang: half the marble sits above the body, and the
    /// other half covers the body's top — content has to clear both.
    static func size(
        title: String?,
        prompt: String?,
        turn: TranscriptTurn,
        fallback: String,
        expansion: TranscriptExpansion = TranscriptExpansion()
    ) -> CGSize {
        var height = marbleDiameter + padding
        if !(title?.isEmpty ?? true) { height += titleHeight + gap + ruleHeight }
        let promptH = promptHeight(prompt)
        if promptH > 0 { height += gap + promptH }
        let transcript = transcriptHeight(turn, fallback: fallback, expansion: expansion)
        if transcript > 0 { height += gap + transcript }
        height += padding
        return CGSize(width: width, height: ceil(height))
    }

    /// Convenience for the no-transcript case: an empty turn renders `response` as the
    /// fallback line, which is exactly the pre-transcript layout.
    static func size(title: String?, prompt: String?, response: String) -> CGSize {
        size(title: title, prompt: prompt, turn: .empty, fallback: response)
    }

    /// Measured through TextKit rather than `NSAttributedString.boundingRect`, so the result
    /// matches what the card's `NSTextView` will actually lay out. `boundingRect` under-reports
    /// by a point or two per line, which clipped the last line of both regions.
    static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }
}
