import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var model: AppModel
    @State private var markingUnusual = false

    var body: some View {
        let totals = model.month.totals

        Page(title: "Budget") {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(model.hasPlan
                     ? "Tap a number to change what you're aiming for in \(model.monthTitle). Later months follow it until you change them again."
                     : "Nothing's set yet — that's fine. Set what you like below, or let the app suggest limits once it's seen a few weeks of spending.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)

                if model.canSuggestPlan {
                    SuggestedPlanCard()
                }

                planCard

                // The limits come straight after the total they add up to. They
                // used to sit under five cards of settings and side-ledgers, so the
                // thing the sentence above says to tap was the one thing on the
                // screen you had to scroll to find.
                AdaptiveCards(spacing: Space.sm) {
                    ForEach(model.expenseCategories) { bucket in
                        BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                    }
                }

                strandedHiddenRows(totals: totals)

                // Everything else here is either a ledger of its own — bills,
                // goals, debts — or a setting for how the month is judged. All of
                // it matters; none of it is why somebody opened this tab.
                RowGroup(title: "Around the plan") {
                    recurringRow
                    goalsRow
                    loansRow
                    categoriesRow
                    // Nothing to carry over without a plan to have left over from.
                    if model.hasPlan { rolloverToggle }
                    unusualMonthRow
                }
                .padding(.top, Space.xs)
            }
        }
        .monthControls()
        .sheet(isPresented: $markingUnusual) { UnusualMonthSheet().environmentObject(model) }
    }

    @ViewBuilder
    private var planCard: some View {
        if model.hasPlan { plannedTotalCard } else { noPlanCard }
    }

    /// With no limits there's no total to measure against, and the planned
    /// card drew one anyway: "$0" planned, a full bar, "$0 left" — which reads
    /// as "you've spent everything" to someone who simply hasn't set anything.
    /// This says what is actually known.
    private var noPlanCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.isCurrentMonth ? "Spent so far" : "Spent in \(model.monthTitle)")
                    .appFont(13, weight: .medium).foregroundStyle(Palette.sub)
                Spacer()
                Text(Fmt.money(model.spent)).mono(18)
            }
            Text("No limits yet, so nothing to measure it against.")
                .appFont(12).foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.md)
        .card()
    }

    private var plannedTotalCard: some View {
        let totalPct = min(100, model.spent / max(model.plannedTotal, 1) * 100)
        return VStack(spacing: 0) {
            HStack {
                Text("Planned total")
                    .appFont(13, weight: .medium).foregroundStyle(Palette.sub)
                Spacer()
                Text(Fmt.money(model.plannedTotal)).mono(18)
            }
            ProgressBar(pct: totalPct, fill: Palette.tealGradient, height: 10)
                .padding(.vertical, Space.sm)
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
                .padding(.top, Space.xs)
            }
            // Stated here for the same reason the rollover is: the planned
            // total is the figure people read as "what I have", and a
            // standing promise against it belongs in the same breath. It is
            // named, not deducted — see `AppModel.leftAfterGoals`.
            if model.hasGoalPromise {
                HStack(spacing: 5) {
                    Image(systemName: "target")
                        .appFont(9.5, weight: .bold)
                    Text("\(Fmt.money(model.promisedToGoals)) a month is promised to goals, and isn't taken out of this")
                        .appFont(11)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.teal)
                .padding(.top, Space.xs)
            }
        }
        .padding(Space.md)
        .card()
    }

    /// Way into the category editor.
    private var categoriesRow: some View {
        NavigationLink(value: Route.categories) {
            RowLabel(symbol: "square.grid.2x2.fill",
                     title: Text("Categories"),
                     subtitle: Text("Rename them, recolour them, add your own"))
        }
        .buttonStyle(.row)
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
            VStack(alignment: .leading, spacing: Space.xs) {
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

                AdaptiveCards(spacing: Space.sm) {
                    ForEach(stranded) { bucket in
                        BudgetRow(bucket: bucket, actual: totals[bucket.id] ?? 0)
                    }
                }
            }
            .padding(.top, Space.xs)
        }
    }

    /// Carrying an underspend forward. Off by default, because it changes what
    /// every other number on this screen means and that should be a choice
    /// somebody made rather than one they inherited.
    private var rolloverToggle: some View {
        GroupedRow(separatorInset: Space.md + 32 + Space.sm) {
            Toggle(isOn: Binding(get: { model.rolloverEnabled },
                                 set: { model.setRollover($0) })) {
                HStack(spacing: Space.sm) {
                    IconTile(symbol: "arrow.turn.down.right", color: Palette.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Carry the leftovers over").appFont(14, weight: .medium)
                        Text(model.rolloverEnabled
                             ? "Whatever you don't spend gets added to next month."
                             : "Each month starts fresh from the same plan.")
                            .appFont(11.5).foregroundStyle(Palette.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The escape hatch for a month that genuinely wasn't typical.
    private var unusualMonthRow: some View {
        Button { markingUnusual = true } label: {
            RowLabel(symbol: model.isSelectedMonthUnusual
                     ? "calendar.badge.exclamationmark" : "calendar",
                     color: model.isSelectedMonthUnusual ? Palette.moodJoy : Palette.sub,
                     title: Text(model.isSelectedMonthUnusual
                                 ? "\(model.monthTitle) is marked unusual"
                                 : "Was this month strange?"),
                     subtitle: Text(model.isSelectedMonthUnusual
                                    ? (model.selectedMonthReason.isEmpty
                                       ? "It won't count against your streak or averages."
                                       : model.selectedMonthReason)
                                    : "A move, a wedding, a hospital bill — say so and it won't skew anything."))
        }
        .buttonStyle(.row)
    }

    /// Way into what's being saved for. Sits above `loansRow` on purpose: the
    /// two are the same shape of thing — a balance moving toward a number — and
    /// the one that's going the right way should be read first.
    private var goalsRow: some View {
        NavigationLink(value: Route.goals) {
            RowLabel(symbol: "target", title: Text("Saving for"),
                     subtitle: Text(goalsSubtitle(open: model.openGoals)))
        }
        .buttonStyle(.row)
    }

    /// Counts only what's still outstanding, so a household that has reached
    /// everything it set out to reach isn't told it has three goals running.
    private func goalsSubtitle(open: [Goal]) -> String {
        guard !model.goals.isEmpty else { return "An emergency fund, a deposit, a trip" }
        guard !open.isEmpty else {
            return "All \(Fmt.count(model.goals.count, "goal")) reached · \(Fmt.money(model.totalSaved)) put by"
        }
        let remaining = open.reduce(0) { $0 + $1.remaining }
        return "\(Fmt.money(model.totalSaved)) put by · \(Fmt.money(remaining)) to go"
    }

    private var loansRow: some View {
        NavigationLink(value: Route.loans) {
            RowLabel(symbol: "graduationcap.fill", color: Palette.moodRoutine,
                     title: Text("Owed"),
                     subtitle: Text(model.loans.isEmpty
                                    ? "Track student loans and other balances"
                                    : "\(Fmt.money(model.totalOwed)) across ^[\(model.loans.count) balance](inflect: true)"))
        }
        .buttonStyle(.row)
    }

    /// Entry point to the repeating items — bills are budget planning, not
    /// day-to-day logging, so they live here rather than behind the + button.
    private var recurringRow: some View {
        let active = model.recurring.filter(\.isActive)
        let monthly = active.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        return NavigationLink(value: Route.recurring) {
            RowLabel(symbol: "repeat", color: Palette.purple,
                     title: Text("Repeating"),
                     subtitle: Text(active.isEmpty
                                    ? "Add rent, subscriptions and paydays"
                                    : "^[\(active.count) item](inflect: true) · \(Fmt.money(monthly)) of bills a month"))
        }
        .buttonStyle(.row)
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

    /// The limit box grows with the text inside it. At a fixed 52pt, "1300"
    /// came out as "13…" at the accessibility sizes: a limit nobody could read.
    @ScaledMetric(relativeTo: .footnote) private var limitWidth: CGFloat = 52

    var body: some View {
        let cap = model.caps[bucket.id] ?? 0
        let isOver = cap > 0 && actual > cap
        let pct = cap > 0 ? min(100, actual / cap * 100) : 0

        VStack(spacing: Space.xs) {
            AdaptiveRow(spacing: Space.xs) {
                icon
                name
            } figures: {
                figures(isOver: isOver)
            }

            // No limit, no bar. A bar is a share of something, and with no
            // limit there's nothing for it to be a share of — drawn full, as it
            // was, it said "all used up" about a category with no ceiling.
            //
            // The fill stays the category's own colour even past the limit —
            // "fill encodes identity" (DESIGN-NOTES §1), which the accessibility
            // statement promises. Turned `Palette.over` instead, an overspent
            // Fun bar came out the exact coral of Housing's. Being past the
            // limit is said by the line underneath, in words and an icon.
            if cap > 0 {
                ProgressBar(pct: pct, fill: bucket.color, height: 7)
            }

            // The number people actually want: what's left, or how far past —
            // and, when it's past, the one tap that fixes it. A verdict with no
            // offered next move is just a scolding.
            HStack(spacing: 4) {
                if cap <= 0 {
                    Text("No limit set")
                        .appFont(11.5).foregroundStyle(Palette.muted)
                } else if isOver {
                    Image(systemName: "exclamationmark.circle.fill")
                        .appFont(11, weight: .semibold)
                        .foregroundStyle(Palette.overText)
                        .accessibilityHidden(true)
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
                        Label("Move money here", systemImage: "arrow.left.arrow.right")
                            .appFont(11, weight: .semibold)
                    }
                    .inlineActionStyle()
                    .accessibilityHint("Takes room from another category")
                }
            }
        }
        .padding(Space.md)
        .card()
        .sheet(isPresented: $moving) {
            MoveMoneySheet(destination: bucket).environmentObject(model)
        }
        .onAppear { limitText = Self.limitField(cap) }
        // The row keeps its identity when the limit changes underneath it —
        // switching months, a move of money, a partner's edit arriving — so the
        // text has to be re-seeded. Never while it's being typed in, though;
        // that would overwrite the half-finished number under the cursor.
        .onChange(of: cap) { _, new in
            if !editingLimit { limitText = Self.limitField(new) }
        }
    }

    private var icon: some View {
        IconTile(symbol: bucket.symbol, color: bucket.color, fill: bucket.tint)
    }

    private var name: some View {
        Text(bucket.label).appFont(14, weight: .medium).lineLimit(1)
    }

    /// What's gone, and the editable limit it's measured against.
    private func figures(isOver: Bool) -> some View {
        HStack(spacing: Space.xs) {
            Text(Fmt.money(actual)).mono(13)
                .foregroundStyle(isOver ? Palette.overText : Palette.text)
            Text("of").appFont(11.5).foregroundStyle(Palette.muted)

            HStack(spacing: 2) {
                Text(Fmt.currencySymbol).mono(12, weight: .regular).foregroundStyle(Palette.muted)
                TextField("0", text: $limitText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .appFont(13, weight: .semibold)
                    .monospacedDigit()
                    .frame(width: limitWidth)
                    .focused($editingLimit)
                    .accessibilityLabel("\(bucket.label) budget")
                    .onSubmit(commitLimit)
                    .onChange(of: editingLimit) { _, isEditing in
                        if !isEditing { commitLimit() }
                    }
            }
            .padding(.horizontal, Space.xs).padding(.vertical, 6)
            .fieldBackground(radius: Radius.tile)
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
