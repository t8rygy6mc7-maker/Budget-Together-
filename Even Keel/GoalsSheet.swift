import SwiftUI

// MARK: - What you're saving for
//
// The mirror image of `LoansSheet`, and stored the same way: by hand. There's
// no bank connection, so the app can't watch a savings balance climb — it holds
// the figure it was given, says plainly what's left, and asks for the rest
// rather than inferring it.
//
// Deliberately not derived from entries filed under Savings. With two goals
// running there's no way to know which transfer belonged to which, and a
// progress bar built on a guess is worse than one built on an answer.

struct GoalsSheet: View {
    @EnvironmentObject var model: AppModel

    @State private var editing: Goal?
    @State private var isAdding = false
    @State private var toppingUp: Goal?

    var body: some View {
        Page(title: "Saving for", subtitle: Fmt.count(model.goals.count, "goal"), displayMode: .inline) {
            VStack(alignment: .leading, spacing: Space.md) {
                if model.goals.isEmpty {
                    Text("An emergency fund, a deposit, a trip — put a number on "
                       + "it and you'll see how far along you are and what it "
                       + "takes each month to get there.")
                        .appFont(13)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                    totalCard
                    AdaptiveCards(spacing: Space.sm) {
                        ForEach(model.goals) { goal in
                            row(goal)
                        }
                    }
                }

                Text("Nothing here is read from a bank. What's put by is whatever "
                   + "you've told the app you've put by.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toolbar { AddItem(label: "Add a goal") { isAdding = true } }
        .sheet(item: $editing) { goal in GoalForm(goal: goal).environmentObject(model) }
        .sheet(isPresented: $isAdding) { GoalForm(goal: nil).environmentObject(model) }
        .sheet(item: $toppingUp) { goal in TopUpSheet(goal: goal).environmentObject(model) }
    }

    private var totalCard: some View {
        let target = model.totalGoalTarget
        let pct = target > 0 ? min(100, model.totalSaved / target * 100) : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Put by so far").appFont(12.5, weight: .medium)
                .foregroundStyle(Palette.sub)
            Text(Fmt.money(model.totalSaved)).mono(30)
            if target > 0 {
                ProgressBar(pct: pct, fill: Palette.tealGradient, height: 8)
                    .padding(.top, 4)
                // `Fmt.count` rather than the `^[…](inflect:)` markup: this
                // string is concatenated before it reaches `Text`, so it
                // arrives as a plain `String` and the markup would render
                // verbatim. See the note on `Fmt.count`.
                Text("of \(Fmt.money(target)) across \(Fmt.count(model.goals.count, "goal"))"
                   + (model.monthlyGoalContributions > 0
                      ? " · \(Fmt.money(model.monthlyGoalContributions)) a month" : ""))
                    .appFont(12).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The other half of the reconciliation. Home now names this figure
            // beside what's left to spend; this says what it is over here, so
            // the two screens agree instead of quietly contradicting each other.
            if model.hasGoalPromise {
                Text("A monthly figure is a plan, not a transfer. Nothing moves until you add it, so it isn't taken out of what Home says is left to spend.")
                    .appFont(11.5).foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .card()
    }

    /// One goal: name, where it stands, and the one action anybody actually
    /// comes here to do. Tapping the row edits it; the button beside it adds to
    /// it — a top-up shouldn't mean opening a form and retyping a total.
    private func row(_ goal: Goal) -> some View {
        let today = Date()
        let behind = goal.isBehind(on: today) || goal.isOverdue(on: today)
        return VStack(spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                IconTile(symbol: goal.isComplete ? "checkmark.seal.fill" : "target",
                         color: goal.isComplete ? Palette.green : Palette.teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).appFont(14, weight: .medium).lineLimit(1)
                    Text(goal.paceLabel(on: today))
                        .appFont(11.5)
                        .foregroundStyle(goal.isComplete ? Palette.green
                                         : (behind ? Palette.overText : Palette.sub))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.money(goal.saved)).mono(13)
                    Text("of \(Fmt.money(goal.target))")
                        .appFont(10.5).foregroundStyle(Palette.sub)
                }
            }

            ProgressBar(pct: goal.fraction * 100,
                        fill: goal.isComplete ? Palette.green : Palette.teal,
                        height: 7)

            HStack(spacing: 4) {
                if goal.isComplete {
                    Text("Done — \(Fmt.money(goal.saved)) saved")
                        .appFont(11.5, weight: .semibold)
                        .foregroundStyle(Palette.green)
                } else {
                    Text("\(Fmt.money(goal.remaining)) to go")
                        .appFont(11.5, weight: .semibold)
                        .foregroundStyle(Palette.sub)
                }

                Spacer(minLength: 4)

                Button { toppingUp = goal } label: {
                    Label("Add to this", systemImage: "plus")
                        .appFont(11, weight: .semibold)
                }
                .inlineActionStyle()
                .accessibilityHint("Records money you've put aside for \(goal.name)")
            }
        }
        .padding(Space.md)
        .card()
        .contentShape(Rectangle())
        .onTapGesture { editing = goal }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Top up

/// Recording another transfer. Its own small sheet rather than a field on the
/// edit form: adding to a goal is the frequent action and rewriting its target
/// is the rare one, and they shouldn't share a screen where a slip does the
/// wrong one.
struct TopUpSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var amount = ""
    @FocusState private var focused: Bool

    private var parsed: Double? { Fmt.amount(from: amount) }

    var body: some View {
        ModalPage(title: "Add to \(goal.name)",
                  subtitle: "\(Fmt.money(goal.saved)) put by so far",
                  detents: [.medium]) {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Amount").appFont(12, weight: .medium).foregroundStyle(Palette.sub)
                    HStack(spacing: 2) {
                        Text(Fmt.currencySymbol).mono(18, weight: .regular)
                            .foregroundStyle(Palette.muted)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .appFont(22, weight: .semibold)
                            .monospacedDigit()
                            .focused($focused)
                    }
                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                    .fieldBackground()
                }

                if let parsed {
                    let after = goal.saved + parsed
                    HStack(spacing: Space.sm) {
                        Image(systemName: after >= goal.target && goal.target > 0
                              ? "checkmark.seal.fill" : "arrow.up.right")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(after >= goal.target && goal.target > 0
                                             ? Palette.green : Palette.teal)
                        Text(after >= goal.target && goal.target > 0
                             ? "That finishes it — \(Fmt.money(after)) saved"
                             : "\(Fmt.money(after)) put by, \(Fmt.money(max(0, goal.target - after))) to go")
                            .appFont(13, weight: .medium)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(Space.md)
                    .card()
                }

                Text("This records what you've set aside. It doesn't move any "
                   + "money, and it isn't logged as spending.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toolbar {
                ConfirmItem(title: "Add", isEnabled: parsed != nil) {
                    guard let parsed else { return }
                    model.addToGoal(goal.id, amount: parsed)
                    dismiss()
                }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Form

struct GoalForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let goal: Goal?

    @State private var name = ""
    @State private var target = ""
    @State private var saved = ""
    @State private var monthly = ""
    @State private var hasDeadline = false
    @State private var deadline = GoalForm.defaultDeadline

    /// The furthest out a deadline can be set. Not a rule anybody will meet —
    /// it's here because an unbounded date runs the month arithmetic off the
    /// end of what a sensible label can say.
    private static let maxYearsOut = 50

    /// Where the picker opens for a goal that hasn't got a date yet.
    ///
    /// Not today, which is what an unset `Date()` would give: a deadline of
    /// today has no months in it, so the line underneath falls back to the
    /// open-ended answer and switching the toggle on appears to do nothing.
    /// Six months out is far enough to produce a real figure and near enough
    /// that nobody leaves it there by accident.
    static var defaultDeadline: Date {
        Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    }

    private var draft: (name: String, target: Double)? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let target = Fmt.amount(from: target) else { return nil }
        return (name, target)
    }

    var body: some View {
        ModalPage(title: goal == nil ? "New goal" : "Edit goal") {
            VStack(alignment: .leading, spacing: Space.md) {
                field("Name", text: $name, prompt: "e.g. Emergency fund")
                money("Target", text: $target)
                money("Put by already", text: $saved)
                money("Adding each month", text: $monthly)

                deadlineSection

                if let preview = previewGoal {
                    HStack(spacing: Space.sm) {
                        Image(systemName: previewSymbol(preview))
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(previewTint(preview))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.paceLabel(on: Date()))
                                .appFont(13, weight: .medium)
                                .fixedSize(horizontal: false, vertical: true)
                            if let shortfall = shortfallLine(preview) {
                                Text(shortfall)
                                    .appFont(11.5).foregroundStyle(Palette.sub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.md)
                    .card()
                }

                if let goal {
                    SecondaryButton(title: "Delete", color: Palette.over) {
                        model.deleteGoal(goal.id)
                        dismiss()
                    }
                }
            }
            .toolbar {
                ConfirmItem(title: goal == nil ? "Add" : "Save", isEnabled: draft != nil, action: save)
            }
        }
        .onAppear(perform: load)
    }

    /// A date is opt-in. Most saving doesn't have one, and a form that demands
    /// a deadline gets an invented deadline — which then drives every "you need
    /// $N a month" line underneath it.
    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $hasDeadline.appAnimation(.easeOut(duration: 0.18))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Want it by a date").appFont(13.5, weight: .medium)
                    Text(hasDeadline
                         ? "You'll see what has to go in each month."
                         : "Optional — leave it off if there's no rush.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hasDeadline {
                DatePicker("Deadline", selection: $deadline,
                           in: Date()...Self.latestDeadline,
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .appFont(13, weight: .medium)
            }
        }
        .padding(Space.md)
        .card()
    }

    private static var latestDeadline: Date {
        Calendar.current.date(byAdding: .year, value: maxYearsOut, to: Date()) ?? Date()
    }

    /// Live pace maths as the numbers are typed, so what a target and a date
    /// actually demand each month is visible before it's committed.
    private var previewGoal: Goal? {
        guard let draft else { return nil }
        return Goal(id: "preview", name: draft.name, target: draft.target,
                    saved: Fmt.amount(from: saved) ?? 0,
                    monthlyContribution: Fmt.amount(from: monthly) ?? 0,
                    deadline: deadlineToStore,
                    createdAt: Date())
    }

    /// The date to keep: what the picker shows, unless that's only today
    /// standing in for a deadline that has already passed.
    ///
    /// `load` shows a past deadline as today because the picker can't hold an
    /// earlier day — and saving then wrote today back, so renaming an overdue
    /// goal quietly moved its deadline and it stopped reading as overdue. The
    /// stored date changes only when a different day is actually picked.
    private var deadlineToStore: String {
        guard hasDeadline else { return "" }
        let picked = Fmt.isoDay(deadline)
        if let stored = goal?.deadline, !stored.isEmpty,
           stored < picked, picked == Fmt.isoDay(Date()) {
            return stored
        }
        return picked
    }

    private func previewSymbol(_ preview: Goal) -> String {
        if preview.isComplete { return "checkmark.seal.fill" }
        return preview.isBehind(on: Date()) ? "exclamationmark.triangle.fill" : "target"
    }

    private func previewTint(_ preview: Goal) -> Color {
        if preview.isComplete { return Palette.green }
        return preview.isBehind(on: Date()) ? Palette.over : Palette.teal
    }

    /// Says the gap out loud when what's going in each month won't reach the
    /// date. Stating both figures is the point — "you're behind" without the
    /// number is just a mood.
    private func shortfallLine(_ preview: Goal) -> String? {
        guard !preview.isComplete,
              preview.monthlyContribution > 0,
              let needed = preview.requiredMonthly(from: Date()),
              needed > preview.monthlyContribution
        else { return nil }
        return "\(Fmt.money(preview.monthlyContribution)) a month is "
             + "\(Fmt.money(needed - preview.monthlyContribution)) short of that."
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            TextField("", text: text,
                      prompt: Text(prompt).foregroundStyle(Palette.muted))
                .textFieldStyle(.plain)
                .appFont(15)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()
        }
        .accessibilityElement(children: .contain)
    }

    private func money(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            HStack(spacing: 2) {
                Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .appFont(15, weight: .medium)
                    .monospacedDigit()
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .fieldBackground()
        }
        .accessibilityElement(children: .contain)
    }

    private func load() {
        guard let goal else { return }
        name = goal.name
        target = Fmt.plain(goal.target)
        saved = goal.saved > 0 ? Fmt.plain(goal.saved) : ""
        monthly = goal.monthlyContribution > 0 ? Fmt.plain(goal.monthlyContribution) : ""
        hasDeadline = goal.hasDeadline
        // A deadline already in the past would fall outside the picker's range
        // and snap silently to today, quietly rewriting what the user set. Show
        // today in the field but leave the stored date alone until they commit.
        if let due = Fmt.day(from: goal.deadline) { deadline = max(due, Date()) }
    }

    private func save() {
        guard let draft else { return }
        model.saveGoal(Goal(
            id: goal?.id ?? UUID().uuidString,
            name: draft.name,
            target: draft.target,
            saved: Fmt.amount(from: saved) ?? 0,
            monthlyContribution: Fmt.amount(from: monthly) ?? 0,
            deadline: deadlineToStore,
            createdAt: goal?.createdAt ?? Date()
        ))
        dismiss()
    }
}

#Preview {
    PreviewShell { GoalsSheet() }
}

#Preview("Goals — light") {
    PreviewShell(scheme: .light) { GoalsSheet() }
}
