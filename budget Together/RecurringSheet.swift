import SwiftUI

// MARK: - Recurring bills and paydays
//
// Things that repeat every month. Each one posts its own entry on its day and
// reminds a couple of days ahead, so rent stops being something to remember.

struct RecurringSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Recurring?
    @State private var isAdding = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if model.recurring.isEmpty {
                    Text("Nothing repeating yet. Add rent, a subscription or a payday and it'll log itself each month.")
                        .appFont(13)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 22)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.recurring) { item in
                            Button { editing = item } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                Button { isAdding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").appFont(15, weight: .bold)
                        Text("Add a repeating item").appFont(15, weight: .bold)
                    }
                    .frame(maxWidth: .infinity).padding(15)
                    .foregroundStyle(Palette.tealInk)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .padding(.top, 16)

                Text("Each item posts on its day and reminds you two days before.")
                    .appFont(12)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .sheet(item: $editing) { item in
            RecurringForm(item: item).environmentObject(model)
        }
        .sheet(isPresented: $isAdding) {
            RecurringForm(item: nil).environmentObject(model)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repeating").appFont(17, weight: .bold)
                Text("^[\(model.recurring.count) item](inflect: true)")
                    .appFont(12.5, weight: .medium)
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 16)
    }

    private func row(_ item: Recurring) -> some View {
        let bucket = Bucket.named(item.bucket)
        return HStack(spacing: 12) {
            Image(systemName: bucket.symbol)
                .appFont(15, weight: .semibold)
                .foregroundStyle(bucket.color)
                .frame(width: 34, height: 34)
                .background(bucket.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.place).appFont(14, weight: .semibold).lineLimit(1)
                Text(item.scheduleLabel)
                    .appFont(11.5).foregroundStyle(Palette.sub)
            }

            Spacer(minLength: 4)

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
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(item == nil ? "New repeating item" : "Edit repeating item")
                        .appFont(17, weight: .bold)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .appFont(14, weight: .semibold)
                            .foregroundStyle(Palette.label9)
                            .frame(width: 30, height: 30)
                            .background(Palette.chip, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.top, 6)

                HStack(spacing: 8) {
                    ForEach(EntryKind.allCases, id: \.self) { candidate in
                        let isSelected = kind == candidate
                        Button { kind = candidate } label: {
                            Text(candidate == .income ? "Money in" : "Bill")
                                .appFont(13, weight: .semibold)
                                .frame(maxWidth: .infinity).padding(9)
                                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                                .fieldBackground(isSelected ? AnyShapeStyle(Palette.teal.opacity(0.14))
                                                            : AnyShapeStyle(Palette.card),
                                                 border: isSelected ? Palette.teal : Palette.cardBorder,
                                                 radius: 14)
                        }
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }

                TextField("", text: $place,
                          prompt: Text(kind == .income ? "e.g. Payroll" : "e.g. Rent")
                            .foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .appFont(15, weight: .medium)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .fieldBackground(radius: 13)
                    .accessibilityLabel("Name")

                HStack(spacing: 2) {
                    Text(Fmt.currencySymbol).mono(14, weight: .regular).foregroundStyle(Palette.muted)
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .appFont(15, weight: .bold, design: .monospaced)
                        .accessibilityLabel("Amount")
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)

                // Capped at 28 so the day exists in every month, February included.
                Stepper(value: $day, in: 1...Recurring.maxDay) {
                    HStack {
                        Text("Day of month").appFont(14, weight: .medium)
                        Spacer()
                        Text("\(day)").mono(14)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .fieldBackground(radius: 13)

                Toggle(isOn: $isActive) {
                    Text("Active").appFont(14, weight: .medium)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .fieldBackground(radius: 13)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Paid by").appFont(12, weight: .semibold)
                        .foregroundStyle(Palette.sub)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(model.members) { member in
                            let isSelected = memberID == member.id
                            Button { memberID = member.id } label: {
                                HStack(spacing: 7) {
                                    MemberAvatar(member: member, size: 18)
                                    Text(member.name)
                                        .appFont(13, weight: .semibold).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(9)
                                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                                .fieldBackground(isSelected ? AnyShapeStyle(member.color.opacity(0.14))
                                                            : AnyShapeStyle(Palette.card),
                                                 border: isSelected ? member.color : Palette.cardBorder,
                                                 radius: 14)
                            }
                            .accessibilityLabel(member.name)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Category").appFont(12, weight: .semibold)
                        .foregroundStyle(Palette.sub)
                    LazyVGrid(columns: Self.columns, spacing: 8) {
                        ForEach(Bucket.list(for: kind, including: item?.bucket)) { candidate in
                            let isSelected = bucket == candidate.id
                            Button { bucket = candidate.id } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: candidate.symbol)
                                        .appFont(15, weight: .semibold)
                                        .foregroundStyle(candidate.color)
                                        .frame(width: 30, height: 30)
                                        .background(candidate.color.opacity(0.18),
                                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    Text(candidate.short).appFont(10.5, weight: .semibold)
                                }
                                .frame(maxWidth: .infinity).padding(9)
                                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                                .fieldBackground(isSelected ? AnyShapeStyle(candidate.tint)
                                                            : AnyShapeStyle(Palette.card),
                                                 border: isSelected ? candidate.color : Palette.cardBorder,
                                                 radius: 14)
                            }
                            .accessibilityLabel(candidate.label)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                let canSave = draft != nil
                Button(action: save) {
                    Text(item == nil ? "Add" : "Save changes")
                        .appFont(15, weight: .bold)
                        .frame(maxWidth: .infinity).padding(15)
                        .foregroundStyle(canSave ? Palette.tealInk : Palette.muted)
                        .background {
                            if canSave { Palette.tealGradient } else { Palette.chip }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .disabled(!canSave)

                if let item {
                    Button {
                        model.deleteRecurring(item.id)
                        dismiss()
                    } label: {
                        Text("Delete")
                            .appFont(14, weight: .semibold)
                            .foregroundStyle(Palette.over)
                            .frame(maxWidth: .infinity).padding(13)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
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
    RecurringSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
