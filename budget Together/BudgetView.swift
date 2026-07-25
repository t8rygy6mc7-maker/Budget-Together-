import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let totals = model.month.totals
        let totalPct = min(100, model.spent / max(model.capTotal, 1) * 100)

        VStack(alignment: .leading, spacing: 0) {
            Text("Budget").font(.system(size: 22, weight: .bold))
            Text("Tap a number to set each cap for \(model.monthTitle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.sub)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                HStack {
                    Text("Planned total")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.sub)
                    Spacer()
                    Text(Fmt.money(model.capTotal)).mono(18)
                }
                ProgressBar(pct: totalPct, fill: Palette.tealGradient, height: 10)
                    .padding(.vertical, 10)
                HStack {
                    Text("\(Fmt.money(model.spent)) spent")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.teal)
                    Spacer()
                    Text("\(Fmt.money(model.left)) left")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.sub)
                }
            }
            .padding(.horizontal, 17).padding(.vertical, 16)
            .card()
            .padding(.bottom, 16)

            VStack(spacing: 9) {
                ForEach(Bucket.all) { bucket in
                    BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                }
            }
        }
    }
}

struct BudgetRow: View {
    @EnvironmentObject var model: AppModel
    let bucket: Bucket
    let actual: Double

    var body: some View {
        let cap = model.caps[bucket.id] ?? 0
        let isOver = cap > 0 && actual > cap
        let pct = cap > 0 ? min(100, actual / cap * 100) : (actual > 0 ? 100 : 0)

        VStack(spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: bucket.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bucket.color)
                    .frame(width: 32, height: 32)
                    .background(bucket.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(bucket.label).font(.system(size: 14, weight: .semibold))

                Spacer(minLength: 4)

                Text(Fmt.money(actual)).mono(13)
                    .foregroundStyle(isOver ? Palette.overText : Palette.text)
                Text("/").font(.system(size: 13)).foregroundStyle(Palette.muted)

                HStack(spacing: 2) {
                    Text("$").mono(12, weight: .regular).foregroundStyle(Palette.muted)
                    TextField("", value: model.capBinding(bucket.id), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 52)
                        .accessibilityLabel("\(bucket.label) budget")
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .fieldBackground(radius: 10)
            }

            ProgressBar(pct: pct, fill: isOver ? Palette.over : bucket.color, height: 7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }
}

#Preview {
    PreviewShell { BudgetView() }
}
