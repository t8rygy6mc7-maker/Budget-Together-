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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                askField

                if let answer {
                    answerCard(answer).padding(.top, 18)
                    if !answer.entries.isEmpty {
                        Text("Behind that number")
                            .appFont(13, weight: .semibold)
                            .padding(.top, 20).padding(.bottom, 10)
                        VStack(spacing: 8) {
                            ForEach(answer.entries.prefix(8)) { EntryRow(entry: $0) }
                        }
                    }
                } else if missed {
                    notUnderstood.padding(.top, 18)
                } else {
                    examplesList.padding(.top, 18)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask").appFont(17, weight: .bold)
                Text("Answered from your own entries, on this device")
                    .appFont(12.5, weight: .medium)
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 16)
    }

    private var askField: some View {
        HStack(spacing: 9) {
            TextField("", text: $question,
                      prompt: Text("Ask about your spending").foregroundStyle(Palette.muted))
                .focused($focused)
                .textFieldStyle(.plain)
                .appFont(15, weight: .medium)
                .submitLabel(.search)
                .onSubmit(run)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)

            let canAsk = !question.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: run) {
                Image(systemName: "arrow.up")
                    .appFont(16, weight: .bold)
                    .foregroundStyle(canAsk ? Palette.tealInk : Palette.muted)
                    .frame(width: 46, height: 46)
                    .background { if canAsk { Palette.tealGradient } else { Palette.chip } }
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
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
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }

    /// No guessing. Say what it can do instead.
    private var notUnderstood: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "questionmark.circle.fill")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.moodRoutine)
                Text("I didn't follow that one")
                    .appFont(14, weight: .semibold)
            }
            Text("I can answer questions about totals, what's left, and who spent what — over today, this week, this month or last month. Try one of these:")
                .appFont(12.5).foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
            exampleButtons
        }
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }

    private var examplesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking").appFont(13, weight: .semibold)
            exampleButtons
        }
    }

    private var exampleButtons: some View {
        VStack(spacing: 8) {
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    question = example
                    run()
                } label: {
                    HStack(spacing: 9) {
                        Text(example)
                            .appFont(13, weight: .medium)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .appFont(11, weight: .semibold)
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .card(border: Palette.cardBorderSoft, radius: 13)
                }
                .buttonStyle(.plain)
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
