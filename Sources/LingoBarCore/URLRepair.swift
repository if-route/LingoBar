import Foundation

/// Repairs URL damage that Vision OCR causes on underlined links. The link
/// underline sits on the underscore glyph, so `work_items` is read as
/// `work items` (or `work_ items`), and it can turn GitLab's `/-/` into `/=/`.
///
/// Only a token that starts with `http(s)://` and already has a path is touched.
/// The token right after it is joined with `_` only when it is a lowercase word
/// directly followed by `/` and a remainder containing a digit or another `/`
/// (`items/1909`). That shape keeps prose such as `and/or`, `read/write` or
/// `3/4 jobs` out of the URL.
public enum URLRepair {
    private static let url = try! NSRegularExpression(pattern: #"^[(<\["']?https?://[^\s/]+/\S*$"#, options: [.caseInsensitive])
    private static let continuation = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9]*/(?=\S*[0-9/])\S+$"#)

    public static func repair(_ text: String) -> String {
        guard text.contains("://") else { return text }
        let tokens = text.components(separatedBy: " ")
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            var token = tokens[index]
            index += 1
            if matches(url, token) {
                while index < tokens.count, endsInPathWord(token), matches(continuation, tokens[index]) {
                    token += (token.hasSuffix("_") ? "" : "_") + tokens[index]
                    index += 1
                }
                token = token.replacingOccurrences(of: "/=/", with: "/-/")
            }
            output.append(token)
        }
        return output.joined(separator: " ")
    }

    /// A URL ending in `.`, `)` or `/` is complete, so the next word is prose.
    private static func endsInPathWord(_ token: String) -> Bool {
        guard let last = token.unicodeScalars.last else { return false }
        return last == "_" || (last.isASCII && CharacterSet.alphanumerics.contains(last))
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}
