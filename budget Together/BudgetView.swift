import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var model: AppModel
    @State private var showRecurring = false

    var body: some View {
        let totals = model.month.totals
        let totalPct = min(100, model.spent / max(model.capTotal, 1) * 100)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Budget").font(.system(size: 22, weight: .bold))
                Spacer()
                MonthStepper()
            }
            Text("Tap a number to set each cap for \(model.monthTitle). Later months inherit it until you change them.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 16)

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
            .padding(.bottom, 12)

            recurringCard
                .padding(.bottom, 16)

            VStack(spacing: 9) {
                ForEach(Bucket.all) { bucket in
                    BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                }
            }
        }
        .sheet(isPresented: $showRecurring) { RecurringSheet().environmentObject(model) }
    }

    /// Entry point to the repeating items — bills are budget planning, not
    /// day-to-day logging, so they live here rather than behind the + button.
    private var recurringCard: some View {
        let active = model.recurring.filter(\.isActive)
        let monthly = active.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        return Button { showRecurring = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.purple)
                    .frame(width: 34, height: 34)
                    .background(Palette.purple.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeating").font(.system(size: 14, weight: .semibold))
                    Text(active.isEmpty
                         ? "Add rent, subscriptions and paydays"
                         : "^[\(active.count) item](inflect: true) · \(Fmt.money(monthly)) of bills a month")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
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

            // The number people actually want: what's left, or how far past.
            HStack(spacing: 4) {
                if cap <= 0 {
                    Text("No cap set")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                } else if isOver {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Over by \(Fmt.money(actual - cap))")
                        .font(.system(size: 11.5, weight: .semibold))
                } else {
                    Text("\(Fmt.money(cap - actual)) left")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOver ? Palette.overText : Palette.sub)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }
}

#Preview {
    PreviewShell { BudgetView() }
}
