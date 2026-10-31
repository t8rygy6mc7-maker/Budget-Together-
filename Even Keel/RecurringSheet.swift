import SwiftUI

// MARK: - Recurring bills and paydays
//
// Things that repeat every month. Each one posts its own entry on its day and
// reminds a couple of days ahead, so rent stops being something to remember.

struct RecurringSheet: View {
    @EnvironmentObject var model: AppModel

    @State private var editing: Recurring?
    @State private var isAdding = false

    var body: some View {
        Page(title: "Repeating",
             subtitle: Fmt.count(model.recurring.count, "item"), displayMode: .inline) {
            VStack(alignment: .leading, spacing: Space.md) {
                if model.recurring.isEmpty {
                    Text("Nothing repeating yet. Add rent, a subscription or a payday and it'll log itself each month.")
                        .appFont(13)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                    RowGroup(footer: "Each item posts on its day and reminds you two days before.") {
                        ForEach(model.recurring) { item in
                            Button { editing = item } label: { row(item) }
                                .buttonStyle(.row)
                        }
                    }
                }
            }
        }
        .toolbar { AddItem(label: "Add a repeating item") { isAdding = true } }
        .sheet(item: $editing) { item in
            RecurringForm(item: item).environmentObject(model)
        }
        .sheet(isPresented: $isAdding) {
            RecurringForm(item: nil).environmentObject(model)
        }
    }

    private func row(_ item: Recurring) -> some View {
        let bucket = Bucket.named(item.bucket)
        return RowLabel(symbol: bucket.symbol, color: bucket.color, fill: bucket.tint,
                        title: Text(item.place), subtitle: Text(item.scheduleLabel)) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.kind.sign + Fmt.money(item.amount))
                    .mono(13).foregroundStyle(item.kind.color)
                if !item.isActive {
                    Text("Paused")
                        .appFont(10, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .opacity(item.isActive ? 1 : 0.55)
    }
}

// MARK: - Form

/// Add or edit one repeating item. `item` is `nil` when adding.
struct RecurringForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: Recurring?

    @State private var place = ""
    @State private var amount = ""
    @State private var kind: EntryKind = .expense
    @State private var bucket = Bucket.fallback.id
    @State private var memberID = ""
    @State private var day = 1
    @State private var isActive = true

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var draft: (place: String, amount: Double)? {
        let place = place.trimmingCharacters(in: .whitespaces)
        guard !place.isEmpty, !memberID.isEmpty,
              let amount = Fmt.amount(from: amount) else { return nil }
        return (place, amount)
    }

    var body: some View {
        ModalPage(title: item == nil ? "New repeating item" : "Edit repeating item") {
            VStack(alignment: .leading, spacing: Space.md) {
                Picker("Kind", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { candidate in
                        Text(candidate == .income ? "Money in" : "Bill").tag(candidate)
                    }
                }
                .pickerStyle(.segmented)

                TextField("", text: $place,
                          prompt: Text(kind == .income ? "e.g. Payroll" : "e.g. Rent")
                            .foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .appFont(15)
                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                    .fieldBackground()
                    .accessibilityLabel("Name")

                HStack(spacing: 2) {
                    Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .appFont(15, weight: .medium)
                        .monospacedDigit()
                        .accessibilityLabel("Amount")
                }
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

                RowGroup {
                    GroupedRow {
                        // Capped at 28 so the day exists in every month, February included.
                        Stepper(value: $day, in: 1...Recurring.maxDay) {
                            HStack {
                                Text("Day of month").appFont(14)
                                Spacer()
                                Text("\(day)").mono(14)
                            }
                        }
                    }
                    GroupedRow {
                        Toggle(isOn: $isActive) { Text("Active").appFont(14) }
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Paid by").appFont(12, weight: .medium)
                        .foregroundStyle(Palette.sub)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.xs)],
                              spacing: Space.xs) {
                        ForEach(model.members) { member in
                            let isSelected = memberID == member.id
                            Button { memberID = member.id } label: {
                                HStack(spacing: 7) {
                                    MemberAvatar(member: member, size: 18)
                                    Text(member.name)
                                        .appFont(13, weight: .medium).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(Space.xs)
                                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                                .fieldBackground(isSelected ? AnyShapeStyle(member.color.opacity(0.14))
                                                            : AnyShapeStyle(Palette.card),
                                                 border: isSelected ? member.color : nil)
                            }
                            .accessibilityLabel(member.name)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Category").appFont(12, weight: .medium)
                        .foregroundStyle(Palette.sub)
                    LazyVGrid(columns: Self.columns, spacing: Space.xs) {
                        ForEach(Bucket.list(for: kind, including: item?.bucket)) { candidate in
                            let isSelected = bucket == candidate.id
                            Button { bucket = candidate.id } label: {
                                VStack(spacing: 5) {
                                    IconTile(symbol: candidate.symbol, color: candidate.color,
                                             fill: candidate.color.opacity(0.18))
                                    Text(candidate.short).appFont(10.5, weight: .medium)
                                }
                                .frame(maxWidth: .infinity).padding(Space.xs)
                                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                                .fieldBackground(isSelected ? AnyShapeStyle(candidate.tint)
                                                            : AnyShapeStyle(Palette.card),
                                                 border: isSelected ? candidate.color : nil)
                            }
                            .accessibilityLabel(candidate.label)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                if let item {
                    SecondaryButton(title: "Delete", color: Palette.over) {
                        model.deleteRecurring(item.id)
                        dismiss()
                    }
                }
            }
            .toolbar {
                ConfirmItem(title: item == nil ? "Add" : "Save", isEnabled: draft != nil, action: save)
            }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, new in
            if !Bucket.list(for: new, including: item?.bucket).contains(where: { $0.id == bucket }) {
                bucket = Bucket.fallback(for: new).id
            }
        }
    }

    private func load() {
        guard let item else {
            memberID = model.defaultMemberID ?? ""
            return
        }
        place = item.place
        amount = Fmt.plain(item.amount)
        kind = item.kind
        bucket = item.bucket
        memberID = item.memberID
        day = item.dayOfMonth
        isActive = item.isActive
    }

    private func save() {
        guard let draft else { return }
        model.saveRecurring(Recurring(
            id: item?.id ?? UUID().uuidString,
            place: draft.place,
            amount: draft.amount,
            bucket: bucket,
            memberID: memberID,
            kind: kind,
            dayOfMonth: day,
            isActive: isActive,
            // Editing shouldn't re-post something this month that already posted.
            lastPostedMonth: item?.lastPostedMonth ?? ""
        ))
        dismiss()
    }
}

#Preview {
    PreviewShell { RecurringSheet() }
}
