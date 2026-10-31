import SwiftUI

// MARK: - Ask
//
// A question box over the ledger. It understands a defined set of shapes and
// admits when a question isn't one of them, which is the only honest way to do
// this without a language model behind it.

struct AskSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var answer: QueryAnswer?
    @State private var missed = false
    @FocusState private var focused: Bool

    private static let examples = [
        "How much can I spend on coffee this week?",
        "How much did I spend on food this month?",
        "What's left on Fun & Misc?",
        "Who spent the most this month?",
        "How much did we spend last month?",
    ]

    var body: some View {
        ModalPage(title: "Ask", subtitle: "Answered from your own entries, on this device") {
            VStack(alignment: .leading, spacing: Space.md) {
                askField

                if let answer {
                    answerCard(answer)
                    if !answer.entries.isEmpty {
                        RowGroup(title: "Behind that number") {
                            ForEach(answer.entries.prefix(8)) { entry in
                                GroupedRow(separatorInset: Space.md + 32 + Space.sm) {
                                    EntryRow(entry: entry)
                                }
                            }
                        }
                    }
                } else if missed {
                    notUnderstood
                } else {
                    examplesList
                }
            }
        }
        .onAppear { focused = true }
    }

    private var askField: some View {
        HStack(spacing: 9) {
            TextField("", text: $question,
                      prompt: Text("Ask about your spending").foregroundStyle(Palette.muted))
                .focused($focused)
                .textFieldStyle(.plain)
                .appFont(15)
                .submitLabel(.search)
                .onSubmit(run)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

            let canAsk = !question.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: run) {
                Image(systemName: "arrow.up")
                    .appFont(14, weight: .bold)
                    .foregroundStyle(canAsk ? Palette.tealInk : Palette.muted)
            }
            .primaryButtonStyle()
            .disabled(!canAsk)
            .accessibilityLabel("Ask")
        }
    }

    private func answerCard(_ answer: QueryAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.headline).mono(30)
            if let detail = answer.detail {
                Text(detail)
                    .appFont(13).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .card()
    }

    /// No guessing. Say what it can do instead.
    private var notUnderstood: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "questionmark.circle.fill")
                        .appFont(14, weight: .semibold)
                        .foregroundStyle(Palette.moodRoutine)
                    Text("I didn't follow that one")
                        .appFont(14, weight: .medium)
                }
                Text("I can answer questions about totals, what's left, and who spent what — over today, this week, this month or last month. Try one of these:")
                    .appFont(12.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            exampleRows(title: nil)
        }
    }

    private var examplesList: some View { exampleRows(title: "Try asking") }

    private func exampleRows(title: String?) -> some View {
        RowGroup(title: title) {
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    question = example
                    run()
                } label: {
                    GroupedRow {
                        HStack(spacing: Space.xs) {
                            Text(example)
                                .appFont(13)
                                .foregroundStyle(Palette.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .appFont(11, weight: .semibold)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .buttonStyle(.row)
            }
        }
    }

    private func run() {
        focused = false
        let result = model.ask(question)
        answer = result
        missed = result == nil
    }
}

#Preview {
    AskSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
