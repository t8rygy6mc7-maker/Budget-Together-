import SwiftUI

// MARK: - Challenges
//
// Shared by the whole household: everyone's spending counts, everyone sees the
// same bar. Progress is read from the ledger, so there's no way to be winning
// on one phone and losing on another.

struct ChallengesSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [Challenge] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if !model.activeChallenges.isEmpty {
                    Text("Running now").appFont(13, weight: .semibold)
                        .padding(.bottom, 10)
                    VStack(spacing: 8) {
                        ForEach(model.activeChallenges, id: \.challenge.id) { progress in
                            ChallengeCard(progress: progress) {
                                model.abandonChallenge(progress.challenge.id)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }

                Text("Start one").appFont(13, weight: .semibold)
                    .padding(.bottom, 10)
                VStack(spacing: 8) {
                    ForEach(templates) { template in
                        Button { model.startChallenge(template) } label: {
                            templateRow(template)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning(template))
                        .opacity(isRunning(template) ? 0.5 : 1)
                    }
                }

                if !model.finishedChallenges.isEmpty {
                    Text("Finished").appFont(13, weight: .semibold)
                        .padding(.top, 20).padding(.bottom, 10)
                    VStack(spacing: 8) {
                        ForEach(model.finishedChallenges, id: \.challenge.id) { progress in
                            ChallengeCard(progress: progress) {
                                model.abandonChallenge(progress.challenge.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .onAppear { templates = Challenge.templates(from: Date()) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Challenges").appFont(17, weight: .bold)
                Text("Everyone on the budget counts")
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

    /// A template counts as running if something with the same title covers the
    /// same window — starting a second No-Spend Weekend for one weekend is noise.
    private func isRunning(_ template: Challenge) -> Bool {
        model.challenges.contains {
            $0.challenge.title == template.title && $0.challenge.endDate == template.endDate
        }
    }

    private func templateRow(_ template: Challenge) -> some View {
        HStack(spacing: 12) {
            Image(systemName: template.kind == .noSpend ? "moon.zzz.fill" : "target")
                .appFont(15, weight: .semibold)
                .foregroundStyle(Palette.teal)
                .frame(width: 34, height: 34)
                .background(Palette.teal.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).appFont(14, weight: .semibold)
                Text(window(template)).appFont(11.5).foregroundStyle(Palette.sub)
            }
            Spacer(minLength: 4)
            Text(isRunning(template) ? "Running" : "Start")
                .appFont(12, weight: .bold)
                .foregroundStyle(isRunning(template) ? Palette.muted : Palette.teal)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.challenge.title).appFont(14, weight: .semibold)
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
        .padding(.horizontal, 13).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
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
    ChallengesSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
