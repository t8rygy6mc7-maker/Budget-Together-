import SwiftUI

// MARK: - Looking ahead
//
// The forecast, what to do about it, and the repeating charges the ledger has
// noticed. Everything here is computed on the device from entries the user
// logged — nothing leaves the phone and nothing is guessed at.

struct InsightsSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Page(title: "Looking ahead", subtitle: "Worked out on this device", displayMode: .inline) {
            VStack(alignment: .leading, spacing: Space.lg) {
                ForecastCard(forecast: model.forecast)

                if !model.suggestions.isEmpty {
                    RowGroup(title: "What would help") {
                        ForEach(model.suggestions) { SuggestionRow(suggestion: $0) }
                    }
                }

                subscriptionSection
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        let found = model.subscriptions
        if found.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionTitle("Repeating charges")
                Text("Nothing repeating found yet. A charge shows up here once it's appeared at a similar amount in three different months.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.md)
            }
        } else {
            RowGroup(title: "Repeating charges",
                     footer: "The app can see what repeats, not whether you still use it — that part's your call.") {
                ForEach(found) { item in
                    let bucket = Bucket.named(item.bucket)
                    RowLabel(symbol: bucket.symbol, color: bucket.color, fill: bucket.tint,
                             title: Text(item.place),
                             subtitle: Text(subtitle(for: item)),
                             subtitleColor: item.looksLapsed ? Palette.overText : Palette.sub) {
                        Text(Fmt.money(item.typicalAmount)).mono(13)
                    }
                }
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
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        RowLabel(symbol: suggestion.symbol, color: tint,
                 title: Text(suggestion.title), subtitle: Text(suggestion.detail)) {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PreviewShell { InsightsSheet() }
}
