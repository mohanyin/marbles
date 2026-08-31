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
    static let maxResponseHeight: CGFloat = 200

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
        return textHeight(response, font: bodyFont, width: responseTextWidth) > maxResponseHeight
    }

    static func responseHeight(_ response: String) -> CGFloat {
        guard !response.isEmpty else { return 0 }
        return min(textHeight(response, font: bodyFont, width: responseTextWidth), maxResponseHeight)
    }

    /// Total card size, marble included.
    ///
    /// The diameter is reserved, not the overhang: half the marble sits above the body, and the
    /// other half covers the body's top — content has to clear both.
    static func size(title: String?, prompt: String?, response: String) -> CGSize {
        var height = marbleDiameter + padding

        let hasTitle = !(title?.isEmpty ?? true)
        if hasTitle {
            height += titleHeight + gap + ruleHeight
        }

        let promptH = promptHeight(prompt)
        if promptH > 0 {
            height += gap + promptH
        }

        let responseH = responseHeight(response)
        if responseH > 0 {
            height += gap + responseH
        }

        height += padding
        return CGSize(width: width, height: ceil(height))
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
