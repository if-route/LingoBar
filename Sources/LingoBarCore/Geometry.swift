import CoreGraphics

/// Coordinate systems in play:
/// - AppKit global: points, bottom-left origin at the primary screen's bottom-left.
/// - ScreenCaptureKit `sourceRect`: points, top-left origin, relative to one display.
/// - Vision `boundingBox`: normalized 0...1, bottom-left origin, relative to the captured image.
public enum CoordinateMapper {
    /// AppKit global rect -> ScreenCaptureKit display-local, top-left rect.
    public static func displayLocalTopLeftRect(globalRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: screenFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// Output pixel dimensions for a capture of `rect` (points) at `scale` (backing scale factor).
    public static func pixelSize(for rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((rect.width * scale).rounded())), max(1, Int((rect.height * scale).rounded())))
    }

    /// Vision normalized bottom-left box inside `region` -> AppKit global rect.
    /// Both systems are bottom-left based, so no flip is needed.
    public static func globalRect(normalized box: CGRect, in region: CGRect) -> CGRect {
        CGRect(
            x: region.minX + box.minX * region.width,
            y: region.minY + box.minY * region.height,
            width: box.width * region.width,
            height: box.height * region.height
        )
    }
}

/// Places translation panels beside their source blocks.
public enum PanelLayout {
    /// Returns one frame per block. Prefers the right side of the block, then
    /// below, then above; keeps every frame inside `visibleFrame` and pushes
    /// frames apart vertically when they would overlap earlier ones or `obstacles`.
    public static func frames(
        blocks: [CGRect],
        sizes: [CGSize],
        visibleFrame: CGRect,
        obstacles: [CGRect] = [],
        spacing: CGFloat = 8
    ) -> [CGRect] {
        precondition(blocks.count == sizes.count)
        var placed: [CGRect] = []
        let inset = visibleFrame.insetBy(dx: 4, dy: 4)

        for (block, size) in zip(blocks, sizes) {
            let size = CGSize(width: min(size.width, inset.width), height: min(size.height, inset.height))
            var frame: CGRect
            let rightX = block.maxX + spacing
            if rightX + size.width <= inset.maxX {
                frame = CGRect(x: rightX, y: block.maxY - size.height, width: size.width, height: size.height)
            } else {
                frame = CGRect(x: block.minX, y: block.minY - spacing - size.height, width: size.width, height: size.height)
                if frame.minY < inset.minY {
                    frame.origin.y = block.maxY + spacing
                }
            }
            frame = clamp(frame, to: inset)
            frame = resolveOverlap(frame, against: obstacles + placed, within: inset, spacing: spacing)
            placed.append(frame)
        }
        return placed
    }

    static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    static func resolveOverlap(_ frame: CGRect, against others: [CGRect], within bounds: CGRect, spacing: CGFloat) -> CGRect {
        func collision(_ candidate: CGRect) -> CGRect? {
            others.first { $0.insetBy(dx: -spacing / 2, dy: -spacing / 2).intersects(candidate) }
        }
        // Try pushing down first, then up; give up (keep overlap) if neither fits.
        for direction in [-1.0, 1.0] as [CGFloat] {
            var candidate = frame
            for _ in 0..<(others.count + 1) {
                guard let hit = collision(candidate) else {
                    return candidate
                }
                candidate.origin.y = direction < 0
                    ? hit.minY - spacing - candidate.height
                    : hit.maxY + spacing
                if candidate.minY < bounds.minY || candidate.maxY > bounds.maxY { break }
            }
        }
        return frame
    }
}
