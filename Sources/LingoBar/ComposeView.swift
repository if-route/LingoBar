import AppKit
import LingoBarCore
import SwiftUI

struct ComposeView: View {
    @ObservedObject var model: ComposeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let context = model.context {
                contextSection(context)
            }
            HStack(alignment: .top, spacing: 12) {
                editor
                suggestions
                    .frame(width: 390)
            }
            footer
        }
        .padding(14)
        .frame(width: 820, height: 470)
    }

    private var header: some View {
        HStack {
            Text("LingoBar")
                .font(.headline)
            Text("Compose")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Tone", selection: $model.tone) {
                ForEach(ComposeTone.allCases, id: \.self) { tone in
                    Text(tone.displayName).tag(tone)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private func contextSection(_ context: String) -> some View {
        HStack(alignment: .top) {
            DisclosureGroup(isExpanded: $model.contextExpanded) {
                ScrollView {
                    Text(context)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            } label: {
                Text("Replying to: ")
                    .foregroundStyle(.secondary)
                    + Text(context.replacingOccurrences(of: "\n", with: " "))
            }
            .lineLimit(1)
            Button {
                model.clearContext()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove the replied-to message")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            DraftEditor(text: $model.draft) { textView in
                model.textView = textView
            }
            if model.draft.isEmpty {
                Text("Type in Thai or rough English…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
    }

    @ViewBuilder
    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating with \(model.modelName)…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
                if let error = model.errorText {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(model.variants.enumerated()), id: \.offset) { index, variant in
                    VariantCard(index: index, variant: variant) {
                        model.pick(index)
                    }
                }
                if !model.isLoading && model.errorText == nil && model.variants.isEmpty {
                    Text("Press ⌘↵ to get suggestions.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Text("⌘↵ Generate    ⌘1 / ⌘2 Copy & paste    Esc Close")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Generate") { model.generate() }
                .disabled(model.isLoading)
        }
    }
}

private struct VariantCard: View {
    let index: Int
    let variant: ComposeVariant
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("⌘\(index + 1)")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
                Text(variant.label)
                    .font(.subheadline.bold())
                Spacer()
                Text(hovering ? "Click to copy" : "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(variant.english)
                .fixedSize(horizontal: false, vertical: true)
            if !variant.thai.isEmpty {
                Text(variant.thai)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

/// Plain-text NSTextView: no smart quotes/dashes, so code and identifiers survive.
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var onReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        onReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
