import AppKit
import ApplicationServices
import Carbon
import LingoBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let compose = ComposeController()
    private let translate = TranslateController()
    private var composeModelItems: [NSMenuItem] = []
    private var translateModelItems: [NSMenuItem] = []
    private var autoPasteItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        translate.onReply = { [weak self] original in
            self?.compose.show(context: original)
        }
        setUpStatusItem()
        registerHotKeys()
    }

    private func registerHotKeys() {
        let option = optionKey
        var failures: [String] = []
        if !HotKeyManager.shared.register(keyCode: kVK_Space, modifiers: option, handler: { [weak self] in self?.compose.toggle() }) {
            failures.append("⌥Space")
        }
        if !HotKeyManager.shared.register(keyCode: kVK_ANSI_T, modifiers: option, handler: { [weak self] in self?.translate.start() }) {
            failures.append("⌥T")
        }
        if !failures.isEmpty {
            Toast.show("LingoBar: \(failures.joined(separator: " and ")) is already used by another app. Use the menu bar icon instead.", duration: 6)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "LingoBar") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "LB"
        }

        let menu = NSMenu()
        menu.delegate = self

        let composeItem = NSMenuItem(title: "Compose", action: #selector(openCompose), keyEquivalent: " ")
        composeItem.keyEquivalentModifierMask = .option
        composeItem.target = self
        menu.addItem(composeItem)

        let translateItem = NSMenuItem(title: "Translate Region", action: #selector(startTranslate), keyEquivalent: "t")
        translateItem.keyEquivalentModifierMask = .option
        translateItem.target = self
        menu.addItem(translateItem)

        menu.addItem(.separator())
        menu.addItem(modelSubmenu(title: "Compose Model", store: &composeModelItems, action: #selector(pickComposeModel(_:))))
        menu.addItem(modelSubmenu(title: "Translate Model", store: &translateModelItems, action: #selector(pickTranslateModel(_:))))

        menu.addItem(.separator())
        let autoPaste = NSMenuItem(title: "", action: #selector(enableAutoPaste), keyEquivalent: "")
        autoPaste.target = self
        menu.addItem(autoPaste)
        autoPasteItem = autoPaste

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LingoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        refreshMenuState()
    }

    private func modelSubmenu(title: String, store: inout [NSMenuItem], action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for choice in ModelChoice.allCases {
            let item = NSMenuItem(title: choice.displayName, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            submenu.addItem(item)
            store.append(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func refreshMenuState() {
        for item in composeModelItems {
            item.state = (item.representedObject as? String) == Settings.composeModel.rawValue ? .on : .off
        }
        for item in translateModelItems {
            item.state = (item.representedObject as? String) == Settings.translateModel.rawValue ? .on : .off
        }
        let trusted = AXIsProcessTrusted()
        autoPasteItem?.title = trusted ? "Auto-Paste: On" : "Enable Auto-Paste (Accessibility)…"
        autoPasteItem?.isEnabled = !trusted
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    @objc private func openCompose() {
        compose.show(context: nil)
    }

    @objc private func startTranslate() {
        // Let the menu finish closing before the overlay grabs the screen.
        DispatchQueue.main.async { [weak self] in self?.translate.start() }
    }

    @objc private func pickComposeModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ModelChoice(rawValue: raw) else { return }
        Settings.composeModel = choice
        compose.model.refreshModelName()
        refreshMenuState()
    }

    @objc private func pickTranslateModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ModelChoice(rawValue: raw) else { return }
        Settings.translateModel = choice
        refreshMenuState()
    }

    @objc private func enableAutoPaste() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
