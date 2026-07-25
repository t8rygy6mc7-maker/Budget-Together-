import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let items = model.month.ranked
        let spent = model.spent
        let people = model.memberTotals

        VStack(alignment: .leading, spacing: 0) {
            Text("Stats").font(.system(size: 22, weight: .bold)).padding(.bottom, 16)

            DonutChart(items: items, total: spent)

            VStack(alignment: .leading, spacing: 12) {
                Text("Who spent what").font(.system(size: 13, weight: .semibold))
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

            Text("By category").font(.system(size: 13, weight: .semibold)).padding(.bottom, 10)
            VStack(spacing: 11) {
                ForEach(items) { item in
                    let pct = item.total / max(spent, 1) * 100
                    VStack(spacing: 6) {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.bucket.color).frame(width: 9, height: 9)
                            Text(item.bucket.label).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 4)
                            Text(Fmt.money(item.total)).mono(13)
                            Text("\(Int(pct.rounded()))%")
                                .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
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
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Fmt.money(person.total)).mono(12.5)
            Text("\(Int(share.rounded()))%")
                .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
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
                Text("Total").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.sub)
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
