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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

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
                    confirmButton
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
            source = donors.first?.bucket.id
            if shortfall > 0 { amount = Fmt.plain(shortfall.rounded(.up)) }
            amountFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Give \(destination.label) more room")
                    .appFont(17, weight: .bold)
                Text(shortfall > 0
                     ? "It's \(Fmt.money(shortfall)) past its limit. Take that from somewhere with room to spare."
                     : "Take some room from a category that isn't using it.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 18)
    }

    private var amountField: some View {
        HStack(spacing: 2) {
            Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .multilineTextAlignment(.center)
                .appFont(40, weight: .bold, design: .monospaced)
                .frame(maxWidth: 200)
                .accessibilityLabel("Amount to move")
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Take it from")
                .appFont(12, weight: .semibold)
                .foregroundStyle(Palette.sub)

            VStack(spacing: 8) {
                ForEach(donors, id: \.bucket.id) { donor in
                    let isSelected = source == donor.bucket.id
                    let isEnough = Fmt.amount(from: amount).map { $0 <= donor.available } ?? true
                    Button {
                        Haptics.selected()
                        source = donor.bucket.id
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: donor.bucket.symbol)
                                .appFont(14, weight: .semibold)
                                .foregroundStyle(donor.bucket.color)
                                .frame(width: 32, height: 32)
                                .background(donor.bucket.tint,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(donor.bucket.label).appFont(13.5, weight: .semibold)
                                Text("\(Fmt.money(donor.available)) unspent")
                                    .appFont(11.5)
                                    .foregroundStyle(isEnough ? Palette.sub : Palette.over)
                            }
                            Spacer(minLength: 4)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .appFont(16, weight: .semibold)
                                    .foregroundStyle(Palette.teal)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                        .fieldBackground(isSelected ? AnyShapeStyle(Palette.teal.opacity(0.10))
                                                    : AnyShapeStyle(Palette.card),
                                         border: isSelected ? Palette.teal : Palette.cardBorder,
                                         radius: 13)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        let value = requested
        let overdrawn = Fmt.amount(from: amount) != nil && value == nil && source != nil

        VStack(spacing: 8) {
            Button {
                guard let value, let source else { return }
                model.moveBudget(from: source, to: destination.id, amount: value)
                dismiss()
            } label: {
                Text(value.map { "Move \(Fmt.money($0))" } ?? "Move")
                    .appFont(15, weight: .bold)
                    .frame(maxWidth: .infinity).padding(15)
                    .foregroundStyle(value != nil ? Palette.tealInk : Palette.muted)
                    .background {
                        if value != nil { Palette.tealGradient } else { Palette.chip }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .disabled(value == nil)

            if overdrawn, let source {
                Text("That's more than \(Bucket.named(source).label) has spare "
                   + "(\(Fmt.money(model.movableAmount(from: source)))).")
                    .appFont(11.5)
                    .foregroundStyle(Palette.over)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your plan total doesn't change — this just moves room between categories.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 20)
    }
}

#Preview {
    MoveMoneySheet(destination: Bucket.named("food"))
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
