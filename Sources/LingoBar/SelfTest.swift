import AppKit
import LingoBarCore

/// `LingoBar --selftest`: assertions for the pure logic plus a real Vision OCR
/// run, because XCTest is not available with the Command Line Tools alone.
enum SelfTest {
    private static var failures = 0
    private static var passes = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if condition() {
            passes += 1
            print("PASS  \(name)")
        } else {
            failures += 1
            let extra = detail()
            print("FAIL  \(name)\(extra.isEmpty ? "" : " — \(extra)")")
        }
    }

    static func run() -> Bool {
        jsonParsing()
        cliResultParsing()
        modelFlags()
        coordinates()
        grouping()
        layout()
        prompts()
        urlRepair()
        bubble()
        ocr()
        ocrUnderlinedURL()
        print("\n\(passes) passed, \(failures) failed")
        return failures == 0
    }

    // MARK: - Model output parsing

    private static let composeJSON = #"{"polished":{"english":"I'll deploy [it] to {staging} tomorrow, see #123.","thai":"จะ deploy ขึ้น staging พรุ่งนี้"},"concise":{"english":"Deploying to staging tomorrow (#123).","thai":"deploy พรุ่งนี้"}}"#

    private static func jsonParsing() {
        let plain = try? ModelOutputParser.parseCompose(composeJSON)
        check(plain?.count == 2 && plain?[0].label == "Polished" && plain?[1].label == "Concise", "compose: plain JSON")
        check(plain?[0].english.contains("[it] to {staging}") == true, "compose: brackets inside strings survive")
        check(plain?[0].thai.hasPrefix("จะ") == true, "compose: Thai gloss parsed")

        let fenced = "```json\n\(composeJSON)\n```"
        check((try? ModelOutputParser.parseCompose(fenced))?.count == 2, "compose: ```json fenced")

        let prose = "Sure! Here are [2] options:\n\n```\n\(composeJSON)\n```\nLet me know if you need more."
        check((try? ModelOutputParser.parseCompose(prose))?.count == 2, "compose: prose + bare fence + prose")

        let inline = "Here you go: \(composeJSON) Hope this helps."
        check((try? ModelOutputParser.parseCompose(inline))?.count == 2, "compose: raw JSON inside prose")

        let altKeys = #"{"Polished":{"en":"A","th":"ก"},"Concise":"B"}"#
        let alt = try? ModelOutputParser.parseCompose(altKeys)
        check(alt?[0].english == "A" && alt?[0].thai == "ก" && alt?[1].english == "B", "compose: alternative key spellings")

        do {
            _ = try ModelOutputParser.parseCompose("I cannot help with that.")
            check(false, "compose: garbage throws")
        } catch {
            check(error as? ModelOutputError != nil, "compose: garbage throws ModelOutputError")
        }

        let translations = "Note [1]: translations below.\n```json\n[\"สวัสดี\", \"pipeline ล้มเหลว\"]\n```"
        let parsed = try? ModelOutputParser.parseTranslations(translations, expectedCount: 2)
        check(parsed == ["สวัสดี", "pipeline ล้มเหลว"], "translate: skips prose [1], uses fenced array", "\(String(describing: parsed))")

        let objects = #"[{"n":1,"thai":"หนึ่ง"},{"n":2,"th":"สอง"}]"#
        check((try? ModelOutputParser.parseTranslations(objects, expectedCount: 2)) == ["หนึ่ง", "สอง"], "translate: array of objects")

        let wrapped = #"{"translations":["ก","ข","ค"]}"#
        check((try? ModelOutputParser.parseTranslations(wrapped, expectedCount: 2)) == ["ก", "ข"], "translate: wrapper object, extra items dropped")

        do {
            _ = try ModelOutputParser.parseTranslations(#"["only one"]"#, expectedCount: 2)
            check(false, "translate: short array throws")
        } catch {
            check(error as? ModelOutputError == .countMismatch(expected: 2, got: 1), "translate: short array -> countMismatch", "\(error)")
        }
    }

    private static func cliResultParsing() {
        let success = #"{"type":"result","subtype":"success","is_error":false,"result":"hello"}"#
        check((try? ClaudeCLIClient.parseResult(success)) == "hello", "cli: result object")

        let array = #"[{"type":"system","subtype":"init"},{"type":"result","subtype":"success","is_error":false,"result":"hi"}]"#
        check((try? ClaudeCLIClient.parseResult(array)) == "hi", "cli: verbose event array")

        let failure = #"{"type":"result","subtype":"success","is_error":true,"result":"API Error: 400"}"#
        do {
            _ = try ClaudeCLIClient.parseResult(failure)
            check(false, "cli: is_error throws")
        } catch {
            check(error.localizedDescription.contains("API Error: 400"), "cli: is_error throws with message")
        }
        check((try? ClaudeCLIClient.parseResult("not json")) == .some(nil), "cli: non-JSON returns nil")
    }

    private static func modelFlags() {
        let client = ClaudeCLIClient(executablePath: "/bin/echo")
        let sonnetArgs = client.arguments(system: "S", model: .sonnet55)
        check(sonnetArgs.contains("claude-sonnet-5-5") && sonnetArgs.suffix(2) == ["--effort", "low"], "flags: Sonnet uses --effort low")
        check(ModelChoice.sonnet55.extraEnvironment["MAX_THINKING_TOKENS"] == nil, "flags: Sonnet does not set MAX_THINKING_TOKENS")
        check(ModelChoice.haiku55.extraEnvironment["MAX_THINKING_TOKENS"] == "0", "flags: Haiku sets MAX_THINKING_TOKENS=0")
        check(!client.arguments(system: "S", model: .haiku55).contains("--effort"), "flags: Haiku has no --effort")
        check(!sonnetArgs.contains("--bare"), "flags: never --bare")
        if let index = sonnetArgs.firstIndex(of: "--setting-sources") {
            check(sonnetArgs[index + 1] == "", "flags: empty --setting-sources")
        } else {
            check(false, "flags: --setting-sources present")
        }
    }

    // MARK: - Geometry

    private static func coordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let local = CoordinateMapper.displayLocalTopLeftRect(globalRect: CGRect(x: 100, y: 700, width: 200, height: 100), screenFrame: primary)
        check(local == CGRect(x: 100, y: 100, width: 200, height: 100), "coords: primary screen flip", "\(local)")

        // Secondary display to the right, lower than the primary.
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let local2 = CoordinateMapper.displayLocalTopLeftRect(globalRect: CGRect(x: 1500, y: 600, width: 100, height: 50), screenFrame: secondary)
        check(local2 == CGRect(x: 60, y: 230, width: 100, height: 50), "coords: secondary screen offset + flip", "\(local2)")

        let pixels = CoordinateMapper.pixelSize(for: CGRect(x: 0, y: 0, width: 200.5, height: 100), scale: 2)
        check(pixels.width == 401 && pixels.height == 200, "coords: Retina pixel size")

        let global = CoordinateMapper.globalRect(normalized: CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.1), in: CGRect(x: 100, y: 200, width: 400, height: 300))
        check(global == CGRect(x: 300, y: 350, width: 100, height: 30), "coords: Vision normalized -> global", "\(global)")
    }

    private static func line(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat = 400, height: CGFloat = 20) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: top - height, width: width, height: height))
    }

    private static func grouping() {
        let grouper = TextBlockGrouper()

        // Two paragraphs: 26pt line pitch (6pt gap within), 24pt gap between.
        let paragraphs = [
            line("Second paragraph line one", x: 10, top: 430),
            line("First paragraph line one", x: 10, top: 500),
            line("First paragraph line two", x: 10, top: 474),
            line("Second paragraph line two", x: 10, top: 404)
        ]
        let blocks = grouper.group(paragraphs)
        check(blocks.count == 2, "group: two paragraphs", "\(blocks.map(\.text))")
        check(blocks.first?.text == "First paragraph line one First paragraph line two", "group: reading order + join")

        let columns = [
            line("Left column one", x: 10, top: 500, width: 300),
            line("Right column one", x: 600, top: 500, width: 300),
            line("Left column two", x: 10, top: 474, width: 300),
            line("Right column two", x: 600, top: 474, width: 300)
        ]
        let columnBlocks = grouper.group(columns)
        check(columnBlocks.count == 2 && columnBlocks[0].text == "Left column one Left column two", "group: side-by-side columns", "\(columnBlocks.map(\.text))")

        let heading = [
            line("Release notes", x: 10, top: 540, height: 34),
            line("Body text that follows", x: 10, top: 500)
        ]
        check(grouper.group(heading).count == 2, "group: heading split by height")

        let hyphen = [line("the deploy-", x: 10, top: 500), line("ment failed", x: 10, top: 474)]
        check(grouper.group(hyphen).first?.text == "the deployment failed", "group: de-hyphenation")

        let indented = [line("A long line", x: 10, top: 500), line("far right", x: 200, top: 474)]
        check(grouper.group(indented).count == 2, "group: misaligned left edges split")

        check(grouper.group([]).isEmpty, "group: empty input")
    }

    private static func layout() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 300, height: 60)

        let right = PanelLayout.frames(blocks: [CGRect(x: 100, y: 500, width: 400, height: 80)], sizes: [size], visibleFrame: visible)
        check(right[0].minX == 508 && right[0].maxY == 580, "layout: right of block, top-aligned", "\(right[0])")

        let below = PanelLayout.frames(blocks: [CGRect(x: 1000, y: 500, width: 400, height: 80)], sizes: [size], visibleFrame: visible)
        check(below[0].minX == 1000 && below[0].maxY == 492, "layout: below when no room on the right", "\(below[0])")

        let stacked = PanelLayout.frames(
            blocks: [CGRect(x: 100, y: 540, width: 400, height: 40), CGRect(x: 100, y: 500, width: 400, height: 30)],
            sizes: [CGSize(width: 300, height: 90), CGSize(width: 300, height: 90)],
            visibleFrame: visible
        )
        check(!stacked[0].intersects(stacked[1]), "layout: no overlap between panels", "\(stacked)")

        let edge = PanelLayout.frames(blocks: [CGRect(x: 1300, y: 5, width: 130, height: 20)], sizes: [size], visibleFrame: visible)
        check(visible.contains(edge[0]), "layout: kept on-screen", "\(edge[0])")

        let obstacle = CGRect(x: 508, y: 520, width: 300, height: 60)
        let avoided = PanelLayout.frames(blocks: [CGRect(x: 100, y: 500, width: 400, height: 80)], sizes: [size], visibleFrame: visible, obstacles: [obstacle])
        check(!avoided[0].intersects(obstacle), "layout: avoids obstacles (toolbar)", "\(avoided[0])")
    }

    private static func prompts() {
        let user = Prompts.translateUser(blocks: ["Hello \"team\"", "Bye/see you"])
        check(user.hasPrefix("N = 2\n"), "prompt: translate count header")
        let json = String(user.dropFirst("N = 2\n".count))
        let decoded = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]]
        check(decoded?.count == 2 && (decoded?[0]["text"] as? String) == "Hello \"team\"", "prompt: translate payload is valid JSON")

        check(Prompts.composeSystem(tone: .teams, extraInstructions: "Client is ACME").hasSuffix("Client is ACME"), "prompt: extra instructions appended")
        check(Prompts.composeUser(draft: "x", replyingTo: "orig").contains("<message_being_replied_to>"), "prompt: reply context included")
        check(!Prompts.composeUser(draft: "x", replyingTo: nil).contains("message_being_replied_to"), "prompt: no context when absent")
        check(Prompts.translateSystem().contains("URLs, file paths and identifiers exactly as given, character for character"), "prompt: translate keeps URLs verbatim")
    }

    // MARK: - URL repair

    private static let workItemURL = "https://gitlab.com/example-org/planning/-/work_items/1909"

    private static func urlRepair() {
        let cases: [(input: String, expected: String, name: String)] = [
            ("https://gitlab.com/example-org/planning/-/work items/1909", workItemURL, "underscore read as space"),
            ("https://gitlab.com/example-org/planning/-/work_ items/1909", workItemURL, "underscore plus extra space"),
            ("https://gitlab.com/example-org/planning/=/work items/1909", workItemURL, "/=/ back to /-/"),
            ("Please check https://gitlab.com/example-org/planning/-/work items/1909 today.", "Please check \(workItemURL) today.", "URL inside a sentence"),
            ("See https://gitlab.com/example-org/app/-/merge requests/45#note 12 thanks", "See https://gitlab.com/example-org/app/-/merge_requests/45#note 12 thanks", "merge_requests, fragment left alone"),
            ("https://gitlab.com/a/-/blob/main/src/my module/sub/file.py", "https://gitlab.com/a/-/blob/main/src/my_module/sub/file.py", "path segment followed by /dir"),
            ("See https://gitlab.com/example-org/app and/or ask Bob", "See https://gitlab.com/example-org/app and/or ask Bob", "and/or prose kept"),
            ("Open https://gitlab.com/example-org/app/-/pipelines 3/4 jobs passed", "Open https://gitlab.com/example-org/app/-/pipelines 3/4 jobs passed", "fraction prose kept"),
            ("Open https://gitlab.com/example-org/app/-/jobs for build logs/123", "Open https://gitlab.com/example-org/app/-/jobs for build logs/123", "only the next token can join"),
            ("Read https://example.com/docs. items/12 are listed", "Read https://example.com/docs. items/12 are listed", "URL ending in punctuation is complete"),
            ("Read https://example.com/ items/12", "Read https://example.com/ items/12", "URL ending in / is complete"),
            ("https://example.com read/write access", "https://example.com read/write access", "URL without a path untouched"),
            ("The work items/1909 board, a = b /=/ c", "The work items/1909 board, a = b /=/ c", "no URL, nothing changes"),
            ("https://gitlab.com/example-org/planning/-/work_items/1909", workItemURL, "correct URL unchanged")
        ]
        for item in cases {
            let output = URLRepair.repair(item.input)
            check(output == item.expected, "url: \(item.name)", output)
        }
    }

    // MARK: - Translation bubble (headless AppKit)

    private static func bubble() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let bubble = TranslationBubble()
            var clicks = 0
            var doubleClicks = 0
            bubble.onClick = { clicks += 1 }
            bubble.onDoubleClick = { doubleClicks += 1 }
            bubble.show(text: "สวัสดีครับ ทดสอบ", style: .translation)
            let size = bubble.preferredSize()
            bubble.setFrame(NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size))
            defer { bubble.close() }

            let content = bubble.panel.contentView
            let labels = content?.subviews.compactMap { $0 as? NSTextField } ?? []
            check(!labels.isEmpty && labels.allSatisfy { !$0.isSelectable && !$0.isEditable }, "bubble: text not selectable or editable")
            check(labels.contains { $0.stringValue == TranslationBubble.hint && !$0.isHidden }, "bubble: hint visible on translation")

            let centre = NSPoint(x: size.width / 2, y: size.height / 2)
            let label = labels.first { $0.stringValue == "สวัสดีครับ ทดสอบ" }
            let onLabel = label.map { NSPoint(x: $0.frame.maxX - 2, y: $0.frame.midY) } ?? centre
            guard let target = content?.hitTest(onLabel) as? BubbleClickView else {
                check(false, "bubble: clicks on text reach the click view", "\(String(describing: content?.hitTest(onLabel)))")
                return
            }
            check(true, "bubble: clicks on text reach the click view")
            check(target.acceptsFirstMouse(for: nil), "bubble: accepts first mouse while inactive")

            for count in [1, 2] {
                let event = NSEvent.mouseEvent(
                    with: .leftMouseDown, location: centre, modifierFlags: [], timestamp: 0,
                    windowNumber: bubble.panel.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1
                )
                if let event { target.mouseDown(with: event) }
            }
            check(clicks == 1 && doubleClicks == 1, "bubble: click -> copy, double click -> reply", "clicks \(clicks), double \(doubleClicks)")

            bubble.show(text: "Translating…", style: .loading)
            check(labels.first { $0.stringValue == TranslationBubble.hint }?.isHidden == true, "bubble: no hint while loading")
        }
    }

    // MARK: - OCR (real Vision pipeline)

    private static func ocr() {
        let pointSize = CGSize(width: 1000, height: 520)
        guard let image = renderParagraphs(size: pointSize, scale: 2) else {
            check(false, "ocr: render test image")
            return
        }
        do {
            let start = Date()
            let blocks = try TextRecognizer.blocks(in: image, region: CGRect(origin: .zero, size: pointSize))
            let elapsed = Date().timeIntervalSince(start)
            print(String(format: "      OCR took %.2fs, blocks: %@", elapsed, blocks.map { "\"\($0.text)\"" }.joined(separator: " | ")))
            check(blocks.count == 2, "ocr: two paragraphs -> 2 blocks", "got \(blocks.count)")
            let first = blocks.first?.text.lowercased() ?? ""
            let second = blocks.dropFirst().first?.text.lowercased() ?? ""
            check(first.contains("deployment pipeline") && first.contains("root cause"), "ocr: first paragraph recognized")
            check(second.contains("merge request") && second.contains("friday"), "ocr: second paragraph recognized")
            check((blocks.first?.lines.count ?? 0) >= 2, "ocr: first block spans multiple lines")
            check((blocks.first?.rect.minY ?? 0) > (blocks.last?.rect.maxY ?? .infinity), "ocr: block rects in point space, top block first")
        } catch {
            check(false, "ocr: Vision request", "\(error)")
        }
    }

    /// Teams-style link: lavender-blue on a dark background, 14pt, underline
    /// drawn over the underscore glyph. Vision reads it as "work items".
    private static func ocrUnderlinedURL() {
        let pointSize = CGSize(width: 700, height: 48)
        let scale: CGFloat = 2
        guard let context = CGContext(
            data: nil, width: Int(pointSize.width * scale), height: Int(pointSize.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            check(false, "ocr url: render test image")
            return
        }
        let link = NSColor(srgbRed: 0x7F / 255, green: 0x85 / 255, blue: 0xF5 / 255, alpha: 1)
        context.setFillColor(NSColor(srgbRed: 0x29 / 255, green: 0x29 / 255, blue: 0x29 / 255, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pointSize.width * scale, height: pointSize.height * scale))
        context.scaleBy(x: scale, y: scale)

        let font = NSFont.systemFont(ofSize: 14)
        let origin = CGPoint(x: 20, y: 14)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = NSAttributedString(string: workItemURL, attributes: [.font: font, .foregroundColor: link])
        text.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()

        var character: UniChar = 0x5F
        var glyph = CGGlyph(0)
        CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
        let underscore = font.boundingRect(forCGGlyph: glyph)
        let baseline = origin.y - font.descender
        context.setFillColor(link.cgColor)
        context.fill(CGRect(x: origin.x, y: baseline + underscore.minY, width: text.size().width, height: underscore.height))

        guard let image = context.makeImage() else {
            check(false, "ocr url: render test image")
            return
        }
        do {
            let raw = try TextRecognizer.recognize(image).map(\.text).joined(separator: " ")
            let blocks = try TextRecognizer.blocks(in: image, region: CGRect(origin: .zero, size: pointSize))
            print("      raw OCR: \"\(raw)\"  repaired: \"\(blocks.first?.text ?? "")\"")
            check(blocks.first?.text == workItemURL, "ocr url: underlined link keeps its underscore", blocks.first?.text ?? "no block")
        } catch {
            check(false, "ocr url: Vision request", "\(error)")
        }
    }

    private static func renderParagraphs(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        let first = "The deployment pipeline failed on the staging server last night because the database migration timed out. We are investigating the root cause and will share an update soon."
        let second = "Please review the merge request before Friday so that we can release the new version to production next week."
        // Paragraph one at the top, then a gap of about one blank line, then paragraph two.
        let textWidth: CGFloat = 900
        let firstHeight = ceil((first as NSString).boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin], attributes: attributes).height)
        let secondHeight = ceil((second as NSString).boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin], attributes: attributes).height)
        let firstTop = size.height - 40
        let secondTop = firstTop - firstHeight - 30
        (first as NSString).draw(in: CGRect(x: 40, y: firstTop - firstHeight, width: textWidth, height: firstHeight), withAttributes: attributes)
        (second as NSString).draw(in: CGRect(x: 40, y: secondTop - secondHeight, width: textWidth, height: secondHeight), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
