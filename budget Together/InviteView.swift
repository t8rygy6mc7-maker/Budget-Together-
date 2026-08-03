import SwiftUI

// MARK: - Putting someone's phone behind a name
//
// The People sheet has always been able to add a person, and what that meant
// was a name and an avatar colour to file entries under. That's still the right
// default — a household includes people without phones, and a budget shouldn't
// require everyone in it to have an iCloud account before it will let you track
// what they spend.
//
// What's new is the second half: a name on the list can now have a real person's
// phone behind it. These are the surfaces for that — offering the invite,
// showing who's actually joined, and asking a joiner which of these people they
// are.

// MARK: - Sharing section

/// Lives at the bottom of the People sheet, under the list it describes.
struct SharingSection: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmingStop = false
    @State private var confirmingLeave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHARING")
                .appFont(10, weight: .bold).tracking(0.8)
                .foregroundStyle(Palette.label9)

            statusCard

            if model.cloudStatus == .on {
                if model.canInvite {
                    inviteButton
                    if model.isShared {
                        Button(role: .destructive) { confirmingStop = true } label: {
                            Text("Stop sharing this budget")
                                .appFont(12.5, weight: .semibold)
                                .foregroundStyle(Palette.over)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                } else if model.isShared {
                    Text("You were invited into this budget, so only its owner can "
                       + "add anyone else to it.")
                        .appFont(11.5)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive) { confirmingLeave = true } label: {
                        Text("Leave this budget")
                            .appFont(12.5, weight: .semibold)
                            .foregroundStyle(Palette.over)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, 22)
        // Sharing is the one feature here that simply cannot work without an
        // iCloud account, so this section can't be the part of the app that
        // finds out last.
        .task { await model.refreshCloudStatus() }
        .sheet(item: $model.pendingShare) { prepared in
            CloudSharingSheet(share: prepared.share,
                              container: prepared.container,
                              title: prepared.title,
                              onStopSharing: { model.reload() },
                              onSaved: { model.reload() })
                .ignoresSafeArea()
        }
        .alert("Couldn't make the invite",
               isPresented: Binding(get: { model.shareError != nil },
                                    set: { if !$0 { model.dismissShareError() } })) {
            Button("OK", role: .cancel) { model.dismissShareError() }
        } message: {
            Text(model.shareError ?? "")
        }
        .confirmationDialog("Stop sharing this budget?",
                            isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                Task { await model.stopSharing() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It disappears from everyone else's phone. Everything they logged "
               + "stays here with you.")
        }
        .confirmationDialog("Leave this budget?",
                            isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task { await model.leaveSharedBudget() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It comes off this phone. Everything you logged into it stays "
               + "with the person who owns it — it was always their copy.")
        }
    }

    /// What sharing is currently doing, said plainly. The three states people
    /// actually land in are "just you", "waiting on someone", and "shared" —
    /// and the difference between the first two matters, because an invite
    /// nobody opened looks exactly like a working share from the inviter's side.
    private var statusCard: some View {
        let joined = model.participants.filter { !$0.isOwner && $0.hasAccepted }
        let waiting = model.participants.filter { !$0.isOwner && !$0.hasAccepted }

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.isShared ? "person.2.fill" : "person.fill")
                .appFont(15, weight: .semibold)
                .foregroundStyle(model.isShared ? Palette.green : Palette.teal)
                .frame(width: 34, height: 34)
                .background((model.isShared ? Palette.green : Palette.teal).opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(joined: joined.count, waiting: waiting.count))
                    .appFont(14, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(detail(joined: joined, waiting: waiting))
                    .appFont(11.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .card(border: Palette.cardBorderSoft, radius: 15)
        .accessibilityElement(children: .combine)
    }

    private func headline(joined: Int, waiting: Int) -> String {
        guard model.cloudStatus != .checking else { return "Checking iCloud…" }
        guard model.cloudStatus == .on else { return "Sharing needs iCloud" }
        if joined > 0 {
            return "Shared with ^[\(joined) other person](inflect: true)"
        }
        if waiting > 0 { return "Invite sent" }
        return "This budget is just yours"
    }

    private func detail(joined: [BudgetStore.ShareParticipant],
                        waiting: [BudgetStore.ShareParticipant]) -> String {
        guard model.cloudStatus == .on else { return model.cloudStatus.detail }
        if !joined.isEmpty {
            // CloudKit only hands over a name once its owner has accepted, and
            // sometimes not even then, so "They" has to be a real fallback
            // rather than a case that never happens.
            let named = joined.compactMap { $0.name.isEmpty ? nil : $0.name }
            let who = named.isEmpty ? "They" : named.formatted(.list(type: .and))
            let tail = waiting.isEmpty ? "" :
                " ^[\(waiting.count) invite](inflect: true) hasn't been opened yet."
            return "\(who) log from their own phone, and it lands here.\(tail)"
        }
        if !waiting.isEmpty {
            return "Nobody's opened it yet. Until they do, everything here is "
                 + "still only on your devices."
        }
        return "Everyone above is a name on this phone. Invite someone to put "
             + "their own phone behind one — what they log turns up here, and "
             + "what you log turns up there."
    }

    private var inviteButton: some View {
        Button {
            Haptics.selected()
            Task { await model.prepareInvite() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                Text(model.isShared ? "Invite someone else" : "Invite someone")
            }
            .appFont(14, weight: .bold)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(Palette.tealInk)
            .background(Palette.tealGradient,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Budget switcher

/// Only appears once this phone holds more than one budget, which only happens
/// when somebody who already had their own is invited into another. Before
/// that it would be a control with one option.
struct BudgetSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.households.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("BUDGETS")
                    .appFont(10, weight: .bold).tracking(0.8)
                    .foregroundStyle(Palette.label9)

                ForEach(model.households) { house in
                    let isCurrent = house.id == model.currentHouseholdID
                    Button {
                        guard !isCurrent else { return }
                        Haptics.selected()
                        model.switchHousehold(to: house.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: house.isOwned ? "house.fill" : "person.2.fill")
                                .appFont(13, weight: .semibold)
                                .foregroundStyle(isCurrent ? Palette.teal : Palette.muted)
                                .frame(width: 30, height: 30)
                                .background(Palette.chip,
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(house.name).appFont(13.5, weight: .semibold).lineLimit(1)
                                Text(house.isOwned ? "Yours" : "You were invited into this one")
                                    .appFont(11).foregroundStyle(Palette.sub)
                            }
                            Spacer(minLength: 4)
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .appFont(12, weight: .bold)
                                    .foregroundStyle(Palette.teal)
                            }
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .card(border: isCurrent ? Palette.teal.opacity(0.45) : Palette.cardBorderSoft,
                              radius: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : [.isButton])
                }

                Text("Switching changes what every screen shows. Nothing moves between them.")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
        }
    }
}

// MARK: - Claiming a seat

/// What a joiner sees the moment they land in somebody else's budget.
///
/// The People sheet has asked "which one of these is you?" for a while, but it
/// asked from three taps inside a settings screen — fine for a state you drift
/// into, useless for the one moment it's guaranteed to be true. Arriving from
/// an invite is that moment, so the question gets asked here instead, up front,
/// with the seats nobody else has taken.
struct SeatClaimSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var addingMyself = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .appFont(26, weight: .semibold)
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 58, height: 58)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.bottom, 16)

                Text("You're in")
                    .appFont(24, weight: .bold)
                    .padding(.bottom, 6)
                Text("This is **\(model.householdName)**. Which of these is you? "
                   + "It's how what you log gets filed, and it only has to be "
                   + "answered once.")
                    .appFont(13.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                seats

                if addingMyself { nameField } else { addMyselfButton }

                Button { dismiss() } label: {
                    Text("I'll do this later")
                        .appFont(12.5, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheetBg)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
    }

    @ViewBuilder
    private var seats: some View {
        let free = model.unclaimedSeats
        if free.isEmpty {
            Text("Everyone already on this budget has a phone behind their name, "
               + "so add yourself below.")
                .appFont(12)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(free) { member in
                    Button {
                        Haptics.saved()
                        model.setMe(member.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            MemberAvatar(member: member, size: 26)
                            Text(member.name)
                                .appFont(13.5, weight: .semibold)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 10)
                        .fieldBackground(AnyShapeStyle(Palette.card),
                                         border: Palette.cardBorder, radius: 13)
                    }
                    .accessibilityLabel("I'm \(member.name)")
                }
            }
            .padding(.bottom, 14)
        }
    }

    private var addMyselfButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { addingMyself = true }
            nameFocused = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").appFont(11, weight: .bold)
                Text(model.unclaimedSeats.isEmpty ? "Add myself" : "I'm not on this list")
                    .appFont(13, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.teal)
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        HStack(spacing: 9) {
            TextField("", text: $newName,
                      prompt: Text("Your name").tinted(Palette.muted))
                .focused($nameFocused)
                .textFieldStyle(.plain)
                .appFont(15, weight: .medium)
                .submitLabel(.done)
                .onSubmit(addMyself)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .fieldBackground(radius: 13)

            let canAdd = !newName.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: addMyself) {
                Image(systemName: "checkmark")
                    .appFont(16, weight: .bold)
                    .foregroundStyle(canAdd ? Palette.tealInk : Palette.muted)
                    .frame(width: 46, height: 46)
                    .background { if canAdd { Palette.tealGradient } else { Palette.chip } }
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .disabled(!canAdd)
            .accessibilityLabel("Join as this name")
        }
    }

    private func addMyself() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Haptics.saved()
        model.joinAsNewMember(name: newName)
        dismiss()
    }
}

