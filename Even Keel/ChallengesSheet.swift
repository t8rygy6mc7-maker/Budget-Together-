import SwiftUI

// MARK: - Challenges
//
// Shared by the whole household: everyone's spending counts, everyone sees the
// same bar. Progress is read from the ledger, so there's no way to be winning
// on one phone and losing on another.

struct ChallengesSheet: View {
    @EnvironmentObject var model: AppModel

    @State private var templates: [Challenge] = []

    var body: some View {
        Page(title: "Challenges", subtitle: "Everyone on the budget counts", displayMode: .inline) {
            VStack(alignment: .leading, spacing: Space.lg) {
                if !model.activeChallenges.isEmpty {
                    cards(model.activeChallenges, title: "Running now")
                }

                RowGroup(title: "Start one") {
                    ForEach(templates) { template in
                        Button { model.startChallenge(template) } label: {
                            templateRow(template)
                        }
                        .buttonStyle(.row)
                        .disabled(isRunning(template))
                        .opacity(isRunning(template) ? 0.5 : 1)
                    }
                }

                if !model.finishedChallenges.isEmpty {
                    cards(model.finishedChallenges, title: "Finished")
                }
            }
        }
        .onAppear { templates = Challenge.templates(from: Date()) }
    }

    private func cards(_ challenges: [ChallengeProgress], title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionTitle(title)
            AdaptiveCards(spacing: Space.sm) {
                ForEach(challenges, id: \.challenge.id) { progress in
                    ChallengeCard(progress: progress) {
                        model.abandonChallenge(progress.challenge.id)
                    }
                }
            }
        }
    }

    /// A template counts as running if something with the same title covers the
    /// same window — starting a second No-Spend Weekend for one weekend is noise.
    private func isRunning(_ template: Challenge) -> Bool {
        model.challenges.contains {
            $0.challenge.title == template.title && $0.challenge.endDate == template.endDate
        }
    }

    private func templateRow(_ template: Challenge) -> some View {
        RowLabel(symbol: template.kind == .noSpend ? "moon.zzz.fill" : "target",
                 title: Text(template.title), subtitle: Text(window(template))) {
            Text(isRunning(template) ? "Running" : "Start")
                .appFont(12.5, weight: .semibold)
                .foregroundStyle(isRunning(template) ? Palette.muted : Palette.teal)
        }
    }

    private func window(_ challenge: Challenge) -> String {
        let span = Fmt.count(challenge.length, "day")
        guard challenge.kind == .categoryCap, let bucket = challenge.bucket else { return span }
        return "\(span) · under \(Fmt.money(challenge.target)) on \(Bucket.named(bucket).short)"
    }
}

// MARK: - Card

struct ChallengeCard: View {
    let progress: ChallengeProgress
    var onAbandon: (() -> Void)?

    private var tint: Color {
        if progress.isBroken { return Palette.over }
        if progress.isWon { return Palette.green }
        return Palette.teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                IconTile(symbol: symbol, color: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.challenge.title).appFont(14, weight: .medium)
                    Text(progress.detail)
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(progress.statusLabel)
                    .appFont(10.5, weight: .bold)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(tint.opacity(0.16), in: Capsule())
            }

            ProgressBar(pct: progress.fraction * 100, fill: tint, height: 6)

            HStack {
                Text(daysLabel).appFont(11).foregroundStyle(Palette.muted)
                Spacer()
                if let onAbandon {
                    Button(progress.hasEnded ? "Clear" : "Give up", action: onAbandon)
                        .appFont(11, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(Space.md)
        .card()
    }

    private var symbol: String {
        if progress.isBroken { return "xmark.circle.fill" }
        if progress.isWon { return "trophy.fill" }
        return progress.challenge.kind == .noSpend ? "moon.zzz.fill" : "target"
    }

    private var daysLabel: String {
        let challenge = progress.challenge
        guard !progress.hasEnded else { return "Ended \(challenge.endDate)" }
        guard let end = Fmt.day(from: challenge.endDate) else { return "" }
        let left = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return left <= 0 ? "Last day" : "\(Fmt.count(left + 1, "day")) to go"
    }
}

#Preview {
    PreviewShell { ChallengesSheet() }
}
