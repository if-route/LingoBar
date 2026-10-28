import CoreGraphics
import Vision

public struct RecognizedLine: Sendable {
    public let text: String
    /// Vision bounding box: normalized, bottom-left origin, relative to the image.
    public let normalizedBox: CGRect
}

public enum TextRecognizer {
    /// Synchronous; call off the main thread for large images.
    public static func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, normalizedBox: observation.boundingBox)
        }
    }

    /// OCR + paragraph grouping, with block rects in the `region` coordinate space
    /// (AppKit global points when `region` is the captured screen rect).
    public static func blocks(in image: CGImage, region: CGRect, grouper: TextBlockGrouper = TextBlockGrouper()) throws -> [TextBlock] {
        let lines = try recognize(image).map {
            TextLine(text: $0.text, rect: CoordinateMapper.globalRect(normalized: $0.normalizedBox, in: region))
        }
        return grouper.group(lines).map {
            TextBlock(text: URLRepair.repair($0.text), rect: $0.rect, lines: $0.lines)
        }
    }
}
