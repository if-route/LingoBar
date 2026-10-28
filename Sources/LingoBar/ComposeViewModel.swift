import AppKit
import LingoBarCore

@MainActor
final class ComposeViewModel: ObservableObject {
    /// Kept for the whole app run so reopening the panel restores the draft.
    @Published var draft = ""
    /// Original message being replied to (set by Translate's "Reply…").
    @Published var context: String?
    @Published var contextExpanded = false
    @Published var tone: ComposeTone = Settings.composeTone {
        didSet { Settings.composeTone = tone }
    }
    @Published var variants: [ComposeVariant] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var modelName = Settings.composeModel.displayName

    weak var textView: NSTextView?
    var onPick: ((ComposeVariant) -> Void)?

    private var task: Task<Void, Never>?

    func refreshModelName() {
        modelName = Settings.composeModel.displayName
    }

    func generate() {
        let draft = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            errorText = "Type a draft first."
            return
        }
        task?.cancel()
        isLoading = true
        errorText = nil
        variants = []

        let model = Settings.composeModel
        modelName = model.displayName
        let system = Prompts.composeSystem(tone: tone)
        let user = Prompts.composeUser(draft: draft, replyingTo: context)
        let client = Settings.makeClient()

        task = Task { [weak self] in
            do {
                let raw = try await client.complete(system: system, user: user, model: model)
                let parsed = try ModelOutputParser.parseCompose(raw)
                guard !Task.isCancelled else { return }
                self?.variants = parsed
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorText = error.localizedDescription
            }
            self?.isLoading = false
        }
    }

    func pick(_ index: Int) {
        guard variants.indices.contains(index) else { return }
        onPick?(variants[index])
    }

    func clearContext() {
        context = nil
        contextExpanded = false
    }
}
