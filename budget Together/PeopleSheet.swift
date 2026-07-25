import SwiftUI

// MARK: - People
//
// Managing everyone on the budget. Reached from the avatar stack on Home and
// from the "Add someone" chip in the add sheet.

struct PeopleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var pendingRemoval: Member?
    @FocusState private var newNameFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                VStack(spacing: 8) {
                    ForEach(model.members) { PersonRow(member: $0, remove: { pendingRemoval = $0 }) }
                }

                addField

                Text("Everyone here can be picked when logging a spend. Tap an avatar to change its colour.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                appearanceSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .confirmationDialog(
            pendingRemoval.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil },
                                 set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            if let member = pendingRemoval {
                Button("Remove", role: .destructive) { model.removeMember(member.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let member = pendingRemoval {
                let count = model.entryCount(for: member.id)
                Text(count == 0
                     ? "They haven't logged anything yet."
                     : "^[\(count) entry](inflect: true) they logged will be deleted too.")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("People").font(.system(size: 17, weight: .bold))
                Text("^[\(model.members.count) person](inflect: true) on this budget")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.sub)
            }
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

    /// Appearance lives here rather than behind a settings screen the app
    /// doesn't have — People is already the "this device, these humans" sheet.
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.label9)

            HStack(spacing: 6) {
                ForEach(Appearance.allCases) { option in
                    appearanceOption(option)
                }
            }

            Text("Only on this phone — it won't change your partner's.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.sub)
        }
        .padding(.top, 22)
    }

    private func appearanceOption(_ option: Appearance) -> some View {
        let isSelected = model.appearance == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.appearance = option }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: option.symbol).font(.system(size: 15, weight: .semibold))
                Text(option.label).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Palette.tealInk : Palette.chipText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    Palette.tealGradient
                } else {
                    Palette.chip
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var addField: some View {
        HStack(spacing: 9) {
            TextField("", text: $newName,
                      prompt: Text("Add someone — their name").foregroundStyle(Palette.muted))
                .focused($newNameFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)

            let canAdd = !newName.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canAdd ? Palette.tealInk : Palette.muted)
                    .frame(width: 46, height: 46)
                    .background {
                        if canAdd { Palette.tealGradient } else { Palette.chip }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .disabled(!canAdd)
            .accessibilityLabel("Add person")
        }
        .padding(.top, 14)
    }

    private func add() {
        model.addMember(name: newName)
        newName = ""
        newNameFocused = false
    }
}

// MARK: - Row

/// One person: avatar (tap to recolour), an editable name, and an overflow menu.
private struct PersonRow: View {
    @EnvironmentObject var model: AppModel
    let member: Member
    let remove: (Member) -> Void

    /// Local mirror so typing stays responsive; committed on blur/submit.
    @State private var draftName: String = ""
    @FocusState private var editing: Bool

    var body: some View {
        let isMe = model.me?.id == member.id
        HStack(spacing: 12) {
            Button { model.cycleColor(member.id) } label: {
                MemberAvatar(member: member, size: 36)
            }
            .accessibilityLabel("\(member.name) colour")
            .accessibilityHint("Changes the avatar colour")

            TextField("", text: $draftName, prompt: Text("Name").foregroundStyle(Palette.muted))
                .focused($editing)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: editing) { _, focused in if !focused { commit() } }
                .accessibilityLabel("Name")

            if isMe {
                Text("You")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(member.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(member.color.opacity(0.16), in: Capsule())
            }

            Menu {
                if !isMe {
                    Button { model.setMe(member.id) } label: {
                        Label("This is me", systemImage: "person.crop.circle")
                    }
                }
                Button { model.cycleColor(member.id) } label: {
                    Label("Change colour", systemImage: "paintpalette")
                }
                // Someone has to own the budget, so the last person stays.
                if model.members.count > 1 {
                    Button(role: .destructive) { remove(member) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(member.name)")
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .card(border: Palette.cardBorderSoft, radius: 15)
        .onAppear { draftName = member.name }
        .onChange(of: member.name) { _, name in if !editing { draftName = name } }
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            draftName = member.name        // reject empty names
            return
        }
        model.rename(member.id, to: trimmed)
    }
}

#Preview {
    PeopleSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}

#Preview("People — light") {
    PeopleSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.light)
}
