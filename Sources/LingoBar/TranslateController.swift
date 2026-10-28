import AppKit
import LingoBarCore

/// Select region -> capture -> OCR -> group -> one LLM call -> Thai bubbles beside each block.
@MainActor
final class TranslateController {
    var onReply: ((String) -> Void)?

    private let selector = RegionSelector()
    private var bubbles: [TranslationBubble] = []
    private var toolbar: TranslateToolbar?
    private var blocks: [TextBlock] = []
    private var translations: [String]?
    private var screen: NSScreen?
    private var task: Task<Void, Never>?
    /// Bumped on every dismiss so late results from an old run are dropped.
    private var generation = 0

    func start() {
        dismiss()
        guard ScreenCapture.hasPermission else {
            ScreenCapture.showPermissionHelp()
            return
        }
        selector.begin { [weak self] selection in
            guard let self, let (rect, screen) = selection else { return }
            let generation = self.generation
            self.task = Task { await self.run(rect: rect, screen: screen, generation: generation) }
        }
    }

    func dismiss() {
        generation += 1
        task?.cancel()
        task = nil
        selector.cancel()
        bubbles.forEach { $0.close() }
        bubbles.removeAll()
        toolbar?.close()
        toolbar = nil
        blocks = []
        translations = nil
    }

    private func run(rect: CGRect, screen: NSScreen, generation: Int) async {
        let blocks: [TextBlock]
        let region: CGRect
        do {
            let capture = try await ScreenCapture.capture(globalRect: rect, on: screen)
            region = capture.region
            let image = capture.image
            blocks = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.blocks(in: image, region: region)
            }.value
        } catch ScreenCaptureError.permissionDenied {
            ScreenCapture.showPermissionHelp()
            return
        } catch {
            Toast.show(error.localizedDescription, near: NSPoint(x: rect.midX, y: rect.midY), duration: 5)
            return
        }
        guard generation == self.generation else { return }
        guard !blocks.isEmpty else {
            Toast.show("No text found", near: NSPoint(x: region.midX, y: region.midY))
            return
        }

        self.blocks = blocks
        self.screen = screen
        showToolbar(region: region, screen: screen)
        bubbles = blocks.indices.map { index in
            let bubble = TranslationBubble()
            bubble.onEscape = { [weak self] in self?.dismiss() }
            bubble.onClick = { [weak self] in self?.copyBlock(index) }
            bubble.onDoubleClick = { [weak self] in self?.replyToBlock(index) }
            bubble.show(text: "Translating…", style: .loading)
            return bubble
        }
        relayout()

        let model = Settings.translateModel
        toolbar?.setStatus("Translating with \(model.displayName)…")
        do {
            let raw = try await Settings.makeClient().complete(
                system: Prompts.translateSystem(),
                user: Prompts.translateUser(blocks: blocks.map(\.text)),
                model: model
            )
            let thai = try ModelOutputParser.parseTranslations(raw, expectedCount: blocks.count)
            guard generation == self.generation else { return }
            translations = thai
            for (bubble, text) in zip(bubbles, thai) {
                bubble.show(text: text, style: .translation)
            }
            toolbar?.setStatus(nil)
            toolbar?.setCopyEnabled(true)
        } catch {
            guard generation == self.generation else { return }
            for (index, bubble) in bubbles.enumerated() {
                bubble.show(text: index == 0 ? "Translation failed: \(error.localizedDescription)" : "Translation failed.", style: .error)
            }
            toolbar?.setStatus("Failed")
        }
        relayout()
    }

    private func showToolbar(region: CGRect, screen: NSScreen) {
        let toolbar = TranslateToolbar()
        toolbar.onCopy = { [weak self] in self?.copyThai() }
        toolbar.onReply = { [weak self] in
            guard let self, !self.blocks.isEmpty else { return }
            self.onReply?(self.blocks.map(\.text).joined(separator: "\n\n"))
        }
        toolbar.onClose = { [weak self] in self?.dismiss() }
        toolbar.place(near: region, visibleFrame: screen.visibleFrame)
        toolbar.panel.makeKeyAndOrderFront(nil)
        self.toolbar = toolbar
    }

    private func relayout() {
        guard let screen else { return }
        let sizes = bubbles.map { $0.preferredSize() }
        let frames = PanelLayout.frames(
            blocks: blocks.map(\.rect),
            sizes: sizes,
            visibleFrame: screen.visibleFrame,
            obstacles: toolbar.map { [$0.panel.frame] } ?? []
        )
        for (bubble, frame) in zip(bubbles, frames) {
            bubble.setFrame(frame)
        }
    }

    private func copyBlock(_ index: Int) {
        guard let translations, translations.indices.contains(index) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translations[index], forType: .string)
        bubbles[index].flashCopied()
    }

    private func replyToBlock(_ index: Int) {
        guard blocks.indices.contains(index) else { return }
        let original = blocks[index].text
        let generation = generation
        // Deferred so the bubble is not torn down inside its own mouseDown.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.generation else { return }
            self.onReply?(original)
            self.dismiss()
        }
    }

    private func copyThai() {
        guard let translations else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translations.joined(separator: "\n\n"), forType: .string)
        toolbar?.setStatus("Copied")
    }
}

@MainActor
final class TranslationBubble {
    enum Style { case loading, translation, error }

    static let maxWidth: CGFloat = 360
    static let padding: CGFloat = 10
    static let hint = "คลิก = copy · ดับเบิลคลิก = ตอบกลับ"
    private static let hintGap: CGFloat = 4

