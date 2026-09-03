import AppKit

/// Turns block markdown into attributed text ready to lay out.
///
/// Colours and fonts are passed in rather than read from `CardPalette`, so this stays free of the
/// view layer and can be compiled into the test target alongside `FocusCardMetrics` — which has to
/// measure exactly what gets drawn.
enum MarkdownRenderer {
    struct Style {
        var body: NSFont
        var mono: NSFont
        var text: NSColor
        var codeText: NSColor
        var listIndent: CGFloat = 14

        static func card(body: NSFont, text: NSColor, codeText: NSColor) -> Style {
            Style(
                body: body,
                mono: .monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular),
                text: text,
                codeText: codeText
            )
        }
    }

    /// Attributed text for one non-code block. Code blocks are laid out separately: they must not
    /// wrap, so they cannot share a text container with prose.
    static func attributed(_ block: MarkdownBlock, style: Style) -> NSAttributedString {
        switch block {
        case .paragraph(let source):
            return inline(source, font: style.body, style: style, paragraph: nil)
        case .heading(let level, let text):
            return inline(text, font: headingFont(level: level, base: style.body), style: style, paragraph: nil)
        case .bullet(let source):
            return listItem(marker: "•", source: source, style: style)
        case .numbered(let marker, let text):
            return listItem(marker: marker, source: text, style: style)
        case .code, .table:
            return NSAttributedString()
        }
    }

    /// Attributed text for one table cell. The header is semibold; body cells match prose.
    static func cell(_ source: String, style: Style, header: Bool) -> NSAttributedString {
        let font = header
            ? NSFont.systemFont(ofSize: style.body.pointSize, weight: .semibold)
            : style.body
        return inline(source, font: font, style: style, paragraph: nil)
    }

    /// The one place a table cell's field is configured.
    ///
    /// Measurement and drawing both go through here. Configuring a field two ways and measuring
    /// only one of them is how the last four geometry bugs happened — `lineBreakMode` and
    /// `alignment` alone add 4pt to a field's required width, which clipped the final character
    /// of every centred column.
    static func cellField(
        _ source: String,
        style: Style,
        header: Bool,
        alignment: NSTextAlignment
    ) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: cell(source, style: style, header: header))
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.alignment = alignment
        return field
    }

    static func headingFont(level: Int, base: NSFont) -> NSFont {
        let size = base.pointSize + (level <= 1 ? 3 : level == 2 ? 2 : 1)
        return .systemFont(ofSize: size, weight: .semibold)
    }

    // MARK: - Inline

    /// Bold, italic, and code spans. `NSAttributedString(markdown:)` handles the parsing; the
    /// intents it records are mapped onto real fonts here, since it only marks them semantically.
    static func inline(
        _ source: String,
        font: NSFont,
        style: Style,
        paragraph: NSParagraphStyle?
    ) -> NSAttributedString {
        let base: NSMutableAttributedString
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: source, options: options) {
            base = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        } else {
            // Malformed markdown renders as the literal text the agent wrote.
            base = NSMutableAttributedString(string: source)
        }

        let full = NSRange(location: 0, length: base.length)
        base.addAttribute(.font, value: font, range: full)
        base.addAttribute(.foregroundColor, value: style.text, range: full)
        if let paragraph {
            base.addAttribute(.paragraphStyle, value: paragraph, range: full)
        }

        base.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            guard let raw = value as? UInt else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            if intent.contains(.code) {
                base.addAttribute(.font, value: style.mono, range: range)
                base.addAttribute(.foregroundColor, value: style.codeText, range: range)
                return
            }
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            guard !traits.isEmpty else { return }
            let converted = NSFontManager.shared.convert(font, toHaveTrait: traits)
            base.addAttribute(.font, value: converted, range: range)
        }
        return base
    }

    private static func listItem(marker: String, source: String, style: Style) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // Hanging indent so wrapped lines align under the text, not the marker.
        paragraph.headIndent = style.listIndent
        paragraph.firstLineHeadIndent = 0
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: style.listIndent)]

        let body = inline(source, font: style.body, style: style, paragraph: paragraph)
        let out = NSMutableAttributedString(
            string: "\(marker)\t",
            attributes: [
                .font: style.body,
                .foregroundColor: style.text,
                .paragraphStyle: paragraph,
            ]
        )
        out.append(body)
        out.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: out.length))
        return out
    }
}
