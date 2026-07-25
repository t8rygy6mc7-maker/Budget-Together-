import SwiftUI

// MARK: - Wins
//
// The other half of the feedback loop. The app already interrupts people when
// they overspend; this is what it has to say when they don't.

struct WinsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let wins = model.wins
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                StreakCard(streak: wins.streak, allowance: model.dailyAllowance)
                    .padding(.bottom, 8)

                if wins.monthsUnderBudget > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.teal)
                        Text("^[\(wins.monthsUnderBudget) month](inflect: true) running inside the plan")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .card(border: Palette.cardBorderSoft, radius: 15)
                    .padding(.bottom, 18)
                }

                Text("Badges").font(.system(size: 13, weight: .semibold))
                    .padding(.bottom, 10)

                VStack(spacing: 8) {
                    ForEach(wins.badges) { badge in
                        HStack(spacing: 12) {
                            Image(systemName: badge.isEarned ? badge.symbol : "lock.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(badge.isEarned ? Palette.tealInk : Palette.muted)
                                .frame(width: 36, height: 36)
                                .background {
                                    if badge.isEarned { Palette.tealGradient } else { Palette.chip }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(badge.title).font(.system(size: 14, weight: .semibold))
                                Text(badge.detail)
                                    .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(badge.isEarned ? 1 : 0.6)
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .card(border: Palette.cardBorderSoft, radius: 15)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(badge.title), \(badge.isEarned ? "earned" : "locked"). \(badge.detail)")
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wins").font(.system(size: 17, weight: .bold))
                Text("^[\(model.wins.earned.count) badge](inflect: true) earned")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 16)
    }
}

/// The streak, stated plainly. A zero isn't framed as failure — it's just the
/// count, with what would start it again.
struct StreakCard: View {
    let streak: Int
    let allowance: Double

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(streak > 0 ? Palette.teal.opacity(0.16) : Palette.chip)
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(streak > 0 ? Palette.teal : Palette.muted)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(streak > 0 ? "^[\(streak) day](inflect: true) in a row" : "No streak yet")
                    .font(.system(size: 16, weight: .bold))
                Text(streak > 0
                     ? "Inside \(Fmt.money(allowance)) a day."
                     : "Stay under \(Fmt.money(allowance)) today to start one.")
                    .font(.system(size: 12)).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .card()
    }
}

#Preview {
    WinsSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
