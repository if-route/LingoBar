# LingoBar

A macOS menu bar helper for writing and reading English at work.

- **Compose (⌥Space)**: type in Thai or rough English, press ⌘↵, and get two English versions ("Polished" and "Concise"), each with a Thai gloss. Pick a tone first: GitLab comment or Teams chat. Press ⌘1 or ⌘2, or click a version, to copy it and paste it into the app you were using.
- **Translate Region (⌥T)**: drag a rectangle over English text. LingoBar reads it with OCR and shows a Thai translation next to each paragraph. The toolbar has Copy Thai, Reply… (opens Compose with the original text as context), and Close. Esc also closes it. Click a bubble to copy its Thai, or double-click it to reply to just that paragraph.

It calls the Claude CLI (`claude -p`) with your Claude subscription login. No API key is needed.

## Build

Requires macOS 14+ and the Xcode Command Line Tools (Swift 5.10). Full Xcode is not needed.

```bash
scripts/build-app.sh          # swift build -c release + assembles build/LingoBar.app
```

## Run

```bash
open build/LingoBar.app       # appears in the menu bar, no Dock icon
pkill -x LingoBar             # or use Quit in the menu
```

Checks:

```bash
build/LingoBar.app/Contents/MacOS/LingoBar --selftest   # offline: parsing, grouping, geometry, real Vision OCR
build/LingoBar.app/Contents/MacOS/LingoBar --e2e        # 2 real Claude calls (uses your quota)
```

## Permissions

- **Screen Recording (required for Translate)**: System Settings › Privacy & Security › Screen Recording. LingoBar opens this page for you if the permission is missing. Quit and reopen LingoBar after you grant it.
- **Accessibility (optional)**: lets Compose paste for you with ⌘V. Use the menu item "Enable Auto-Paste (Accessibility)…". Without it, the text is copied and you paste it yourself.

## Settings

Choose the model for each mode from the menu: Sonnet 5.5 (`--effort low`) or Haiku 5.5 (thinking off). The defaults are Sonnet for Compose and Haiku for Translate. The Claude CLI path defaults to `~/.local/bin/claude`. To change it:

```bash
defaults write io.github.if-route.lingobar claudePath /path/to/claude
```

## Known limits

- **Ad-hoc signing**: if there is no code-signing identity in your keychain, the app is signed ad-hoc. macOS then forgets the Screen Recording and Accessibility permissions after every rebuild. To keep them, create a code-signing certificate (Keychain Access › Certificate Assistant › Create a Certificate…, type "Code Signing") and build with `LINGOBAR_SIGN_IDENTITY="<name>" scripts/build-app.sh`.
- macOS 15 and later may ask you to confirm screen access again from time to time.
- Each request takes about 4–5 seconds. Results appear all at once; they are not streamed.
- OCR is English only. Paragraph grouping is heuristic, so unusual layouts may be split or merged imperfectly.
- If another app already uses ⌥Space or ⌥T, LingoBar shows a notice. Use the menu bar icon instead.
- A selection stays on one screen; it cannot span two displays.
