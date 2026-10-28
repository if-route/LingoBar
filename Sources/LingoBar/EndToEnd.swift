import Foundation
import LingoBarCore

/// `LingoBar --e2e`: one real CLI call per mode with the configured models.
/// Uses the user's Claude subscription quota, so it is not part of --selftest.
enum EndToEnd {
    static func run() -> Never {
        Task {
            let client = ClaudeCLIClient(executablePath: Settings.claudePath)
            var ok = true

            let url = "https://gitlab.com/example-org/planning/-/work_items/1909"
            let blocks = [
                "The pipeline failed on the staging server.",
                "Please review the merge request before Friday.",
                "The details are in \(url), please take a look."
            ]
            let translateModel = Settings.translateModel
            var start = Date()
            do {
                let raw = try await client.complete(system: Prompts.translateSystem(), user: Prompts.translateUser(blocks: blocks), model: translateModel)
                let thai = try ModelOutputParser.parseTranslations(raw, expectedCount: blocks.count)
                print(String(format: "PASS  translate (%@, %.1fs)", translateModel.rawValue, Date().timeIntervalSince(start)))
                for (english, translated) in zip(blocks, thai) {
                    print("      \(english)\n   -> \(translated)")
                }
                if thai.last?.contains(url) != true {
                    ok = false
                    print("FAIL  translate kept the URL exactly")
                }
            } catch {
                ok = false
                print("FAIL  translate (\(translateModel.rawValue)): \(error.localizedDescription)")
            }

            let composeModel = Settings.composeModel
            start = Date()
            do {
                let draft = "พรุ่งนี้จะ deploy fix ของ #123 ขึ้น staging ให้นะครับ"
                let raw = try await client.complete(
                    system: Prompts.composeSystem(tone: .teams),
                    user: Prompts.composeUser(draft: draft, replyingTo: nil),
                    model: composeModel
                )
                let variants = try ModelOutputParser.parseCompose(raw)
                print(String(format: "PASS  compose (%@, %.1fs)", composeModel.rawValue, Date().timeIntervalSince(start)))
                print("      draft: \(draft)")
                for variant in variants {
                    print("      \(variant.label): \(variant.english)\n        th: \(variant.thai)")
                }
            } catch {
                ok = false
                print("FAIL  compose (\(composeModel.rawValue)): \(error.localizedDescription)")
            }
            exit(ok ? 0 : 1)
        }
        dispatchMain()
    }
}
