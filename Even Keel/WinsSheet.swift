import SwiftUI

// MARK: - Wins
//
// The other half of the feedback loop. The app already interrupts people when
// they overspend; this is what it has to say when they don't.

struct WinsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// The badges that were new when the sheet opened. Held here because
    /// opening the sheet is what marks them seen — without a copy, the "New"
    /// tags would vanish in the same frame they were due to appear in.
    @State private var fresh: Set<String> = []

    var body: some View {
        let wins = model.wins
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                StreakCard(streak: wins.streak, best: wins.bestStreak,
                           allowance: model.dailyAllowance, hasPlan: model.hasPlan)
                    .padding(.bottom, 8)

                if wins.monthsUnderBudget > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .appFont(15, weight: .semibold)
                            .foregroundStyle(Palette.teal)
                        Text("^[\(wins.monthsUnderBudget) month](inflect: true) running inside the plan")
                            .appFont(13, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .card(border: Palette.cardBorderSoft, radius: 15)
                }

                // Grouped by what they're about. Sixteen in one undivided list
                // read as a wall of locks; four short lists read as four
                // things a person might care about, one of which is usually
                // already going well.
                ForEach(Badge.Group.allCases) { group in
                    let badges = wins.badges(in: group)
                    if !badges.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.title).appFont(13, weight: .semibold)
                            Spacer(minLength: 8)
                            Text("\(badges.filter(\.isEarned).count) of \(badges.count)")
                                .appFont(11.5, weight: .medium)
                                .foregroundStyle(Palette.sub)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18).padding(.bottom, 10)

                        VStack(spacing: 8) {
                            ForEach(badges) { badge in
                                BadgeRow(badge: badge, isNew: fresh.contains(badge.id))
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
        .onAppear {
            fresh = model.newBadgeIDs
            model.markBadgesSeen()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wins").appFont(17, weight: .bold)
                Text("\(model.wins.earned.count) of \(Fmt.count(model.wins.badges.count, "badge")) earned")
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
}

/// One badge. Earned ones are stated; locked ones say what would earn them and,
/// where that's a count of something, how far along it already is.
private struct BadgeRow: View {
    let badge: Badge
    let isNew: Bool

    /// Progress is only worth showing on the way there. On an earned badge
    /// it's a full bar saying what the tick already says.
    private var progress: Badge.Progress? { badge.isEarned ? nil : badge.progress }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: badge.isEarned ? badge.symbol : "lock.fill")
                .appFont(15, weight: .semibold)
                .foregroundStyle(badge.isEarned ? Palette.tealInk : Palette.muted)
                .frame(width: 36, height: 36)
                .background {
                    if badge.isEarned { Palette.tealGradient } else { Palette.chip }
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(badge.title).appFont(14, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    if isNew {
                        Text("New")
                            .appFont(10.5, weight: .bold)
                            .foregroundStyle(Palette.tealInk)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Palette.teal, in: Capsule())
                    }
                }
                Text(badge.detail)
                    .appFont(11.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress {
                    HStack(spacing: 9) {
                        ProgressBar(pct: progress.fraction * 100, fill: Palette.teal, height: 4)
                        Text(progress.label)
                            .appFont(10.5, weight: .medium)
                            .foregroundStyle(Palette.sub)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        // Locked rows used to be dimmed to 60% as a whole, which took the detail
        // line from 5.3:1 down to 2.8:1 (2.65:1 in light) — under the floor,
        // on the one line that says how to earn the thing. The lock and the
        // grey tile already say "not yet"; the words stay at full strength.
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: isNew ? Palette.teal.opacity(0.55) : Palette.cardBorderSoft, radius: 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts = ["\(badge.title), \(isNew ? "newly earned" : badge.isEarned ? "earned" : "locked")",
                     badge.detail]
        if let progress { parts.append(progress.label) }
        return parts.joined(separator: ". ")
    }
}

/// The streak, stated plainly. A zero isn't framed as failure — it's just the
/// count, with what would start it again.
struct StreakCard: View {
    let streak: Int
    /// The longest run there has been. Mentioned only when it beats the current
    /// one: "your best is 12" beside a streak of 12 is the same fact twice.
    let best: Int
    let allowance: Double
    let hasPlan: Bool

    /// Without a plan the allowance is $0, and this used to say "Stay under $0
    /// today to start one" — the verdict `hasPlan` exists to keep off screens,
    /// and an instruction nobody can follow, since the streak needs an
    /// allowance above zero to count anything at all.
    private var detail: String {
        guard hasPlan else {
            return "A streak counts days spent inside your daily allowance. Set some limits and there'll be one to stay inside."
        }
        let now = streak > 0
            ? "Inside \(Fmt.money(allowance)) a day."
            : "Stay under \(Fmt.money(allowance)) today to start one."
        return best > streak ? now + " Your best run so far is \(Fmt.count(best, "day"))." : now
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(streak > 0 ? Palette.teal.opacity(0.16) : Palette.chip)
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .appFont(21, weight: .semibold)
                    .foregroundStyle(streak > 0 ? Palette.teal : Palette.muted)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(streak > 0 ? "^[\(streak) day](inflect: true) in a row" : "No streak yet")
                    .appFont(16, weight: .bold)
                Text(detail)
                    .appFont(12).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .card()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WinsSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
