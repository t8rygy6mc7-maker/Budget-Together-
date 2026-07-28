import SwiftUI

// MARK: - Categories
//
// The eight spending categories and five income ones used to be a hardcoded
// array. They're now the household's own list: renameable, recolourable,
// reorderable, and extendable with as many of their own as they like.
//
// Two rules shape the whole screen:
//
// **An id is forever.** Every entry, limit, recurring item and challenge points
// at a category by id, so editing changes how one renders and never what any of
// them refer to. Renaming "Fun & Misc" to "Going out" reclassifies nothing.
//
// **Hiding beats deleting.** A category with history behind it can't be removed
// without leaving holes in months that have already happened, so it's hidden
// instead: gone from every picker, still resolving everywhere it was used.
// Deletion is offered only for a category nothing points at.

struct CategoriesSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: EntryKind = .expense
    @State private var editing: Bucket?
    @State private var pendingDeletion: Bucket?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.categories(for: kind)) { row($0) }
                        .onMove { model.moveCategories(for: kind, from: $0, to: $1) }
                } header: {
                    Text(kind == .income ? "Income sources" : "Spending categories")
                } footer: {
                    Text("Drag to reorder — this is the order they appear in when "
                       + "you log something. Renaming or recolouring one leaves "
                       + "every entry already filed under it exactly where it is.")
                }

                hiddenSection
                addSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.sheetBg)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { directionPicker }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Palette.sheetBg)
        .tint(Palette.teal)
        .sheet(item: $editing) { bucket in
            CategoryEditor(bucket: bucket).environmentObject(model)
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \($0.label)?" } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            if let bucket = pendingDeletion {
                Button("Delete", role: .destructive) { model.deleteCategory(bucket.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is filed under it, so nothing will be lost.")
        }
    }

    // MARK: Sections

    private var directionPicker: some View {
        Picker("", selection: $kind) {
            Text("Spending").tag(EntryKind.expense)
            Text("Income").tag(EntryKind.income)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    @ViewBuilder
    private var hiddenSection: some View {
        let hidden = model.hiddenCategories(for: kind)
        if !hidden.isEmpty {
            Section {
                ForEach(hidden) { row($0) }
            } header: {
                Text("Hidden")
            } footer: {
                Text("Not offered when logging, but everything filed under them "
                   + "is untouched and still counts in past months.")
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                editing = model.draftCategory(for: kind)
            } label: {
                Label(kind == .income ? "Add an income source" : "Add a category",
                      systemImage: "plus.circle.fill")
                    .foregroundStyle(Palette.teal)
            }
        }
    }

    // MARK: Row

    private func row(_ bucket: Bucket) -> some View {
        HStack(spacing: 12) {
            Image(systemName: bucket.symbol)
                .appFont(15, weight: .semibold)
                .foregroundStyle(bucket.color)
                .frame(width: 34, height: 34)
                .background(bucket.tint,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.label)
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(bucket.isHidden ? Palette.sub : Palette.text)
                Text(subtitle(for: bucket))
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button { editing = bucket } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if model.canHideCategory(bucket.id) {
                    Button { model.setCategoryHidden(!bucket.isHidden, id: bucket.id) } label: {
                        Label(bucket.isHidden ? "Show again" : "Hide",
                              systemImage: bucket.isHidden ? "eye" : "eye.slash")
                    }
                }
                if bucket.isBuiltIn, Bucket.builtIn(bucket.id) != nil {
                    Button { model.resetCategory(bucket.id) } label: {
                        Label("Reset to default", systemImage: "arrow.uturn.backward")
                    }
                }
                if model.canDeleteCategory(bucket.id) {
                    Button(role: .destructive) { pendingDeletion = bucket } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(bucket.label)")
        }
        .padding(.vertical, 3)
        .listRowBackground(Palette.card)
        .contentShape(Rectangle())
        .onTapGesture { editing = bucket }
    }

    /// Says what the category is for and what's riding on it, so the
    /// consequences of hiding or deleting are visible before the menu opens.
    private func subtitle(for bucket: Bucket) -> String {
        var parts: [String] = []
        if bucket.kind == .expense { parts.append(bucket.cadence.label) }
        let usage = model.categoryUsage(bucket.id)
        if usage.entries > 0 {
            parts.append(Fmt.count(usage.entries, "entry", plural: "entries"))
        } else if !bucket.isBuiltIn {
            parts.append("Nothing filed here yet")
        }
        if bucket.isHidden { parts.append("Hidden") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Editor

/// Add or edit one category. Deliberately a small form: a name, a glyph, a
/// colour, and — for spending — whether it's a fixed bill or varies, which is
/// the one field with arithmetic behind it.
struct CategoryEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let bucket: Bucket

    @State private var label = ""
    @State private var symbol = "tag.fill"
    @State private var colorHex = ""
    @State private var cadence: Cadence = .variable
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { !model.categories.contains { $0.id == bucket.id } }
    private var chosen: CategoryColor { CategoryColor.named(colorHex) }
    private var canSave: Bool { !label.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    nameField
                    colorPicker
                    symbolPicker
                    if bucket.kind == .expense { cadencePicker }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .background(Palette.sheetBg)
            .navigationTitle(isNew ? "New category" : bucket.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .onAppear {
            label = bucket.label
            symbol = bucket.symbol
            colorHex = bucket.hex
            cadence = bucket.cadence
            if isNew { nameFocused = true }
        }
    }

    // MARK: Sections

    /// What it'll look like in the places it actually appears, updating live.
    /// Cheaper than making someone save and go and look.
    private var preview: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .appFont(17, weight: .semibold)
                .foregroundStyle(chosen.color)
                .frame(width: 42, height: 42)
                .background(chosen.color.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(label.isEmpty ? "Your category" : label)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(label.isEmpty ? Palette.muted : Palette.text)
                ProgressBar(pct: 62, fill: chosen.color, height: 7)
                    .frame(maxWidth: 160)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Palette.cardBorderSoft, radius: 16)
        .accessibilityHidden(true)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Name").appFont(12, weight: .semibold).foregroundStyle(Palette.sub)
            TextField("", text: $label,
                      prompt: Text(bucket.kind == .income ? "e.g. Freelance"
                                                          : "e.g. Childcare")
                        .foregroundStyle(Palette.muted))
                .focused($nameFocused)
                .textFieldStyle(.plain)
                .appFont(15, weight: .medium)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)
                .accessibilityLabel("Category name")
        }
    }

    /// A closed set, not a colour well — see `CategoryStyle.swift` for why.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Colour").appFont(12, weight: .semibold).foregroundStyle(Palette.sub)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                ForEach(CategoryColor.all) { option in
                    let isSelected = option.hex.caseInsensitiveCompare(colorHex) == .orderedSame
                    Button {
                        Haptics.selected()
                        colorHex = option.hex
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(height: 38)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .appFont(14, weight: .bold)
                                        .foregroundStyle(Palette.screen)
                                }
                            }
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? Palette.text : .clear, lineWidth: 2)
                                    .padding(-3)
                            }
                    }
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text("Every one of these is checked for readability in both light and "
               + "dark, which is why it's a set rather than a free choice.")
                .appFont(11)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon").appFont(12, weight: .semibold).foregroundStyle(Palette.sub)
            ForEach(SymbolGroup.all) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text(group.name)
                        .appFont(11, weight: .medium)
                        .foregroundStyle(Palette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)],
                              spacing: 8) {
                        ForEach(group.symbols, id: \.self) { candidate in
                            let isSelected = symbol == candidate
                            Button {
                                Haptics.selected()
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .appFont(15, weight: .semibold)
                                    .foregroundStyle(isSelected ? chosen.color : Palette.chipText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .fieldBackground(
                                        isSelected ? AnyShapeStyle(chosen.color.opacity(0.16))
                                                   : AnyShapeStyle(Palette.card),
                                        border: isSelected ? chosen.color : Palette.cardBorder,
                                        radius: 11)
                            }
                            .accessibilityLabel(candidate)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    /// The one field that changes arithmetic rather than appearance: fixed
    /// categories are treated as already handled by the simplified view and by
    /// the "obligations" figure, rather than as money still to be decided about.
    private var cadencePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("How it behaves").appFont(12, weight: .semibold)
                .foregroundStyle(Palette.sub)
            ForEach(Cadence.allCases) { option in
                let isSelected = cadence == option
                Button {
                    Haptics.selected()
                    cadence = option
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: option.symbol)
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(isSelected ? Palette.teal : Palette.muted)
                            .frame(width: 28, height: 28)
                            .background(isSelected ? Palette.teal.opacity(0.16) : Palette.chip,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).appFont(13.5, weight: .semibold)
                            Text(option.detail)
                                .appFont(11.5).foregroundStyle(Palette.sub)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
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

    private func save() {
        let option = CategoryColor.named(colorHex)
        model.saveCategory(Bucket(
            id: bucket.id,
            label: label,
            hex: option.hex,
            light: option.light,
            symbol: symbol,
            cadence: bucket.kind == .income ? .variable : cadence,
            kind: bucket.kind,
            isHidden: bucket.isHidden,
            isBuiltIn: bucket.isBuiltIn,
            sortOrder: bucket.sortOrder
        ))
        dismiss()
    }
}

#Preview {
    CategoriesSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
