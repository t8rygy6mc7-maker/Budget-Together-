import SwiftUI

// MARK: - Unusual month

/// Marks a month as unrepresentative. The month keeps its entries and its
/// totals — it happened, and hiding it would be a different and worse feature —
/// but it stops counting toward streaks, badges and the month-over-month
/// comparison.
///
/// The reason for this is arithmetic before it's kindness: one month with a
/// deposit and a moving van in it sits in the trailing average for the next six,
/// and the app spends that whole stretch reporting a decline that never
/// happened. Letting the user say "that one was strange" is the cheapest way to
/// keep every later comparison honest.
struct UnusualMonthSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @FocusState private var reasonFocused: Bool

    /// Common enough to be worth a tap rather than a sentence.
    private static let presets = [
        "Moved house", "Wedding", "Holiday", "Medical bills",
        "New baby", "Car trouble", "One-off big purchase",
    ]

    var body: some View {
        ModalPage(title: "About \(model.monthTitle)", detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Everything stays in your log and your totals. It just stops "
                   + "counting toward streaks and averages.")
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isSelectedMonthUnusual {
                    marked
                } else {
                    picker
                }
            }
        }
        .onAppear { reason = model.selectedMonthReason }
    }

    /// Already flagged: show what it says and offer to take it back.
    private var marked: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marked as unusual").appFont(14, weight: .medium)
                    if !model.selectedMonthReason.isEmpty {
                        Text(model.selectedMonthReason)
                            .appFont(12).foregroundStyle(Palette.sub)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            SecondaryButton(title: "Count it normally again") {
                model.markMonthUnusual(false)
                dismiss()
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("What happened?")
                .appFont(12, weight: .semibold)
                .foregroundStyle(Palette.sub)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(Self.presets, id: \.self) { preset in
                    let isSelected = reason == preset
                    Button {
                        Haptics.selected()
                        reason = isSelected ? "" : preset
                        reasonFocused = false
                    } label: {
                        Text(preset)
                            .appFont(12.5, weight: .semibold)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                            .fieldBackground(isSelected ? AnyShapeStyle(Palette.teal.opacity(0.14))
                                                        : AnyShapeStyle(Palette.card),
                                             border: isSelected ? Palette.teal : nil)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            TextField("", text: $reason,
                      prompt: Text("Or say it in your own words").foregroundStyle(Palette.muted))
                .focused($reasonFocused)
                .textFieldStyle(.plain)
                .appFont(14)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()
                .padding(.top, Space.xxs)
                .accessibilityLabel("Reason")

            PrimaryButton(title: "Don't count this month") {
                model.markMonthUnusual(true, reason: reason.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .padding(.top, Space.xs)

            Text("You can undo this any time — nothing is deleted either way.")
                .appFont(11.5)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Suggested plan

/// Offers limits worked out from what the household has actually spent, once
/// there's enough history to mean something.
///
/// This is the other half of dropping the budget question from onboarding: the
/// app stopped asking for a number on day one, so it has to earn one later —
/// and a figure derived from your own last few weeks is both easier to accept
/// and more likely to be right than one invented on a welcome screen.
struct SuggestedPlanCard: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded = false

    var body: some View {
        let plan = model.suggestedPlan()
        let total = plan.values.reduce(0, +)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Space.sm) {
                IconTile(symbol: "wand.and.stars", color: Palette.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to set some limits?")
                        .appFont(14, weight: .medium)
                    Text("Based on what you've actually been spending — about \(Fmt.money(total)) a month.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if expanded {
                VStack(spacing: 7) {
                    ForEach(model.expenseCategories.filter { plan[$0.id] != nil }) { bucket in
                        HStack(spacing: 9) {
                            Image(systemName: bucket.symbol)
                                .appFont(11, weight: .semibold)
                                .foregroundStyle(bucket.color)
                            Text(bucket.label).appFont(12.5)
                            Spacer(minLength: 4)
                            Text(Fmt.money(plan[bucket.id] ?? 0)).mono(12.5)
                        }
                    }
                }
                .padding(Space.sm)
                .fieldBackground()
            }

            HStack(spacing: Space.xs) {
                PrimaryButton(title: "Use these") { model.applyPlan(plan) }
                SecondaryButton(title: expanded ? "Hide" : "Show me") {
                    withAppAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
            }

            Text("Nothing's locked in — every one of them is a tap away from changing.")
                .appFont(11)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.md)
        .card()
    }
}

#Preview {
    UnusualMonthSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
