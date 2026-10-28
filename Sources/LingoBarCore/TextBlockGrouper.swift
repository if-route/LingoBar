import CoreGraphics
import Foundation

public struct TextLine: Equatable, Sendable {
    public let text: String
    /// Bottom-left based rect in a uniform unit (points or pixels, not normalized,
    /// so horizontal and vertical distances are comparable).
    public let rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

public struct TextBlock: Equatable, Sendable {
    public let text: String
    public let rect: CGRect
    public let lines: [TextLine]
}

/// Groups OCR lines into paragraphs so they can be translated as a whole.
public struct TextBlockGrouper {
    /// Maximum vertical gap between consecutive lines, as a fraction of line height.
    public var maxGapRatio: CGFloat = 0.75
    /// Maximum left-edge offset between consecutive lines, as a multiple of line height.
    public var maxIndentRatio: CGFloat = 1.5
    /// Lines whose heights differ more than this ratio (e.g. heading vs body) are split.
    public var maxHeightRatio: CGFloat = 1.6

    public init() {}

    public func group(_ lines: [TextLine]) -> [TextBlock] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { lhs, rhs in
                abs(lhs.rect.maxY - rhs.rect.maxY) > min(lhs.rect.height, rhs.rect.height) / 2
                    ? lhs.rect.maxY > rhs.rect.maxY
                    : lhs.rect.minX < rhs.rect.minX
            }

        var groups: [[TextLine]] = []
        for line in sorted {
            var best: (index: Int, score: CGFloat)?
            for (index, group) in groups.enumerated() {
                guard let last = group.last, let score = joinScore(previous: last, next: line) else { continue }
                if best == nil || score < best!.score {
                    best = (index, score)
                }
            }
            if let best {
                groups[best.index].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups
            .map(makeBlock)
            .sorted { lhs, rhs in
                abs(lhs.rect.maxY - rhs.rect.maxY) > 1 ? lhs.rect.maxY > rhs.rect.maxY : lhs.rect.minX < rhs.rect.minX
            }
    }

    /// Lower is better; nil means the lines don't belong together.
    func joinScore(previous: TextLine, next: TextLine) -> CGFloat? {
        let a = previous.rect
        let b = next.rect
        let height = (a.height + b.height) / 2
        guard height > 0 else { return nil }
        guard max(a.height, b.height) / max(min(a.height, b.height), 0.0001) <= maxHeightRatio else { return nil }

        let gap = a.minY - b.maxY
        guard gap > -0.5 * height, gap <= maxGapRatio * height else { return nil }

        let indent = abs(a.minX - b.minX)
        guard indent <= maxIndentRatio * height else { return nil }

        return gap / height + indent / height
    }

    func makeBlock(_ lines: [TextLine]) -> TextBlock {
        let rect = lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) }
        var text = ""
        for line in lines {
            let piece = line.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                text = piece
            } else if text.hasSuffix("-"), let first = piece.first, first.isLowercase {
                // Re-join a word hyphenated across a line break.
                text.removeLast()
                text += piece
            } else {
                text += " " + piece
            }
        }
        return TextBlock(text: text, rect: rect, lines: lines)
    }
}
