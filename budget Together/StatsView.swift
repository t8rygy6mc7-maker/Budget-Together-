import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let items = model.month.ranked
        let spent = model.spent
        let people = model.memberTotals

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Stats").appFont(22, weight: .bold)
                Spacer()
                MonthStepper()
            }
            .padding(.bottom, 16)

            if items.isEmpty {
                EmptyState(
                    symbol: "chart.pie",
                    title: model.isCurrentMonth
                        ? "No charts yet — nothing to chart"
                        : "Nothing was logged in \(model.monthTitle)",
                    message: model.isCurrentMonth
                        ? "This fills in on its own as you log things. A week or so is usually enough for the patterns to be worth looking at."
                        : "Step back to a month with entries in it to see how it went.",
                    actionTitle: model.isCurrentMonth ? "Add something" : nil,
                    action: model.isCurrentMonth ? { model.isAddingEntry = true } : nil
                )
            } else {
                charts(items: items, spent: spent, people: people)
            }
        }
    }

    @ViewBuilder
    private func charts(items: [BucketTotal], spent: Double,
                        people: [MemberTotal]) -> some View {
        Group {
            TrendChart(points: model.history)
                .padding(.bottom, 18)

            DonutChart(items: items, total: spent)

            VStack(alignment: .leading, spacing: 12) {
                Text("Who spent what").appFont(13, weight: .semibold)
                SplitBar(shares: people).frame(height: 14)
                // One row per person: with more than two, a single line of
                // legends runs out of width and the shares stop comparing.
                VStack(spacing: 9) {
                    ForEach(people) { person in
                        legend(person, share: spent > 0 ? person.total / spent * 100 : 0)
                    }
                }
            }
            .padding(.horizontal, 17).padding(.vertical, 16)
            .card()
            .padding(.vertical, 18)

            MoodCard(totals: model.month.byMood,
                     tagged: model.month.moodTagged,
                     spent: spent)
                .padding(.bottom, 18)

            if !model.month.incomeRanked.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("Where it came from").appFont(13, weight: .semibold)
                        Spacer()
                        Text("+" + Fmt.money(model.earned)).mono(13)
                            .foregroundStyle(Palette.green)
                    }
                    ForEach(model.month.incomeRanked) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.bucket.symbol)
                                .appFont(12, weight: .semibold)
                                .foregroundStyle(item.bucket.color)
                                .frame(width: 26, height: 26)
                                .background(item.bucket.tint,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(item.bucket.label).appFont(13, weight: .medium)
                            Spacer(minLength: 4)
                            Text("+" + Fmt.money(item.total)).mono(13)
                        }
                    }
                }
                .padding(.horizontal, 17).padding(.vertical, 16)
                .card()
                .padding(.bottom, 18)
            }

            Text("By category").appFont(13, weight: .semibold).padding(.bottom, 10)
            VStack(spacing: 11) {
                ForEach(items) { item in
                    let pct = item.total / max(spent, 1) * 100
                    VStack(spacing: 6) {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.bucket.color).frame(width: 9, height: 9)
                            Text(item.bucket.label).appFont(13, weight: .medium)
                            Spacer(minLength: 4)
                            Text(Fmt.money(item.total)).mono(13)
                            Text("\(Int(pct.rounded()))%")
                                .appFont(11.5).foregroundStyle(Palette.sub)
                                .frame(width: 38, alignment: .trailing)
                        }
                        ProgressBar(pct: pct, fill: item.bucket.color, height: 7)
                    }
                }
            }
        }
    }

    private func legend(_ person: MemberTotal, share: Double) -> some View {
        HStack(spacing: 7) {
            Circle().fill(person.member.color).frame(width: 9, height: 9)
            Text(person.member.name)
                .appFont(12.5, weight: .semibold)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Fmt.money(person.total)).mono(12.5)
            Text("\(Int(share.rounded()))%")
                .appFont(11.5).foregroundStyle(Palette.sub)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Charts

/// Capsule split into one segment per person, in household order. Zero-spend
/// members simply contribute no width.
struct SplitBar: View {
    let shares: [MemberTotal]

    var body: some View {
        GeometryReader { geo in
            let total = shares.reduce(0) { $0 + $1.total }
            HStack(spacing: 0) {
                if total > 0 {
                    ForEach(shares) { share in
                        Rectangle()
                            .fill(share.member.color)
                            .frame(width: geo.size.width * share.total / total)
                    }
                } else {
                    Rectangle().fill(Palette.field)
                }
            }
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shares.map { "\($0.member.name) \(Fmt.money($0.total))" }
            .joined(separator: ", "))
    }
}

/// What was driving the spending, when the user said. Shows nothing until a few
/// entries are tagged — a breakdown of one coffee is noise dressed as insight.
struct MoodCard: View {
    let totals: [MoodTotal]
    let tagged: Double
    let spent: Double

    /// Below this many tagged entries the split isn't worth reading.
    private static let minimumEntries = 3

    var body: some View {
        let count = totals.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 12) {
            Text("What drove it").appFont(13, weight: .semibold)

            if count < Self.minimumEntries {
                Text("Tag a few spends with how they felt and the pattern shows up here.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let note = prompt {
                    Text(note)
                        .appFont(12.5, weight: .medium)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(totals) { item in
                    VStack(spacing: 6) {
                        HStack(spacing: 9) {
                            Image(systemName: item.mood.symbol)
                                .appFont(11, weight: .semibold)
                                .foregroundStyle(item.mood.color)
                                .frame(width: 22, height: 22)
                                .background(item.mood.color.opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(item.mood.label).appFont(13, weight: .medium)
                            Spacer(minLength: 4)
                            Text(Fmt.money(item.total)).mono(13)
                            Text("^[\(item.count) buy](inflect: true)")
                                .appFont(11).foregroundStyle(Palette.sub)
                                .frame(width: 56, alignment: .trailing)
                        }
                        ProgressBar(pct: item.total / max(tagged, 1) * 100,
                                    fill: item.mood.color, height: 6)
                    }
                }

                // Tagging is partial by design, so say what share this covers.
                Text("Based on \(Fmt.money(tagged)) of \(Fmt.money(spent)) tagged.")
                    .appFont(11).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }

    /// A single observation, not a verdict — and only when the mood in question
    /// is actually the biggest driver.
    private var prompt: String? {
        guard let top = totals.first, top.mood.isWorthNoticing,
              tagged > 0, top.total / tagged >= 0.3 else { return nil }
        return "\(top.mood.label) accounts for \(Int((top.total / tagged * 100).rounded()))% of what you tagged — \(Fmt.money(top.total)) across \(Fmt.count(top.count, "buy", plural: "buys"))."
    }
}

/// Spending per month with an income marker, so a month reads in context
/// instead of in isolation. The selected month is the last bar.
struct TrendChart: View {
    let points: [MonthPoint]

    private static let height: CGFloat = 96

    var body: some View {
        let peak = points.map { max($0.spent, $0.earned) }.max() ?? 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last \(points.count) months").appFont(13, weight: .semibold)
                Spacer()
                HStack(spacing: 12) {
                    key(Palette.teal, "Spent")
                    key(Palette.green, "Income")
                }
            }

            if peak <= 0 {
                Text("No history yet — it fills in as months go by.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(points) { point in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                // Income sits behind as a hollow outline, so two
                                // series share one column without stacking.
                                Capsule()
                                    .strokeBorder(Palette.green.opacity(0.75), lineWidth: 1.5)
                                    .frame(width: 26, height: bar(point.earned, peak))
                                Capsule()
                                    .fill(Palette.teal.opacity(0.9))
                                    .frame(width: 12, height: bar(point.spent, peak))
                            }
                            .frame(height: Self.height, alignment: .bottom)

                            Text(point.label)
                                .appFont(10, weight: .semibold)
                                .foregroundStyle(Palette.sub)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(point.label): spent \(Fmt.money(point.spent)), income \(Fmt.money(point.earned))")
                    }
                }
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 16)
        .card()
    }

    /// Linear against the tallest month, floored so a tiny month is still visible.
    private func bar(_ value: Double, _ peak: Double) -> CGFloat {
        guard value > 0, peak > 0 else { return 0 }
        return max(3, Self.height * value / peak)
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).appFont(11).foregroundStyle(Palette.sub)
        }
    }
}

struct DonutChart: View {
    let items: [BucketTotal]
    let total: Double

    private static let diameter: CGFloat = 168
    private static let holeDiameter: CGFloat = 108

    var body: some View {
        ZStack {
            Canvas { context, size in
                let sum = items.reduce(0) { $0 + $1.total }
                guard sum > 0 else { return }

                let radius = min(size.width, size.height) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var start = -90.0

                for item in items {
                    let end = start + item.total / sum * 360
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(start), endAngle: .degrees(end),
                                clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(item.bucket.color))
                    start = end
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)

            Circle().fill(Palette.screen)
                .frame(width: Self.holeDiameter, height: Self.holeDiameter)

            VStack(spacing: 2) {
                Text("Total").appFont(11, weight: .medium).foregroundStyle(Palette.sub)
                Text(Fmt.money(total)).mono(22)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total spent \(Fmt.money(total))")
    }
}

#Preview {
    PreviewShell { StatsView() }
}

#Preview("Stats — light") {
    PreviewShell(scheme: .light) { StatsView() }
}
