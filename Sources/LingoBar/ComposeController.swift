import AppKit
import ApplicationServices
import LingoBarCore
import SwiftUI

/// Spotlight-like compose panel. Non-activating, so the user's app stays
/// frontmost and receives the paste afterwards.
@MainActor
final class ComposeController: NSObject, NSWindowDelegate {
    let model = ComposeViewModel()
    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show(context: nil)
    }

    /// `context` replaces the current replied-to message when non-nil.
    func show(context: String?) {
        if let context {
            model.context = context
            model.contextExpanded = false
        }
        model.refreshModelName()

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        if let textView = model.textView {
            panel.makeFirstResponder(textView)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let hosting = NSHostingView(rootView: ComposeView(model: model))
        let size = hosting.fittingSize
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.isMovableByWindowBackground = false
        let background = makePanelBackground(material: .hudWindow, cornerRadius: 14)
        background.frame = NSRect(origin: .zero, size: size)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        model.onPick = { [weak self] variant in self?.deliver(variant) }
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = screenContaining(NSEvent.mouseLocation) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + (visible.height - size.height) * 0.62
        )
        panel.setFrameOrigin(origin)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            model.generate()
            return true
        case KeyCode.digit1:
            model.pick(0)
            return true
        case KeyCode.digit2:
            model.pick(1)
            return true
        default:
            return false
        }
    }

    private func deliver(_ variant: ComposeVariant) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(variant.english, forType: .string)

        hide()
        previousApp?.activate()

        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Self.sendPaste()
            }
        } else {
            Toast.show("Copied. Press ⌘V to paste.")
        }
    }

    private static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Close when the user moves to another app, but not when they click one of
    // LingoBar's own panels (e.g. a translation bubble).
    nonisolated func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, NSApp.keyWindow == nil else { return }
                self.hide()
            }
        }
    }
}
