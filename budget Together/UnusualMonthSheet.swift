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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if model.isSelectedMonthUnusual {
                    marked
                } else {
                    picker
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
        .onAppear { reason = model.selectedMonthReason }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("About \(model.monthTitle)").appFont(17, weight: .bold)
                Text("Everything stays in your log and your totals. It just stops "
                   + "counting toward streaks and averages.")
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

    /// Already flagged: show what it says and offer to take it back.
    private var marked: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marked as unusual").appFont(14, weight: .semibold)
                    if !model.selectedMonthReason.isEmpty {
                        Text(model.selectedMonthReason)
                            .appFont(12).foregroundStyle(Palette.sub)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(border: Palette.cardBorderSoft, radius: 15)

            Button {
                model.markMonthUnusual(false)
                dismiss()
            } label: {
                Text("Count it normally again")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.chipText)
                    .frame(maxWidth: .infinity).padding(13)
                    .fieldBackground(radius: 14)
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
                                             border: isSelected ? Palette.teal : Palette.cardBorder,
                                             radius: 13)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            TextField("", text: $reason,
                      prompt: Text("Or say it in your own words").foregroundStyle(Palette.muted))
                .focused($reasonFocused)
                .textFieldStyle(.plain)
                .appFont(14)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)
                .padding(.top, 4)
                .accessibilityLabel("Reason")

            Button {
                model.markMonthUnusual(true, reason: reason.trimmingCharacters(in: .whitespaces))
                dismiss()
            } label: {
                Text("Don't count this month")
                    .appFont(15, weight: .bold)
                    .frame(maxWidth: .infinity).padding(15)
                    .foregroundStyle(Palette.tealInk)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(.top, 10)

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
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.teal)
                    .frame(width: 34, height: 34)
                    .background(Palette.teal.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to set some limits?")
                        .appFont(14, weight: .semibold)
                    Text("Based on what you've actually been spending — about \(Fmt.money(total)) a month.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if expanded {
                VStack(spacing: 7) {
                    ForEach(Bucket.all.filter { plan[$0.id] != nil }) { bucket in
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
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(Palette.field,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    model.applyPlan(plan)
                } label: {
                    Text("Use these")
                        .appFont(13.5, weight: .bold)
                        .foregroundStyle(Palette.tealInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Palette.tealGradient,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Hide" : "Show me")
                        .appFont(13.5, weight: .semibold)
                        .foregroundStyle(Palette.chipText)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .fieldBackground(radius: 13)
                }
            }

            Text("Nothing's locked in — every one of them is a tap away from changing.")
                .appFont(11)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .card(border: Palette.cardBorderSoft, radius: 16)
    }
}

#Preview {
    UnusualMonthSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
