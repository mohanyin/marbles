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
    case table(MarkdownTable)
}

/// A GitHub-flavoured table. Cells hold inline markdown source, resolved at render time like
/// every other block.
struct MarkdownTable: Equatable {
    enum Alignment: Equatable {
        case leading
        case center
        case trailing
    }

    var header: [String]
    var alignments: [Alignment]
    /// Every row is padded or trimmed to the header's column count, so layout never has to
    /// reason about ragged input.
    var rows: [[String]]

    var columnCount: Int { header.count }
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

        let lines = source.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            defer { index += 1 }
            let line = lines[index]
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
            // A table is a row followed by a delimiter row; without the delimiter it is prose
            // that merely contains pipes.
            if let table = table(at: index, in: lines) {
                flushParagraph()
                blocks.append(.table(table.value))
                index = table.lastIndex
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

    // MARK: - Tables

    private static func table(at start: Int, in lines: [String]) -> (value: MarkdownTable, lastIndex: Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|") else { return nil }
        let header = cells(headerLine)
        guard !header.isEmpty else { return nil }

        let delimiter = cells(lines[start + 1].trimmingCharacters(in: .whitespaces))
        guard delimiter.count == header.count, isDelimiterRow(delimiter) else { return nil }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.contains("|") else { break }
            var row = cells(line)
            // Ragged rows are common in hand-written tables; normalise here so layout never sees them.
            if row.count < header.count {
                row.append(contentsOf: Array(repeating: "", count: header.count - row.count))
            } else if row.count > header.count {
                row = Array(row.prefix(header.count))
            }
            rows.append(row)
            index += 1
        }

        let table = MarkdownTable(
            header: header,
            alignments: delimiter.map(alignment(of:)),
            rows: rows
        )
        return (table, index - 1)
    }

    private static func isDelimiterRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            var body = cell.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return false }
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    private static func alignment(of delimiter: String) -> MarkdownTable.Alignment {
        let body = delimiter.trimmingCharacters(in: .whitespaces)
        let leading = body.hasPrefix(":")
        let trailing = body.hasSuffix(":")
        if leading && trailing { return .center }
        if trailing { return .trailing }
        return .leading
    }

    /// Split a row on its pipes. Pipes inside inline code spans and escaped pipes are literal.
    static func cells(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inCode = false
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\":
                escaped = true
                current.append(character)
            case "`":
                inCode.toggle()
                current.append(character)
            case "|" where !inCode:
                out.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        out.append(current)
        // Surrounding pipes produce empty cells at each end; a bare `| |` header does not.
        if line.hasPrefix("|"), !out.isEmpty { out.removeFirst() }
        if line.hasSuffix("|"), !out.isEmpty { out.removeLast() }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
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
