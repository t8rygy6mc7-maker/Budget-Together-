import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var model: AppModel
    @State private var showRecurring = false
    @State private var showLoans = false
    @State private var markingUnusual = false
    @State private var showCategories = false

    var body: some View {
        let totals = model.month.totals
        let totalPct = min(100, model.spent / max(model.plannedTotal, 1) * 100)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Budget").appFont(22, weight: .bold)
                Spacer()
                MonthStepper()
            }
            Text(model.hasPlan
                 ? "Tap a number to change what you're aiming for in \(model.monthTitle). Later months follow it until you change them again."
                 : "Nothing's set yet — that's fine. Set what you like here, or let the app suggest limits once it's seen a few weeks of spending.")
                .appFont(13, weight: .medium)
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 16)

            if model.canSuggestPlan {
                SuggestedPlanCard().padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Planned total")
                        .appFont(13, weight: .medium).foregroundStyle(Palette.sub)
                    Spacer()
                    Text(Fmt.money(model.plannedTotal)).mono(18)
                }
                ProgressBar(pct: totalPct, fill: Palette.tealGradient, height: 10)
                    .padding(.vertical, 10)
                HStack {
                    Text("\(Fmt.money(model.spent)) spent")
                        .appFont(12.5, weight: .semibold).foregroundStyle(Palette.teal)
                    Spacer()
                    Text("\(Fmt.money(model.left)) left")
                        .appFont(12.5, weight: .semibold).foregroundStyle(Palette.sub)
                }
                if model.rollover > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .appFont(9.5, weight: .bold)
                        Text("Includes \(Fmt.money(model.rollover)) carried over from \(model.previousMonthName)")
                            .appFont(11)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.green)
                    .padding(.top, 9)
                }
            }
            .padding(.horizontal, 17).padding(.vertical, 16)
            .card()
            .padding(.bottom, 12)

            rolloverToggle.padding(.bottom, 9)
            unusualMonthCard.padding(.bottom, 9)

            recurringCard
                .padding(.bottom, 9)

            loansCard
                .padding(.bottom, 16)

            VStack(spacing: 9) {
                ForEach(model.expenseCategories) { bucket in
                    BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                }
            }

            categoriesCard.padding(.top, 12)
            strandedHiddenRows(totals: totals)
        }
        .sheet(isPresented: $showRecurring) { RecurringSheet().environmentObject(model) }
        .sheet(isPresented: $showLoans) { LoansSheet().environmentObject(model) }
        .sheet(isPresented: $markingUnusual) { UnusualMonthSheet().environmentObject(model) }
        .sheet(isPresented: $showCategories) { CategoriesSheet().environmentObject(model) }
    }

    /// Way into the category editor.
    private var categoriesCard: some View {
        Button { showCategories = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.teal)
                    .frame(width: 34, height: 34)
                    .background(Palette.teal.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Categories").appFont(14, weight: .semibold)
                    Text("Rename them, recolour them, add your own")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    /// Hidden categories that still hold a limit or this month's spending.
    ///
    /// Hiding doesn't touch the arithmetic — the limit still counts toward the
    /// planned total and the spending still counts toward what's gone. If these
    /// rows weren't surfaced somewhere, that money would be inside the totals
    /// with no row on the screen that accounts for it, which is the sort of
    /// discrepancy that makes people stop trusting the whole app.
    @ViewBuilder
    private func strandedHiddenRows(totals: [String: Double]) -> some View {
        let stranded = model.hiddenCategories(for: .expense)
            .filter { (model.caps[$0.id] ?? 0) > 0 || (totals[$0.id] ?? 0) > 0 }
        if !stranded.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .appFont(10, weight: .semibold)
                    Text("Hidden, but still counting")
                        .appFont(12, weight: .semibold)
                }
                .foregroundStyle(Palette.sub)

                Text("These aren't offered when you log something, but they still "
                   + "hold a limit or this month's spending, so they're still part "
                   + "of the totals above.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(stranded) { bucket in
                    BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                }
            }
            .padding(.top, 22)
        }
    }

    /// Carrying an underspend forward. Off by default, because it changes what
    /// every other number on this screen means and that should be a choice
    /// somebody made rather than one they inherited.
    private var rolloverToggle: some View {
        Toggle(isOn: Binding(get: { model.rolloverEnabled },
                             set: { model.setRollover($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Carry the leftovers over").appFont(13.5, weight: .semibold)
                Text(model.rolloverEnabled
                     ? "Whatever you don't spend gets added to next month."
                     : "Each month starts fresh from the same plan.")
                    .appFont(11.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }

    /// The escape hatch for a month that genuinely wasn't typical.
    private var unusualMonthCard: some View {
        Button { markingUnusual = true } label: {
            HStack(spacing: 12) {
                Image(systemName: model.isSelectedMonthUnusual
                      ? "calendar.badge.exclamationmark" : "calendar")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(model.isSelectedMonthUnusual ? Palette.moodJoy : Palette.sub)
                    .frame(width: 34, height: 34)
                    .background((model.isSelectedMonthUnusual ? Palette.moodJoy : Palette.sub)
                        .opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isSelectedMonthUnusual
                         ? "\(model.monthTitle) is marked unusual"
                         : "Was this month strange?")
                        .appFont(14, weight: .semibold)
                    Text(model.isSelectedMonthUnusual
                         ? (model.selectedMonthReason.isEmpty
                            ? "It won't count against your streak or averages."
                            : model.selectedMonthReason)
                         : "A move, a wedding, a hospital bill — say so and it won't skew anything.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    private var loansCard: some View {
        Button { showLoans = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.moodRoutine)
                    .frame(width: 34, height: 34)
                    .background(Palette.moodRoutine.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Owed").appFont(14, weight: .semibold)
                    Text(model.loans.isEmpty
                         ? "Track student loans and other balances"
                         : "\(Fmt.money(model.totalOwed)) across ^[\(model.loans.count) balance](inflect: true)")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    /// Entry point to the repeating items — bills are budget planning, not
    /// day-to-day logging, so they live here rather than behind the + button.
    private var recurringCard: some View {
        let active = model.recurring.filter(\.isActive)
        let monthly = active.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        return Button { showRecurring = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.purple)
                    .frame(width: 34, height: 34)
                    .background(Palette.purple.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeating").appFont(14, weight: .semibold)
                    Text(active.isEmpty
                         ? "Add rent, subscriptions and paydays"
                         : "^[\(active.count) item](inflect: true) · \(Fmt.money(monthly)) of bills a month")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
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

    @State private var moving = false

    /// The limit is edited as text, not as a `Double` bound straight to the
    /// field. A numeric binding only writes back when what's typed parses, so
    /// an emptied box wrote nothing at all and then redrew from the limit still
    /// in the model — clearing it and pressing return put the old number back,
    /// and "no limit" was a state the row could show but never be given.
    @State private var limitText = ""
    @FocusState private var editingLimit: Bool

    var body: some View {
        let cap = model.caps[bucket.id] ?? 0
        let isOver = cap > 0 && actual > cap
        let pct = cap > 0 ? min(100, actual / cap * 100) : (actual > 0 ? 100 : 0)

        VStack(spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: bucket.symbol)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(bucket.color)
                    .frame(width: 32, height: 32)
                    .background(bucket.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(bucket.label).appFont(14, weight: .semibold)

                Spacer(minLength: 4)

                Text(Fmt.money(actual)).mono(13)
                    .foregroundStyle(isOver ? Palette.overText : Palette.text)
                Text("/").appFont(13).foregroundStyle(Palette.muted)

                HStack(spacing: 2) {
                    Text(Fmt.currencySymbol).mono(12, weight: .regular).foregroundStyle(Palette.muted)
                    TextField("0", text: $limitText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .appFont(13, weight: .bold, design: .monospaced)
                        .frame(width: 52)
                        .focused($editingLimit)
                        .accessibilityLabel("\(bucket.label) budget")
                        .onSubmit(commitLimit)
                        .onValueChange(of: editingLimit) { isEditing in
                            if !isEditing { commitLimit() }
                        }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .fieldBackground(radius: 10)
            }

            ProgressBar(pct: pct, fill: isOver ? Palette.over : bucket.color, height: 7)

            // The number people actually want: what's left, or how far past —
            // and, when it's past, the one tap that fixes it. A red bar with no
            // offered next move is just a scolding.
            HStack(spacing: 4) {
                if cap <= 0 {
                    Text("No limit set")
                        .appFont(11.5).foregroundStyle(Palette.muted)
                } else if isOver {
                    Text("\(Fmt.money(actual - cap)) past the limit")
                        .appFont(11.5, weight: .semibold)
                        .foregroundStyle(Palette.overText)
                } else {
                    Text("\(Fmt.money(cap - actual)) left")
                        .appFont(11.5, weight: .semibold)
                        .foregroundStyle(Palette.sub)
                }

                Spacer(minLength: 4)

                if isOver, model.isCurrentMonth {
                    Button { moving = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .appFont(9.5, weight: .bold)
                            Text("Move money here").appFont(11, weight: .bold)
                        }
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Palette.teal.opacity(0.14), in: Capsule())
                    }
                    .accessibilityHint("Takes room from another category")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
        .sheet(isPresented: $moving) {
            MoveMoneySheet(destination: bucket).environmentObject(model)
        }
        .onAppear { limitText = Self.limitField(cap) }
        // The row keeps its identity when the limit changes underneath it —
        // switching months, a move of money, a partner's edit arriving — so the
        // text has to be re-seeded. Never while it's being typed in, though;
        // that would overwrite the half-finished number under the cursor.
        .onValueChange(of: cap) { new in
            if !editingLimit { limitText = Self.limitField(new) }
        }
    }

    /// Writes what's in the box back as the limit.
    ///
    /// An empty field is taken at its word — 0, no limit. Text that isn't a
    /// number at all is not: that's a fumbled paste, and wiping a real limit
    /// over it would be a worse answer than putting the limit back.
    private func commitLimit() {
        let stored = model.caps[bucket.id] ?? 0
        let value = Fmt.limit(from: limitText) ?? stored
        if value != stored { model.setCap(bucket.id, to: value) }
        limitText = Self.limitField(value)
    }

    /// No limit shows as an empty box against the "0" placeholder, so the row
    /// reads as "nothing set here yet" rather than "budgeted zero".
    private static func limitField(_ cap: Double) -> String {
        cap > 0 ? Fmt.plain(cap) : ""
    }
}

#Preview {
    PreviewShell { BudgetView() }
}

#Preview("Budget — light") {
    PreviewShell(scheme: .light) { BudgetView() }
}
