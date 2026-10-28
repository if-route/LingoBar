import AppKit

/// Full-screen transparent overlays (one per screen) for drag-to-select.
/// The completion receives the selection in AppKit global coordinates plus the
/// screen it lies on, or nil when cancelled.
@MainActor
final class RegionSelector {
    private var windows: [FloatingPanel] = []
    private var completion: ((CGRect, NSScreen)?) -> Void = { _ in }

    func begin(completion: @escaping ((CGRect, NSScreen)?) -> Void) {
        cancel()
        self.completion = completion
        let mouseScreen = screenContaining(NSEvent.mouseLocation)

        for screen in NSScreen.screens {
            let panel = FloatingPanel(contentRect: screen.frame)
            panel.level = .screenSaver
            panel.hasShadow = false
            panel.isMovableByWindowBackground = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.setFrame(screen.frame, display: false)

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak panel] localRect in
                guard let self, let panel else { return }
                let global = panel.convertToScreen(localRect)
                self.finish(global.width >= 6 && global.height >= 6 ? (global, screen) : nil)
            }
            panel.contentView = view
            panel.onEscape = { [weak self] in self?.finish(nil) }
            panel.orderFrontRegardless()
            if screen == mouseScreen {
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
            windows.append(panel)
        }
        NSCursor.crosshair.set()
    }

    func cancel() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private func finish(_ result: (CGRect, NSScreen)?) {
        cancel()
        NSCursor.arrow.set()
        let completion = self.completion
        self.completion = { _ in }
        completion(result)
    }
}

private final class SelectionView: NSView {
    var onFinish: ((NSRect) -> Void)?
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var mouse: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        mouse = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragCurrent = NSPoint(x: min(max(point.x, 0), bounds.maxX), y: min(max(point.y, 0), bounds.maxY))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect else { return }
        dragStart = nil
        dragCurrent = nil
        onFinish?(rect)
    }

    private var selectionRect: NSRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y)).integral
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.3)
        guard let selection = selectionRect else {
            dim.setFill()
            bounds.fill()
            if let mouse {
                // Guide lines double as a crosshair if the cursor change is ignored.
                NSColor.white.withAlphaComponent(0.6).setFill()
                NSRect(x: 0, y: mouse.y, width: bounds.width, height: 1).fill()
                NSRect(x: mouse.x, y: 0, width: 1, height: bounds.height).fill()
            }
            return
        }
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: selection))
        path.windingRule = .evenOdd
        dim.setFill()
        path.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        var origin = NSPoint(x: selection.minX, y: selection.minY - labelSize.height - 4)
        if origin.y < 0 { origin.y = selection.minY + 4 }
        label.draw(at: origin, withAttributes: attributes)
    }
}
