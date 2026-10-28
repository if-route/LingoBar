import AppKit

/// Borderless floating panel that can take keyboard focus without activating
/// LingoBar, so the user's app stays frontmost. Intercepts keys by key code so
/// shortcuts work under the Thai layout too.
class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// Return true to swallow the event.
    var keyHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect, focusable: Bool = true) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.focusable = focusable
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private var focusable = true
    override var canBecomeKey: Bool { focusable }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == KeyCode.escape, let onEscape {
                onEscape()
                return
            }
            if let keyHandler, keyHandler(event) {
                return
            }
        }
        super.sendEvent(event)
    }
}

enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let digit1: UInt16 = 18
    static let digit2: UInt16 = 19
    static let v: UInt16 = 9
}

/// Rounded, vibrant background used by all LingoBar panels.
func makePanelBackground(material: NSVisualEffectView.Material = .popover, cornerRadius: CGFloat = 10) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.masksToBounds = true
    return view
}

/// Short-lived, click-through HUD message.
enum Toast {
    private static var current: NSPanel?

    static func show(_ message: String, near point: NSPoint? = nil, duration: TimeInterval = 1.8) {
        current?.orderOut(nil)

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 320
        let textSize = label.fittingSize
        let size = NSSize(width: textSize.width + 28, height: textSize.height + 18)

        let screen = point.flatMap(screenContaining) ?? screenContaining(NSEvent.mouseLocation) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = point.map { NSPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2) }
            ?? NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.25)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        let panel = FloatingPanel(contentRect: NSRect(origin: origin, size: size), focusable: false)
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        let background = makePanelBackground(material: .hudWindow)
        background.frame = NSRect(origin: .zero, size: size)
        label.frame = NSRect(x: 14, y: 9, width: textSize.width, height: textSize.height)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()
        current = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard current === panel else { return }
            panel.orderOut(nil)
            current = nil
        }
    }
}

func screenContaining(_ point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
}
