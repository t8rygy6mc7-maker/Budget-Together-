import SwiftUI

// MARK: - Move money
//
// The way out of an over-budget category. Every budgeting app is happy to tell
// you a bar is red; almost none of them offer to do anything about it, which
// leaves "I overspent on food" sitting there as a verdict with no next move.
//
// The plan total never changes here. That's what keeps this honest — it's a
// reallocation between categories, not a quiet raise, so a household that keeps
// reaching for it can still see the overall number holding steady.

struct MoveMoneySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The category that needs the money.
    let destination: Bucket

    @State private var source: String?
    @State private var amount = ""
    @FocusState private var amountFocused: Bool

    /// Prefilled with exactly what it would take to get back to level — the
    /// number the user would otherwise have to work out themselves.
    private var shortfall: Double {
        let cap = model.caps[destination.id] ?? 0
        let spent = model.month.totals[destination.id] ?? 0
        return max(0, spent - cap)
    }

    private var donors: [(bucket: Bucket, available: Double)] {
        model.donorBuckets(excluding: destination.id)
    }

    private var requested: Double? {
        guard let value = Fmt.amount(from: amount), let source else { return nil }
        guard value <= model.movableAmount(from: source) else { return nil }
        return value
    }

    var body: some View {
        ModalPage(title: "Give \(destination.label) more room",
                  subtitle: shortfall > 0
                      ? "\(Fmt.money(shortfall)) past its limit"
                      : "From a category that isn't using it",
                  detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: 0) {
                if donors.isEmpty {
                    EmptyState(
                        symbol: "tray",
                        title: "Nothing spare to move",
                        message: "Every other category is already spent up to its limit. "
                               + "Raising the limit on \(destination.label) directly might be the "
                               + "more honest fix this month."
                    )
                } else {
                    amountField
                    sourcePicker
                    moveFootnote
                }
            }
            .toolbar {
                if !donors.isEmpty {
                    ConfirmItem(title: requested.map { "Move \(Fmt.money($0))" } ?? "Move",
                                isEnabled: requested != nil) {
                        guard let requested, let source else { return }
                        model.moveBudget(from: source, to: destination.id, amount: requested)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            source = donors.first?.bucket.id
            if shortfall > 0 { amount = Fmt.plain(shortfall.rounded(.up)) }
            amountFocused = true
        }
    }

    private var amountField: some View {
        HStack(spacing: 2) {
            Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .multilineTextAlignment(.center)
                .appFont(40, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .frame(maxWidth: 200)
                .accessibilityLabel("Amount to move")
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Space.lg)
    }

    private var sourcePicker: some View {
        RowGroup(title: "Take it from") {
            ForEach(donors, id: \.bucket.id) { donor in
                let isSelected = source == donor.bucket.id
                let isEnough = Fmt.amount(from: amount).map { $0 <= donor.available } ?? true
                Button {
                    Haptics.selected()
                    source = donor.bucket.id
                } label: {
                    RowLabel(symbol: donor.bucket.symbol, color: donor.bucket.color,
                             fill: donor.bucket.tint,
                             title: Text(donor.bucket.label),
                             subtitle: Text("\(Fmt.money(donor.available)) unspent"),
                             subtitleColor: isEnough ? Palette.sub : Palette.over) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .appFont(14, weight: .semibold)
                                .foregroundStyle(Palette.teal)
                        }
                    }
                }
                .buttonStyle(.row)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var moveFootnote: some View {
        let overdrawn = Fmt.amount(from: amount) != nil && requested == nil && source != nil

        Group {
            if overdrawn, let source {
                Text("That's more than \(Bucket.named(source).label) has spare "
                   + "(\(Fmt.money(model.movableAmount(from: source)))).")
                    .foregroundStyle(Palette.over)
            } else {
                Text("Your plan total doesn't change — this just moves room between categories.")
                    .foregroundStyle(Palette.muted)
            }
        }
        .appFont(11.5)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.sm)
        .padding(.horizontal, Space.md)
    }
}

#Preview {
    MoveMoneySheet(destination: Bucket.named("food"))
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
