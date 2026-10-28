import Foundation

public enum ComposeTone: String, CaseIterable, Sendable {
    case gitlab
    case teams

    public var displayName: String {
        switch self {
        case .gitlab: return "GitLab comment"
        case .teams: return "Teams chat"
        }
    }

    var guidance: String {
        switch self {
        case .gitlab:
            return "GitLab comment: clear and well structured. Markdown is fine when it helps (short paragraphs, bullet lists, `inline code`). Polite and direct."
        case .teams:
            return "Microsoft Teams chat: short, friendly-professional and conversational. No headings or heavy markdown. Prefer one to three sentences."
        }
    }
}

/// Every system prompt lives here. `extraInstructions` is the hook for a future
/// "context" feature that appends project- or client-specific guidance.
public enum Prompts {
    public static func composeSystem(tone: ComposeTone, extraInstructions: String? = nil) -> String {
        var prompt = """
        You help a Thai software developer write English messages to clients about software projects.
        The user writes a draft in Thai, rough English, or a mix. Rewrite it into natural, professional English that means exactly the same thing.

        Rules:
        - Keep the meaning. Never add facts, promises, commitments, estimates or dates that the draft does not contain, and do not drop any point.
        - Keep code, identifiers, file paths, commands, issue/MR references (like #123 or !45), URLs, @mentions and people's names exactly as written.
        - If a message being replied to is provided, use it only to understand the situation and make the reply fit. Do not answer things the draft does not address.
        - Tone: \(tone.guidance)

        Write two variants:
        - "polished": complete, natural and professional.
        - "concise": the shortest version that still keeps every point.
        For each variant also write "thai": one line of Thai explaining what the English says, so the user can check the meaning.

        Return JSON only, with no markdown fences and no commentary, exactly in this shape:
        {"polished":{"english":"...","thai":"..."},"concise":{"english":"...","thai":"..."}}
        """
        if let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            prompt += "\n\nAdditional context:\n" + extra
        }
        return prompt
    }

    public static func composeUser(draft: String, replyingTo context: String?) -> String {
        var message = ""
        if let context = context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            message += "<message_being_replied_to>\n\(context)\n</message_being_replied_to>\n\n"
        }
        message += "<draft>\n\(draft)\n</draft>"
        return message
    }

    public static func translateSystem(extraInstructions: String? = nil) -> String {
        var prompt = """
        You translate English text from software-project tools (GitLab, Microsoft Teams, email, documentation) into natural Thai for a Thai software developer.

        The input is a JSON array of objects {"n": number, "text": string}. Each one is a block of text read from the screen with OCR, so silently fix obvious OCR mistakes.

        Rules:
        - Write natural, fluent Thai the way a Thai developer would say it, not word-for-word.
        - Keep technical terms, code, identifiers, file names, commands, URLs, issue/MR numbers, product names and people's names in English, as Thai developers normally do (for example: merge request, deploy, pipeline, branch, staging, server). Write them in Latin letters; do not transliterate them into Thai script.
        - Copy URLs, file paths and identifiers exactly as given, character for character. Never add, drop or change underscores, hyphens, slashes, dots or letter case in them.
        - Translate every block separately, using the other blocks only as context.
        - If a block is not meaningful prose (only a name, a timestamp or a button label), return it unchanged.

        Return JSON only, with no markdown fences and no commentary: a JSON array of exactly N strings, where item i is the Thai translation of block n = i + 1.
        """
        if let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            prompt += "\n\nAdditional context:\n" + extra
        }
        return prompt
    }

    public static func translateUser(blocks: [String]) -> String {
        let items = blocks.enumerated().map { ["n": $0.offset + 1, "text": $0.element] as [String: Any] }
        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return "N = \(blocks.count)\n\(json)"
    }
}
