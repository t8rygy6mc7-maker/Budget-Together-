import SwiftUI

// MARK: - Looking ahead
//
// The forecast, what to do about it, and the repeating charges the ledger has
// noticed. Everything here is computed on the device from entries the user
// logged — nothing leaves the phone and nothing is guessed at.

struct InsightsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForecastCard(forecast: model.forecast).padding(.bottom, 18)

                if !model.suggestions.isEmpty {
                    Text("What would help").appFont(13, weight: .semibold)
                        .padding(.bottom, 10)
                    VStack(spacing: 8) {
                        ForEach(model.suggestions) { SuggestionRow(suggestion: $0) }
                    }
                    .padding(.bottom, 18)
                }

                subscriptionSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Looking ahead").appFont(17, weight: .bold)
                Text("Worked out on this device")
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

    @ViewBuilder
    private var subscriptionSection: some View {
        let found = model.subscriptions
        VStack(alignment: .leading, spacing: 10) {
            Text("Repeating charges").appFont(13, weight: .semibold)

            if found.isEmpty {
                Text("Nothing repeating found yet. A charge shows up here once it's appeared at a similar amount in three different months.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(found) { item in
                    HStack(spacing: 12) {
                        Image(systemName: Bucket.named(item.bucket).symbol)
                            .appFont(14, weight: .semibold)
                            .foregroundStyle(Bucket.named(item.bucket).color)
                            .frame(width: 32, height: 32)
                            .background(Bucket.named(item.bucket).tint,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place)
                                .appFont(14, weight: .semibold).lineLimit(1)
                            Text(subtitle(for: item))
                                .appFont(11.5)
                                .foregroundStyle(item.looksLapsed ? Palette.overText : Palette.sub)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text(Fmt.money(item.typicalAmount)).mono(13)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .card(border: Palette.cardBorderSoft, radius: 15)
                }

                Text("The app can see what repeats, not whether you still use it — that part's your call.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func subtitle(for item: DetectedSubscription) -> String {
        if item.looksLapsed {
            return "Nothing for \(Fmt.count(item.daysSinceLast, "day")) — stopped, or worth checking?"
        }
        let tracked = item.isTracked ? "tracked" : "not set up as repeating"
        return "Seen \(Fmt.count(item.occurrences, "time")) · \(tracked)"
    }
}

// MARK: - Cards

struct ForecastCard: View {
    let forecast: Forecast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where this month lands").appFont(13, weight: .semibold)

            if !forecast.isReliable {
                Text("A few more days of spending and there'll be enough to forecast from.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.money(forecast.projected)).mono(30)
                    Text(forecast.isOverPlan
                         ? "\(Fmt.money(forecast.overBy)) over"
                         : "\(Fmt.money(forecast.underBy)) under")
                        .appFont(13, weight: .semibold)
                        .foregroundStyle(forecast.isOverPlan ? Palette.over : Palette.teal)
                }

                ProgressBar(pct: min(100, forecast.projected / max(forecast.plan, 1) * 100),
                            fill: forecast.isOverPlan ? AnyShapeStyle(Palette.over)
                                                      : AnyShapeStyle(Palette.tealGradient),
                            height: 8)

                Text(verbatim: "Against a \(Fmt.money(forecast.plan)) plan, from \(Fmt.count(forecast.daysElapsed, "day")) of spending"
                     + (forecast.billsToCome > 0
                        ? " plus \(Fmt.money(forecast.billsToCome)) of bills still due."
                        : "."))
                    .appFont(11.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }
}

struct SuggestionRow: View {
    let suggestion: Suggestion

    private var tint: Color {
        switch suggestion.weight {
        case .win:     Palette.teal
        case .nudge:   Palette.moodRoutine
        case .warning: Palette.over
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.symbol)
                .appFont(14, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title).appFont(14, weight: .semibold)
                Text(suggestion.detail)
                    .appFont(12).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InsightsSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
