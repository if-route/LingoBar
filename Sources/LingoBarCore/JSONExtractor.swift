import Foundation

/// Pulls JSON values out of model output that may be wrapped in ```json fences
/// or surrounded by prose.
public enum JSONExtractor {
    /// All top-level JSON objects/arrays found in `text`, most likely first.
    /// Callers pick the first candidate that has the shape they expect, because
    /// prose such as "see [1]" can itself parse as JSON.
    public static func candidates(from text: String) -> [Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [Any] = []
        if let whole = parseContainer(trimmed) {
            results.append(whole)
        }
        for block in fencedBlocks(in: trimmed) {
            if let value = parseContainer(block) {
                results.append(value)
            }
        }
        results.append(contentsOf: balancedContainers(in: trimmed))
        return results
    }

    static func parseContainer(_ text: String) -> Any? {
        guard let first = text.first, first == "{" || first == "[" else { return nil }
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              value is [Any] || value is [String: Any] else { return nil }
        return value
    }

    static func fencedBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var searchStart = text.startIndex
        while let open = text.range(of: "```", range: searchStart..<text.endIndex) {
            var contentStart = open.upperBound
            if let newline = text[contentStart...].firstIndex(of: "\n") {
                let tag = text[contentStart..<newline].trimmingCharacters(in: .whitespaces)
                if tag.allSatisfy({ $0.isLetter }) {
                    contentStart = text.index(after: newline)
                }
            }
            guard let close = text.range(of: "```", range: contentStart..<text.endIndex) else {
                blocks.append(String(text[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines))
                break
            }
            blocks.append(String(text[contentStart..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            searchStart = close.upperBound
        }
        return blocks
    }

    /// Scans bytes for bracket-balanced spans (string- and escape-aware) and
    /// returns the ones that parse. Working on UTF-8 bytes is safe because every
    /// structural character is ASCII and never appears inside a multi-byte sequence.
    static func balancedContainers(in text: String) -> [Any] {
        let bytes = Array(text.utf8)
        var results: [Any] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == openBrace || byte == openBracket, let end = matchingEnd(bytes, from: index) {
                if let value = try? JSONSerialization.jsonObject(with: Data(bytes[index...end])),
                   value is [Any] || value is [String: Any] {
                    results.append(value)
                    index = end + 1
                    continue
                }
            }
            index += 1
        }
        return results
    }

    private static let openBrace = UInt8(ascii: "{")
    private static let closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "[")
    private static let closeBracket = UInt8(ascii: "]")
    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")

    static func matchingEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var stack: [UInt8] = []
        var inString = false
        var escaped = false
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == backslash {
                    escaped = true
                } else if byte == quote {
                    inString = false
                }
            } else if byte == quote {
                inString = true
            } else if byte == openBrace || byte == openBracket {
                stack.append(byte)
            } else if byte == closeBrace || byte == closeBracket {
                guard let open = stack.popLast(),
                      (open == openBrace && byte == closeBrace) || (open == openBracket && byte == closeBracket)
                else { return nil }
                if stack.isEmpty { return index }
            }
            index += 1
        }
        return nil
    }
}
