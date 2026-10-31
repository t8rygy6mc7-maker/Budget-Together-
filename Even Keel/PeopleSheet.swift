// xcode: set sdk=iOS

import SwiftUI

// MARK: - People
//
// Managing everyone on the budget. Reached from the avatar stack on Home and
// from the "Add someone" chip in the add sheet.

struct PeopleSheet: View {
    @EnvironmentObject var model: AppModel

    @State private var newName = ""
    @State private var pendingRemoval: Member?
    @State private var alertsOn = false
    @State private var mutedBuckets: Set<String> = []
    @State private var deniedBySystem = false
    @FocusState private var newNameFocused: Bool

    var body: some View {
        ModalPage(title: "People",
                  subtitle: Fmt.count(model.members.count, "person", plural: "people") + " on this budget",
                  detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: 0) {
                whoAreYouPrompt

                RowGroup {
                    ForEach(model.members) { PersonRow(member: $0, remove: { pendingRemoval = $0 }) }
                }

                addField

                Text("Everyone here can be picked when logging a spend. Tap an avatar to change its colour.")
                    .appFont(12)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)
                    .padding(.horizontal, Space.md)

                SharingSection()
                BudgetSwitcher()
                alertsSection
                appearanceSection
                dataSection
            }
        }
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

    /// Asks which of these people is holding the phone, when that isn't known.
    ///
    /// "This is me" already lives in each row's overflow menu, but nothing ever
    /// pointed at it, and the state it fixes is silent — the app doesn't look
    /// broken, it just quietly attributes things to the wrong person and stops
    /// offering reactions. That's the case for asking plainly and inline rather
    /// than leaving it to be found.
    ///
    /// It's a question, not a warning: the honest framing is that the app
    /// doesn't know something yet, not that the user did anything wrong.
    @ViewBuilder
    private var whoAreYouPrompt: some View {
        // Seats with somebody's phone already behind them aren't on offer —
        // claiming one would be taking a name that belongs to a real person
        // who is, right now, logging things under it.
        let free = model.unclaimedSeats
        if model.needsLocalMember, !free.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .appFont(13, weight: .semibold)
                        .foregroundStyle(Palette.teal)
                    Text("Which one of these is you?")
                        .appFont(13.5, weight: .semibold)
                    Spacer(minLength: 0)
                }
                Text("This phone doesn't know yet, so new entries may be filed under "
                   + "the wrong person and you can't react to anyone's spending.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)

                // Everyone is offered directly. The household is small by
                // nature, and one tap here beats hunting through a row's
                // overflow menu for the same command.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(free) { member in
                        Button { model.setMe(member.id) } label: {
                            HStack(spacing: 6) {
                                MemberAvatar(member: member, size: 20)
                                Text(member.name)
                                    .appFont(12.5, weight: .semibold)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .fieldBackground(AnyShapeStyle(Palette.card))
                        }
                        .accessibilityLabel("I'm \(member.name)")
                    }
                }
            }
            .padding(13)
            .card(border: Palette.teal.opacity(0.45), radius: 16)
            .padding(.bottom, 12)
        }
    }

    /// Whether the budget is syncing, one tap from Home rather than three.
    ///
    /// Short on purpose — the full explanation lives on the data screen, and
    /// tapping this goes there. What it has to carry here is the one bit that
    /// matters at a glance: whether this household's money is being kept in
    /// more than one place. Silence would read as "yes", and for a device with
    /// no iCloud account that would be wrong.
    private var syncRow: some View {
        let status = model.cloudStatus
        return NavigationLink { DataSheet() } label: {
            RowLabel(symbol: status.symbol, color: status.tint, title: Text(status.title))
        }
        .buttonStyle(.row)
        .accessibilityHint("Opens your data, including what's synced")
        .task { await model.refreshCloudStatus() }
    }

    /// Export and erase. Sits at the bottom of the only settings surface the
    /// app has, rather than behind a menu, because a promise about data you
    /// can't find the controls for isn't much of a promise.
    private var dataSection: some View {
        RowGroup(title: "Your data") {
            syncRow

            // Names the lock as well. It lives on the data screen, and
            // under a title that only mentioned exporting and deleting,
            // nobody looking for a Face ID switch would think to open it.
            NavigationLink { DataSheet() } label: {
                RowLabel(symbol: "lock.shield.fill", title: Text("Privacy and your data"),
                         subtitle: Text("Lock with \(AppLock.biometryName), take a copy, or wipe it all."))
            }
            .buttonStyle(.row)
        }
        .padding(.top, Space.lg)
    }

    /// Limit alerts: off unless asked for, and silenceable per category.
    ///
    /// The old behaviour was to request notification permission on first launch
    /// and then push whenever any category crossed 80% or 100%. That's the
    /// app's loudest channel carrying its least welcome message to someone who
    /// never asked for it — and health and personal spending are precisely
    /// where an unsolicited buzz lands worst.
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionTitle("Alerts")

            Toggle(isOn: $alertsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tell me when a category is running low")
                        .appFont(13.5, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alertsOn ? "A single nudge at 80% and again at the limit."
                                  : "Off. Nothing will interrupt you.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                }
            }
            .padding(Space.md)
            .card()
            .onChange(of: alertsOn) { _, wantsOn in
                guard wantsOn else {
                    Notifier.shared.limitAlertsEnabled = false
                    return
                }
                Task {
                    let granted = await Notifier.shared.requestAuthorization()
                    Notifier.shared.limitAlertsEnabled = granted
                    // If iOS said no, don't leave a switch sitting on that
                    // silently does nothing.
                    if !granted { alertsOn = false; deniedBySystem = true }
                }
            }

            if deniedBySystem {
                Text("Notifications are switched off for this app in iOS Settings.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.over)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if alertsOn {
                Text("Mute any you'd rather not hear about")
                    .appFont(11.5)
                    .foregroundStyle(Palette.sub)
                    .padding(.top, 2)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(model.expenseCategories) { bucket in
                        let muted = mutedBuckets.contains(bucket.id)
                        Button {
                            Haptics.selected()
                            Notifier.shared.setMuted(!muted, for: bucket.id)
                            if muted { mutedBuckets.remove(bucket.id) }
                            else { mutedBuckets.insert(bucket.id) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: muted ? "bell.slash.fill" : bucket.symbol)
                                    .appFont(11, weight: .semibold)
                                    .foregroundStyle(muted ? Palette.muted : bucket.color)
                                Text(bucket.short)
                                    .appFont(12, weight: .semibold).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 9).padding(.vertical, 8)
                            .foregroundStyle(muted ? Palette.muted : Palette.chipText)
                            .fieldBackground(AnyShapeStyle(Palette.card))
                        }
                        .accessibilityLabel("\(bucket.label) alerts")
                        .accessibilityValue(muted ? "Muted" : "On")
                    }
                }
            }
        }
        .padding(.top, Space.lg)
        .onAppear {
            alertsOn = Notifier.shared.limitAlertsEnabled
            mutedBuckets = Set(model.expenseCategories.map(\.id).filter(Notifier.shared.isMuted))
        }
    }

    /// Appearance lives here rather than behind a settings screen the app
    /// doesn't have — People is already the "this device, these humans" sheet.
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionTitle("Appearance")

            // Not `appAnimation`: switching the scheme cross-fades colour and
            // moves nothing, which is the case Reduce Motion leaves alone.
            Picker("Appearance", selection: $model.appearance.animation(.easeInOut(duration: 0.2))) {
                ForEach(Appearance.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("Only on this phone — it won't change your partner's.")
                .appFont(11.5)
                .foregroundStyle(Palette.sub)
                .padding(.horizontal, Space.md)
        }
        .padding(.top, Space.lg)
    }

    private var addField: some View {
        HStack(spacing: Space.xs) {
            TextField("", text: $newName,
                      prompt: Text("Add someone — their name").foregroundStyle(Palette.muted))
                .focused($newNameFocused)
                .textFieldStyle(.plain)
                .appFont(15)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .fieldBackground()

            let canAdd = !newName.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: add) {
                Image(systemName: "plus")
                    .appFont(14, weight: .bold)
                    .foregroundStyle(canAdd ? Palette.tealInk : Palette.muted)
            }
            .primaryButtonStyle()
            .disabled(!canAdd)
            .accessibilityLabel("Add person")
        }
        .padding(.top, Space.sm)
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
        GroupedRow(separatorInset: Space.md + 32 + Space.sm) {
            content(isMe: isMe)
        }
        .onAppear { draftName = member.name }
        .onChange(of: member.name) { _, name in if !editing { draftName = name } }
    }

    private func content(isMe: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Button { model.cycleColor(member.id) } label: {
                MemberAvatar(member: member, size: 32)
            }
            .accessibilityLabel("\(member.name) colour")
            .accessibilityHint("Changes the avatar colour")

            TextField("", text: $draftName, prompt: Text("Name").foregroundStyle(Palette.muted))
                .focused($editing)
                .textFieldStyle(.plain)
                .appFont(14, weight: .medium)
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: editing) { _, focused in if !focused { commit() } }
                .accessibilityLabel("Name")

            if isMe {
                Text("You")
                    .appFont(10.5, weight: .bold)
                    .foregroundStyle(member.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(member.color.opacity(0.16), in: Capsule())
            } else if member.isClaimed {
                // Somebody's phone is behind this name. Worth showing, because
                // it's the only difference between a person on the budget and
                // a label for one — and the difference decides whether what
                // they spend arrives on its own.
                Image(systemName: "iphone.gen3")
                    .appFont(11.5, weight: .semibold)
                    .foregroundStyle(Palette.sub)
                    .accessibilityLabel("\(member.name) is on their own phone")
            }

            Menu {
                // Never offered for a seat someone else's phone already holds.
                if !isMe, !member.isClaimed {
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
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.label9)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(member.name)")
        }
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
