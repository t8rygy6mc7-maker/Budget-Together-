import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let items = model.month.ranked
        let spent = model.spent
        let people = model.memberTotals

        Page(title: "Stats") {
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
                AdaptiveCards {
                    TrendChart(points: model.history)
                    CategoryCard(items: items, total: spent)

                    // Only when there's a split to show. For a budget of one this was
                    // a bar in a single colour over "You — 100%".
                    if people.count > 1 {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Who spent what").appFont(13, weight: .semibold)
                            SplitBar(shares: people).frame(height: 14)
                            // One row per person: with more than two, a single line of
                            // legends runs out of width and the shares stop comparing.
                            VStack(spacing: Space.xs) {
                                ForEach(people) { person in
                                    legend(person, share: spent > 0 ? person.total / spent * 100 : 0)
                                }
                            }
                        }
                        .padding(Space.md)
                        .card()
                    }

                    MoodCard(totals: model.month.byMood,
                             tagged: model.month.moodTagged,
                             spent: spent)

                    if !model.month.incomeRanked.isEmpty { incomeCard }
                }
            }
        }
        .monthControls()
    }

    private var incomeCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Where it came from").appFont(13, weight: .semibold)
                Spacer()
                Text("+" + Fmt.money(model.earned)).mono(13)
                    .foregroundStyle(Palette.green)
            }
            ForEach(model.month.incomeRanked) { item in
                HStack(spacing: Space.xs) {
                    IconTile(symbol: item.bucket.symbol, color: item.bucket.color,
                             fill: item.bucket.tint)
                    Text(item.bucket.label).appFont(13, weight: .medium)
                    Spacer(minLength: Space.xxs)
                    Text("+" + Fmt.money(item.total)).mono(13)
                }
            }
        }
        .padding(Space.md)
        .card()
    }

    private func legend(_ person: MemberTotal, share: Double) -> some View {
        AdaptiveRow(spacing: 7) {
            Circle().fill(person.member.color).frame(width: 9, height: 9)
            Text(person.member.name)
                .appFont(12.5, weight: .semibold)
                .lineLimit(1)
        } figures: {
            Text(Fmt.money(person.total)).mono(12.5)
            Text(Fmt.share(share))
                .appFont(11.5).foregroundStyle(Palette.sub)
                .figureColumn(width: 38)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.member.name), \(Fmt.money(person.total)), "
                          + "\(Fmt.share(share, spoken: true)) of spending")
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
        VStack(alignment: .leading, spacing: Space.sm) {
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
                        AdaptiveRow(spacing: 9) {
                            IconTile(symbol: item.mood.symbol, color: item.mood.color)
                            Text(item.mood.label).appFont(13, weight: .medium)
                        } figures: {
                            Text(Fmt.money(item.total)).mono(13)
                            Text("^[\(item.count) buy](inflect: true)")
                                .appFont(11).foregroundStyle(Palette.sub)
                                .figureColumn(width: 56)
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
        .padding(Space.md)
        .card()
    }

    /// A single observation, not a verdict — and only when the mood in question
    /// is actually the biggest driver.
    private var prompt: String? {
        guard let top = totals.first, top.mood.isWorthNoticing,
              tagged > 0, top.total / tagged >= 0.3 else { return nil }
        return "\(top.mood.label) accounts for \(Fmt.whole(top.total / tagged * 100))% of what you tagged — \(Fmt.money(top.total)) across \(Fmt.count(top.count, "buy", plural: "buys"))."
    }
}

/// Spending per month with an income marker, so a month reads in context
/// instead of in isolation. The selected month is the last bar.
struct TrendChart: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let points: [MonthPoint]

    private static let height: CGFloat = 96

    var body: some View {
        let peak = points.map { max($0.spent, $0.earned) }.max() ?? 0

        VStack(alignment: .leading, spacing: 10) {
            // The key moves under the title at the accessibility sizes, where
            // the three of them on one line wrapped "Income" into "Incom" / "e".
            if typeSize.prefersStackedLayout {
                Text("Last \(points.count) months").appFont(13, weight: .semibold)
                HStack(spacing: 12) {
                    key(Palette.teal, "Spent")
                    key(Palette.green, "Income")
                }
            } else {
                HStack {
                    Text("Last \(points.count) months").appFont(13, weight: .semibold)
                    Spacer()
                    HStack(spacing: 12) {
                        key(Palette.teal, "Spent")
                        key(Palette.green, "Income")
                    }
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
        .padding(Space.md)
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

/// The month by category: one bar of everything, biggest first, with the rows
/// that say what each piece is underneath.
///
/// This retired the eight-slice donut, as DESIGN-NOTES §3 asked. Reading a donut
/// meant cross-referencing a legend for every slice, and slices under about 5%
/// were invisible slivers. It's the same one-bar-many-colours shape iOS uses to
/// show what's filling a phone's storage.
struct CategoryCard: View {
    let items: [BucketTotal]
    let total: Double

    /// Hairline gap between pieces, so neighbours stay apart without an outline.
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("By category").appFont(13, weight: .semibold)
                Spacer()
                Text(Fmt.money(total)).mono(13)
            }

            bar

            VStack(spacing: Space.xs) {
                ForEach(items) { item in
                    let pct = item.total / max(total, 1) * 100
                    AdaptiveRow(spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.bucket.color).frame(width: 10, height: 10)
                        Text(item.bucket.label).appFont(13, weight: .medium).lineLimit(1)
                    } figures: {
                        Text(Fmt.money(item.total)).mono(13)
                        Text(Fmt.share(pct))
                            .appFont(11.5).foregroundStyle(Palette.sub)
                            .figureColumn(width: 40)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.bucket.label), \(Fmt.money(item.total)), "
                                      + "\(Fmt.share(pct, spoken: true)) of spending")
                }
            }
        }
        .padding(Space.md)
        .card()
    }

    private var bar: some View {
        GeometryReader { geo in
            let sum = max(items.reduce(0) { $0 + $1.total }, 1)
            let room = geo.size.width - Self.gap * CGFloat(max(items.count - 1, 0))
            HStack(spacing: Self.gap) {
                ForEach(items) { item in
                    // Floored like every other bar here, so a small category
                    // still shows a mark beside its amount.
                    Rectangle()
                        .fill(item.bucket.color)
                        .frame(width: max(room * item.total / sum, 3))
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

#Preview {
    PreviewShell { StatsView() }
}

#Preview("Stats — light") {
    PreviewShell(scheme: .light) { StatsView() }
}
