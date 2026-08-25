import Foundation

enum JSONC {
    enum ParseError: Error, Equatable {
        case invalid
    }

    static func stripComments(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var index = input.startIndex
        var inString = false
        var escape = false
        var lineComment = false
        var blockComment = false
        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)
            if lineComment {
                if character == "\n" {
                    lineComment = false
                    out.append(character)
                }
                index = next
                continue
            }
            if blockComment {
                if character == "*", next < input.endIndex, input[next] == "/" {
                    blockComment = false
                    index = input.index(after: next)
                } else {
                    index = next
                }
                continue
            }
            if inString {
                out.append(character)
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }
            if character == "\"" {
                inString = true
                out.append(character)
                index = next
                continue
            }
            if character == "/", next < input.endIndex, input[next] == "/" {
                lineComment = true
                index = next
                continue
            }
            if character == "/", next < input.endIndex, input[next] == "*" {
                blockComment = true
                index = next
                continue
            }
            out.append(character)
            index = next
        }
        return out
    }

    static func parseObject(_ text: String) throws -> [String: Any] {
        let stripped = stripComments(text)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [:]
        }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ParseError.invalid
        }
        return object
    }

    static func comments(in text: String) -> [String] {
        text.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
        }
    }

    static func stringify(_ object: [String: Any], preservingCommentsFrom original: String?) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard var json = String(data: data, encoding: .utf8) else {
            throw ParseError.invalid
        }
        let kept = comments(in: original ?? "")
        if !kept.isEmpty, json.hasPrefix("{") {
            let block = kept.map { "  \($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n")
            json = "{\n\(block)\n" + json.dropFirst().drop(while: { $0 == "\n" || $0 == " " })
        }
        if !json.hasSuffix("\n") {
            json.append("\n")
        }
        return json
    }
}
