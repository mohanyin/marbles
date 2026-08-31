import Foundation

/// A block of agent prose. Inline syntax (bold, italic, code spans) stays in the payload and is
/// resolved at render time; only block structure is parsed here.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(marker: String, text: String)
    /// Verbatim lines. Never wrapped — a fenced block scrolls sideways instead (PRD §5.1).
    case code(language: String?, lines: [String])
}

/// Block-level markdown, line by line.
///
/// Deliberately small: headings, the two list flavours, and fenced code. Anything else is a
/// paragraph, which is the right failure mode — unsupported syntax renders as the text the agent
/// actually wrote rather than disappearing.
enum MarkdownParser {
    static func blocks(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var codeLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceLanguage(trimmed) {
                if code == nil {
                    flushParagraph()
                    code = []
                    codeLanguage = fence.isEmpty ? nil : fence
                } else {
                    blocks.append(.code(language: codeLanguage, lines: code ?? []))
                    code = nil
                    codeLanguage = nil
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let bullet = bullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }
            if let numbered = numbered(trimmed) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }
            paragraph.append(line)
        }

        // An unterminated fence still renders as code — agents stream partial output.
        if let code {
            blocks.append(.code(language: codeLanguage, lines: code))
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line classification

    private static func fenceLanguage(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#", level < 6 {
            level += 1
            index = trimmed.index(after: index)
        }
        guard level > 0, index < trimmed.endIndex, trimmed[index] == " " else { return nil }
        let text = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func bullet(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let text = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numbered(_ trimmed: String) -> MarkdownBlock? {
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, index < trimmed.endIndex, trimmed[index] == "." else { return nil }
        let afterDot = trimmed.index(after: index)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let text = String(trimmed[afterDot...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .numbered(marker: "\(digits).", text: text)
    }
}