    let panel: FloatingPanel
    var onEscape: (() -> Void)? {
        get { panel.onEscape }
        set { panel.onEscape = newValue }
    }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private let label = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: TranslationBubble.hint)
    private let background = makePanelBackground(material: .popover, cornerRadius: 8)
    private let clickArea = BubbleClickView()
    private var flashGeneration = 0

    init() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40))
        // Clicks belong to the bubble, not to window dragging.
        panel.isMovableByWindowBackground = false
        label.font = .systemFont(ofSize: 14)
        label.isSelectable = false
        label.isEditable = false
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.isSelectable = false
        hintLabel.isHidden = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.addSubview(label)
        background.addSubview(hintLabel)
        // On top of the labels so every click inside the bubble lands here.
        clickArea.onClick = { [weak self] in self?.onClick?() }
        clickArea.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
        background.addSubview(clickArea)
        panel.contentView = background
    }

    func show(text: String, style: Style) {
        label.stringValue = text
        switch style {
        case .loading: label.textColor = .secondaryLabelColor
        case .translation: label.textColor = .labelColor
        case .error: label.textColor = .systemRed
        }
        hintLabel.isHidden = style != .translation
        clickArea.toolTip = style == .translation ? Self.hint : nil
        panel.orderFrontRegardless()
    }

    /// Brief "Copied" confirmation in place of the hint, with an accent border.
    func flashCopied() {
        flashGeneration += 1
        let generation = flashGeneration
        hintLabel.stringValue = "Copied"
        hintLabel.textColor = .controlAccentColor
        background.layer?.borderWidth = 2
        background.layer?.borderColor = NSColor.controlAccentColor.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.hintLabel.stringValue = Self.hint
            self.hintLabel.textColor = .tertiaryLabelColor
            self.background.layer?.borderWidth = 0.5
            self.background.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    func preferredSize() -> NSSize {
        let maxText = Self.maxWidth - 2 * Self.padding
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxText, height: .greatestFiniteMagnitude)) ?? .zero
        var width = size.width
        var height = size.height
        if !hintLabel.isHidden {
            let hint = hintSize()
            width = max(width, hint.width)
            height += Self.hintGap + hint.height
        }
        return NSSize(
            width: max(60, min(maxText, ceil(width))) + 2 * Self.padding,
            height: ceil(height) + 2 * Self.padding
        )
    }

    func setFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        background.frame = NSRect(origin: .zero, size: frame.size)
        clickArea.frame = background.bounds
        var content = background.bounds.insetBy(dx: Self.padding, dy: Self.padding)
        if !hintLabel.isHidden {
            let hintHeight = ceil(hintSize().height)
            hintLabel.frame = NSRect(x: content.minX, y: content.minY, width: content.width, height: hintHeight)
            content.origin.y += hintHeight + Self.hintGap
            content.size.height -= hintHeight + Self.hintGap
        }
        label.frame = content
    }

    func close() {
        panel.orderOut(nil)
    }

    /// Measured with the hint text, so the "Copied" flash never changes the layout.
    private func hintSize() -> NSSize {
        NSAttributedString(string: Self.hint, attributes: [.font: hintLabel.font ?? .systemFont(ofSize: 10)]).size()
    }
}

/// Transparent overlay that turns a bubble into a click target: single click,
/// double click and a pointing-hand cursor. It also works while LingoBar is
/// not the active app, because the bubbles never activate it.
@MainActor
final class BubbleClickView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // The first click of a double click also copies; no delay is added to tell them apart.
        switch event.clickCount {
        case 1: onClick?()
        case 2: onDoubleClick?()
        default: break
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

@MainActor
final class TranslateToolbar {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 34))
    var onCopy: (() -> Void)?
    var onReply: (() -> Void)?
    var onClose: (() -> Void)?

    private let status = NSTextField(labelWithString: "")
    private lazy var copyButton = makeButton("Copy Thai", #selector(copyTapped))

    init() {
        let replyButton = makeButton("Reply…", #selector(replyTapped))
        let closeButton = makeButton("Close", #selector(closeTapped))
        copyButton.isEnabled = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "LingoBar")
        title.font = .systemFont(ofSize: 11, weight: .semibold)

        let stack = NSStackView(views: [title, status, copyButton, replyButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 6)

        let background = makePanelBackground(material: .hudWindow, cornerRadius: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background
        panel.onEscape = { [weak self] in self?.onClose?() }
        resize()
    }

    func setStatus(_ text: String?) {
        status.stringValue = text ?? ""
        status.isHidden = text == nil
        resize()
    }

    func setCopyEnabled(_ enabled: Bool) {
        copyButton.isEnabled = enabled
    }

    /// Above the region's top-left corner if it fits, else below, else inside.
    func place(near region: CGRect, visibleFrame: CGRect) {
        let size = panel.frame.size
        var origin = NSPoint(x: region.minX, y: region.maxY + 6)
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = region.minY - 6 - size.height
            if origin.y < visibleFrame.minY {
                origin.y = region.maxY - size.height - 6
            }
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 4), visibleFrame.maxX - size.width - 4)
        origin.y = min(max(origin.y, visibleFrame.minY + 4), visibleFrame.maxY - size.height - 4)
        panel.setFrameOrigin(origin)
    }

    func close() {
        panel.orderOut(nil)
    }

    private func resize() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        return button
    }

    @objc private func copyTapped() { onCopy?() }
    @objc private func replyTapped() { onReply?() }
    @objc private func closeTapped() { onClose?() }
}
