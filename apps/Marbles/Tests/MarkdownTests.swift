import AppKit

enum MarkdownTests {
    static func run() {
        splitsParagraphs()
        parsesHeadings()
        parsesLists()
        parsesFencedCode()
        unterminatedFenceStillRenders()
        unsupportedSyntaxStaysText()
        inlineEmphasisChangesFont()
        inlineCodeUsesMonospace()
        measuresBlocksIndependently()
        codeHeightTracksLineCount()
    }

    private static var style: MarkdownRenderer.Style {
        FocusCardMetrics.markdownStyle(text: .labelColor, codeText: .labelColor)
    }

    // MARK: - Block parsing

    private static func splitsParagraphs() {
        let blocks = MarkdownParser.blocks("first line\nstill first\n\nsecond para")
        TestRun.expectEqual(blocks.count, 2, "blank line splits paragraphs")
        TestRun.expectEqual(blocks.first, .paragraph("first line\nstill first"), "soft breaks kept")
        TestRun.expectEqual(blocks.last, .paragraph("second para"), "second paragraph")
    }

    private static func parsesHeadings() {
        let blocks = MarkdownParser.blocks("# One\n## Two\n###### Six\n####### too many")
        TestRun.expectEqual(blocks.count, 4, "three headings plus a paragraph")
        TestRun.expectEqual(blocks[0], .heading(level: 1, text: "One"), "h1")
        TestRun.expectEqual(blocks[1], .heading(level: 2, text: "Two"), "h2")
        TestRun.expectEqual(blocks[2], .heading(level: 6, text: "Six"), "h6")
        if case .paragraph = blocks[3] {} else { TestRun.expect(false, "seven hashes is not a heading") }

        TestRun.expectEqual(
            MarkdownParser.blocks("#nospace").first,
            .paragraph("#nospace"),
            "a hash without a space is text"
        )
    }

    private static func parsesLists() {
        let bullets = MarkdownParser.blocks("- one\n* two\n+ three")
        TestRun.expectEqual(bullets.count, 3, "all three bullet markers")
        TestRun.expectEqual(bullets.first, .bullet("one"), "dash bullet")

        let numbered = MarkdownParser.blocks("1. first\n2. second")
        TestRun.expectEqual(numbered.count, 2, "two numbered items")
        TestRun.expectEqual(numbered.first, .numbered(marker: "1.", text: "first"), "marker retained")

        TestRun.expectEqual(
            MarkdownParser.blocks("1.no space").first,
            .paragraph("1.no space"),
            "a number without a space is text"
        )
    }

    private static func parsesFencedCode() {
        let blocks = MarkdownParser.blocks("before\n```swift\nlet x = 1\nlet y = 2\n```\nafter")
        TestRun.expectEqual(blocks.count, 3, "paragraph, code, paragraph")
        TestRun.expectEqual(
            blocks[1],
            .code(language: "swift", lines: ["let x = 1", "let y = 2"]),
            "language and lines captured verbatim"
        )
    }

    /// Agents stream, so a card can render mid-block.
    private static func unterminatedFenceStillRenders() {
        let blocks = MarkdownParser.blocks("```\npartial output")
        TestRun.expectEqual(blocks.count, 1, "one block")
        TestRun.expectEqual(blocks.first, .code(language: nil, lines: ["partial output"]), "renders as code")
    }

    /// Unsupported syntax must survive as the text the agent wrote, not vanish.
    private static func unsupportedSyntaxStaysText() {
        let table = "| a | b |\n| --- | --- |"
        let blocks = MarkdownParser.blocks(table)
        TestRun.expectEqual(blocks.count, 1, "table is one paragraph")
        TestRun.expectEqual(blocks.first, .paragraph(table), "table text preserved verbatim")

        let quote = MarkdownParser.blocks("> quoted").first
        TestRun.expectEqual(quote, .paragraph("> quoted"), "blockquote falls back to text")
    }

    // MARK: - Inline rendering

    private static func fonts(in text: NSAttributedString) -> [NSFont] {
        var out: [NSFont] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? NSFont { out.append(font) }
        }
        return out
    }

    private static func inlineEmphasisChangesFont() {
        let rendered = MarkdownRenderer.attributed(.paragraph("plain **bold** and *italic*"), style: style)
        TestRun.expect(!rendered.string.contains("**"), "markers are consumed, not shown")
        let traits = fonts(in: rendered).map { NSFontManager.shared.traits(of: $0) }
        TestRun.expect(traits.contains { $0.contains(.boldFontMask) }, "bold run present")
        TestRun.expect(traits.contains { $0.contains(.italicFontMask) }, "italic run present")
    }

    private static func inlineCodeUsesMonospace() {
        let rendered = MarkdownRenderer.attributed(.paragraph("call `focusCardSize()` now"), style: style)
        TestRun.expect(!rendered.string.contains("`"), "backticks consumed")
        let names = fonts(in: rendered).compactMap(\.fontName)
        TestRun.expect(
            names.contains { $0.lowercased().contains("mono") },
            "code span switches to a monospaced font"
        )
    }

    // MARK: - Measurement

    private static func measuresBlocksIndependently() {
        let width = FocusCardMetrics.responseTextWidth
        let one = FocusCardMetrics.proseHeight("just one line", width: width)
        let two = FocusCardMetrics.proseHeight("first para\n\nsecond para", width: width)
        TestRun.expect(two > one, "an extra block is taller")
        TestRun.expect(
            two >= one * 2 - 1,
            "two blocks include the spacing between them"
        )
        TestRun.expectNear(FocusCardMetrics.proseHeight("", width: width), 0, "empty prose has no height")

        // A heading is bigger than body text of the same string.
        let heading = FocusCardMetrics.proseHeight("# Title", width: width)
        let plain = FocusCardMetrics.proseHeight("Title", width: width)
        TestRun.expect(heading > plain, "headings are taller than body text")
    }

    private static func codeHeightTracksLineCount() {
        let three = FocusCardMetrics.codeHeight(["a", "b", "c"])
        let six = FocusCardMetrics.codeHeight(["a", "b", "c", "d", "e", "f"])
        TestRun.expect(six > three, "more lines is taller")
        TestRun.expect(FocusCardMetrics.codeHeight([]) > 0, "an empty block still has its inset")

        // Every line must fit — measuring from font metrics used to clip the last one.
        let lines = ["func f() {", "    let x = 1", "}"]
        let single = FocusCardMetrics.codeHeight(["only"])
        let perLine = single - FocusCardMetrics.codeInset * 2
        TestRun.expect(
            FocusCardMetrics.codeHeight(lines) >= perLine * 3 + FocusCardMetrics.codeInset * 2 - 1,
            "height covers every line, not n-1"
        )
        // Long lines scroll rather than wrap, so width must not affect height.
        let long = String(repeating: "x", count: 400)
        let blocks = MarkdownParser.blocks("```\n\(long)\n```")
        TestRun.expectNear(
            FocusCardMetrics.blockHeight(blocks[0], style: style, width: 100),
            FocusCardMetrics.blockHeight(blocks[0], style: style, width: 320),
            "code height is width-independent"
        )
    }
}
