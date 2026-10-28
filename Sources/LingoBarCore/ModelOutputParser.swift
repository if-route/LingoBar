import Foundation

public struct ComposeVariant: Equatable, Sendable {
    public let label: String
    public let english: String
    public let thai: String

    public init(label: String, english: String, thai: String) {
        self.label = label
        self.english = english
        self.thai = thai
    }
}

public enum ModelOutputError: LocalizedError, Equatable {
    case noUsableJSON(snippet: String)
    case countMismatch(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .noUsableJSON(let snippet):
            return "Could not parse the model output as the expected JSON.\n\nOutput: \(snippet)"
        case .countMismatch(let expected, let got):
            return "Expected \(expected) translations but the model returned \(got)."
        }
    }
}

public enum ModelOutputParser {
    static let composeKeys: [(key: String, label: String)] = [("polished", "Polished"), ("concise", "Concise")]

    /// Expects `{"polished": {"english": "...", "thai": "..."}, "concise": {...}}`,
    /// tolerating a few alternative key spellings.
    public static func parseCompose(_ text: String) throws -> [ComposeVariant] {
        for candidate in JSONExtractor.candidates(from: text) {
            guard let dict = lowercasedKeys(candidate) else { continue }
            var variants: [ComposeVariant] = []
            for (key, label) in composeKeys {
                guard let raw = dict[key] else { break }
                if let english = raw as? String {
                    variants.append(ComposeVariant(label: label, english: english, thai: ""))
                } else if let inner = lowercasedKeys(raw),
                          let english = firstString(in: inner, keys: ["english", "en", "text"]) {
                    let thai = firstString(in: inner, keys: ["thai", "th", "gloss", "thai_gloss"]) ?? ""
                    variants.append(ComposeVariant(label: label, english: english, thai: thai))
                }
            }
            if variants.count == composeKeys.count {
                return variants
            }
        }
        throw ModelOutputError.noUsableJSON(snippet: snippet(text))
    }

    /// Expects a JSON array of `expectedCount` Thai strings (objects with a
    /// translation field are accepted too). Extra items are dropped.
    public static func parseTranslations(_ text: String, expectedCount: Int) throws -> [String] {
        var bestShortCount: Int?
        for candidate in JSONExtractor.candidates(from: text) {
            var array = candidate as? [Any]
            if array == nil, let dict = lowercasedKeys(candidate) {
                array = dict["translations"] as? [Any]
            }
            guard let items = array else { continue }
            let strings = items.compactMap { item -> String? in
                if let string = item as? String { return string }
                if let inner = lowercasedKeys(item) {
                    return firstString(in: inner, keys: ["thai", "th", "translation", "text"])
                }
                return nil
            }
            guard strings.count == items.count else { continue }
            if strings.count >= expectedCount {
                return Array(strings.prefix(expectedCount))
            }
            bestShortCount = max(bestShortCount ?? 0, strings.count)
        }
        if let got = bestShortCount {
            throw ModelOutputError.countMismatch(expected: expectedCount, got: got)
        }
        throw ModelOutputError.noUsableJSON(snippet: snippet(text))
    }

    private static func lowercasedKeys(_ value: Any) -> [String: Any]? {
        guard let dict = value as? [String: Any] else { return nil }
        return Dictionary(dict.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String { return value }
        }
        return nil
    }

    static func snippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
    }
}
