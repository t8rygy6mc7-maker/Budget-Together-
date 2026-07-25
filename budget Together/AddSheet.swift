import SwiftUI

struct AddSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var place = ""
    /// Resolved in `onAppear` once the household's members are known.
    @State private var memberID = ""
    @State private var bucket = Bucket.fallback.id
    @State private var showPeople = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    /// People wrap across as many rows as they need — a household can be big.
    private static let peopleColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    /// The entry that would be saved, or `nil` while the form is incomplete.
    private var draft: (place: String, amount: Double, memberID: String)? {
        let place = place.trimmingCharacters(in: .whitespaces)
        guard !place.isEmpty, !memberID.isEmpty,
              let amount = Fmt.amount(from: amount) else { return nil }
        return (place, amount, memberID)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                amountField
                placeField
                personPicker
                categoryPicker
                saveButton
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .sheet(isPresented: $showPeople) { PeopleSheet().environmentObject(model) }
        .onAppear(perform: selectDefaultMember)
        // Someone added from the people sheet should be selectable right away;
        // if the selected person was removed, fall back rather than lose the draft.
        .onChange(of: model.members) { _, _ in
            if !model.members.contains(where: { $0.id == memberID }) { selectDefaultMember() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Add a spend").font(.system(size: 17, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .background(Palette.chip, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 6).padding(.bottom, 16)
    }

    private var amountField: some View {
        HStack(spacing: 2) {
            Text("$").mono(14, weight: .regular).foregroundStyle(Palette.muted)
            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .frame(maxWidth: 220)
                .accessibilityLabel("Amount")
        }
        .padding(.bottom, 6)
    }

    private var placeField: some View {
        TextField("", text: $place,
                  prompt: Text("Where'd it go? (e.g. Trader Joe's)").foregroundStyle(Palette.muted))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 13)
            .fieldBackground(radius: 13)
            .accessibilityLabel("Where")
            .padding(.bottom, 12)
    }

    private var personPicker: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Who spent it").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.sub)
                Spacer()
            }
            LazyVGrid(columns: Self.peopleColumns, spacing: 8) {
                ForEach(model.members) { personChip($0) }
                addPersonChip
            }
        }
        .padding(.bottom, 14)
    }

    private var categoryPicker: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Category").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.sub)
                Spacer()
            }
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Bucket.all) { categoryChip($0) }
            }
        }
    }

    private var saveButton: some View {
        let canSave = draft != nil
        return Button(action: save) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                Text("Add to log").font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity).padding(15)
            .foregroundStyle(canSave ? Palette.tealInk : Palette.muted)
            .background {
                if canSave { Palette.tealGradient } else { Palette.chip }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .disabled(!canSave)
        .padding(.top, 18)
    }

    // MARK: - Chips

    private func personChip(_ candidate: Member) -> some View {
        let isSelected = memberID == candidate.id
        return Button { memberID = candidate.id } label: {
            HStack(spacing: 7) {
                MemberAvatar(member: candidate, size: 18)
                Text(candidate.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(9)
            .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
            .fieldBackground(isSelected ? AnyShapeStyle(candidate.color.opacity(0.14))
                                        : AnyShapeStyle(Palette.card),
                             border: isSelected ? candidate.color : Palette.cardBorder,
                             radius: 14)
        }
        .accessibilityLabel(candidate.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addPersonChip: some View {
        Button { showPeople = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Palette.chipText)
                    .frame(width: 18, height: 18)
                    .background(Palette.chip, in: Circle())
                Text("Add").font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(9)
            .foregroundStyle(Palette.chipText)
            .fieldBackground(AnyShapeStyle(Palette.card),
                             border: Palette.cardBorder, radius: 14)
        }
        .accessibilityLabel("Add someone")
    }

    private func categoryChip(_ candidate: Bucket) -> some View {
        let isSelected = bucket == candidate.id
        return Button { bucket = candidate.id } label: {
            VStack(spacing: 5) {
                Image(systemName: candidate.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(candidate.color)
                    .frame(width: 30, height: 30)
                    .background(candidate.color.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(candidate.short).font(.system(size: 10.5, weight: .semibold))
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

    // MARK: - Actions

    private func selectDefaultMember() {
        memberID = model.defaultMemberID ?? ""
    }

    private func save() {
        guard let draft else { return }
        model.addEntry(place: draft.place, amount: draft.amount,
                       bucket: bucket, memberID: draft.memberID)
        dismiss()
    }
}

#Preview {
    AddSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
