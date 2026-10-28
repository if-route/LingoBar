import Foundation
import LingoBarCore

/// UserDefaults-backed preferences (domain: io.github.if-route.lingobar).
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let claudePath = "claudePath"
        static let composeModel = "composeModel"
        static let translateModel = "translateModel"
        static let composeTone = "composeTone"
    }

    /// Absolute path because a Finder-launched app has no shell PATH.
    static var claudePath: String {
        get { defaults.string(forKey: Key.claudePath) ?? "\(NSHomeDirectory())/.local/bin/claude" }
        set { defaults.set(newValue, forKey: Key.claudePath) }
    }

    static var composeModel: ModelChoice {
        get { defaults.string(forKey: Key.composeModel).flatMap(ModelChoice.init(rawValue:)) ?? .sonnet55 }
        set { defaults.set(newValue.rawValue, forKey: Key.composeModel) }
    }

    static var translateModel: ModelChoice {
        get { defaults.string(forKey: Key.translateModel).flatMap(ModelChoice.init(rawValue:)) ?? .haiku55 }
        set { defaults.set(newValue.rawValue, forKey: Key.translateModel) }
    }

    static var composeTone: ComposeTone {
        get { defaults.string(forKey: Key.composeTone).flatMap(ComposeTone.init(rawValue:)) ?? .gitlab }
        set { defaults.set(newValue.rawValue, forKey: Key.composeTone) }
    }

    static func makeClient() -> LLMClient {
        ClaudeCLIClient(executablePath: claudePath, timeout: 30)
    }
}