// MARK: - Joining

/// Covers the screen while an invite is being taken, and says how it went.
///
/// Accepting a share is two round trips and a mirror-down, which on a slow
/// connection is long enough that an app which showed nothing would read as one
/// that had ignored the tap.
struct JoiningOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.joining {
        case .idle:
            EmptyView()
        case .joining:
            ZStack {
                Palette.screen.opacity(0.96).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(Palette.teal).scaleEffect(1.2)
                    Text("Joining the budget…")
                        .appFont(14, weight: .semibold)
                    Text("Fetching what's already been logged.")
                        .appFont(12).foregroundStyle(Palette.sub)
                }
            }
            .transition(.opacity)
        case let .failed(why):
            ZStack {
                Palette.screen.opacity(0.96).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .appFont(24, weight: .semibold)
                        .foregroundStyle(Palette.over)
                    Text("Couldn't open that invite")
                        .appFont(17, weight: .bold)
                    Text(why)
                        .appFont(13)
                        .foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.dismissJoinResult() } label: {
                        Text("OK")
                            .appFont(14, weight: .bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .foregroundStyle(Palette.tealInk)
                            .background(Palette.tealGradient,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .card()
                .padding(.horizontal, 28)
            }
            .transition(.opacity)
        case .joined:
            // The seat-claim sheet is the acknowledgement — a separate
            // "you're in!" step before it would be a tap that says nothing.
            Color.clear.onAppear { model.dismissJoinResult() }
        }
    }
}

#Preview("Seat claim") {
    SeatClaimSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
