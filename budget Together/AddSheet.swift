import SwiftUI

struct AddSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The entry being edited, or `nil` when logging a new one.
    var editing: Entry?

    @State private var amount = ""
    @State private var place = ""
    /// Resolved in `onAppear` once the budget's members are known.
    @State private var memberID = ""
    @State private var kind: EntryKind = .expense
    @State private var bucket = Bucket.fallback.id
    @State private var mood: Mood?
    @State private var note = ""
    @State private var isPrivate = false
    @State private var showPeople = false
    /// Once the user picks a category themselves, the guesser stops touching it.
    @State private var pickedCategory = false
    @State private var guess: CategoryGuess?
    /// Whether the rest of the form is showing. Closed by default: logging a
    /// coffee used to mean seven decisions, and six of them have a sane answer
    /// the app can work out for itself.
    @State private var showDetails = false
    /// Written by a successful add, which parks the sheet on a receipt rather
    /// than closing it. `nil` means the form is showing.
    @State private var saved: Receipt?
    /// Adds made without leaving the sheet. Surfaced once it's more than one, so
    /// a run of entries is visibly adding up.
    @State private var savedCount = 0

    @FocusState private var amountFocused: Bool

    /// On-device speech, for saying an amount instead of typing it.
    @StateObject private var voice = VoiceAmountListener()

    /// A snapshot of what an add wrote, taken at save time so the receipt keeps
    /// reading correctly after the form is cleared for the next entry.
    private struct Receipt {
        let place: String
        let amount: Double
        let kind: EntryKind
        let bucket: Bucket
        let memberName: String
        let isPrivate: Bool
    }

    /// Adaptive rather than a fixed four, so the labels still fit when Dynamic
    /// Type grows them.
    private static let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]
    /// People wrap across as many rows as they need — a budget can be shared
    /// by more than two.
    private static let peopleColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    /// The entry that would be saved, or `nil` while the form is incomplete.
    ///
    /// Only the amount is genuinely required. A missing place is filled from the
    /// category ("Food & Drink"), because insisting on a merchant name before
    /// you'll accept a number is exactly the kind of friction that stops people
    /// logging the small stuff — and the small stuff is most of it.
    private var draft: (place: String, amount: Double, memberID: String)? {
        guard !memberID.isEmpty, let amount = Fmt.amount(from: amount) else { return nil }
        let typed = place.trimmingCharacters(in: .whitespaces)
        return (typed.isEmpty ? Bucket.named(bucket).label : typed, amount, memberID)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if let saved {
                    receipt(saved)
                } else {
                    form
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
        .sheet(isPresented: $showPeople) { PeopleSheet().environmentObject(model) }
        .onAppear(perform: load)
        .onDisappear { voice.stop() }
        // Switching direction invalidates the category, since the two lists
        // share no ids.
        .onChange(of: kind) { _, new in
            if !Bucket.list(for: new, including: editing?.bucket).contains(where: { $0.id == bucket }) {
                bucket = Bucket.fallback(for: new).id
            }
            autoCategorize()
        }
        .onChange(of: place) { _, _ in autoCategorize() }
        // Someone added from the people sheet should be selectable right away;
        // if the selected person was removed, fall back rather than lose the draft.
        .onChange(of: model.members) { _, _ in
            if !model.members.contains(where: { $0.id == memberID }) { selectDefaultMember() }
        }
    }

    // MARK: - Sections

    /// Everything the draft is edited through. Swapped out wholesale once an add
    /// lands, so a stray tap can't retouch an entry that's already written.
    ///
    /// The order is the point. Amount, then a one-tap shortcut, then save —
    /// that's the whole path for the overwhelming majority of entries. Person,
    /// category, mood, note and privacy are all pre-answered and folded away
    /// behind one disclosure, reachable in a tap when the answer is wrong.
    @ViewBuilder
    private var form: some View {
        kindPicker
        amountField
        placeField
        if editing == nil { shortcuts }
        detailsDisclosure
        if showDetails {
            personPicker
            categoryPicker
            if kind == .expense { moodPicker }
            noteField
            privacyToggle
        } else {
            guessSummary
        }
        saveButton
        if editing != nil { deleteButton }
    }

    /// What the app has decided on your behalf, stated plainly so the folded-up
    /// form is never a black box. Tapping it opens the details.
    private var guessSummary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showDetails = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Bucket.named(bucket).symbol)
                    .appFont(10, weight: .semibold)
                    .foregroundStyle(Bucket.named(bucket).color)
                Text(Bucket.named(bucket).label)
                Text("·").foregroundStyle(Palette.muted)
                Text(model.member(memberID).name)
                Spacer(minLength: 0)
                Text("Change").foregroundStyle(Palette.teal)
            }
            .appFont(11.5, weight: .medium)
            .foregroundStyle(Palette.sub)
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filed under \(Bucket.named(bucket).label) for \(model.member(memberID).name). Change")
    }

    /// One tap to log something you log often. Built from the household's own
    /// history rather than a fixed list, so it's "Blue Bottle" and "Groceries"
    /// rather than someone else's idea of a common purchase.
    @ViewBuilder
    private var shortcuts: some View {
        let suggestions = model.frequentPlaces(for: kind)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(kind == .income ? "Usual sources" : "Usual suspects")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.sub)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach(suggestions) { shortcut in
                        Button { apply(shortcut) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: shortcut.bucket.symbol)
                                    .appFont(11, weight: .semibold)
                                    .foregroundStyle(shortcut.bucket.color)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(shortcut.place)
                                        .appFont(12.5, weight: .semibold)
                                        .lineLimit(1)
                                    Text(Fmt.money(shortcut.typicalAmount))
                                        .appFont(10.5)
                                        .foregroundStyle(Palette.sub)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .foregroundStyle(Palette.chipText)
                            .fieldBackground(AnyShapeStyle(Palette.card),
                                             border: Palette.cardBorder, radius: 12)
                        }
                        .accessibilityLabel("\(shortcut.place), usually \(Fmt.money(shortcut.typicalAmount))")
                        .accessibilityHint("Fills the form in")
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private var detailsDisclosure: some View {
        Button {
            Haptics.selected()
            withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .appFont(10, weight: .bold)
                Text(showDetails ? "Hide details" : "Add details")
                    .appFont(12.5, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.teal)
            .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }

    /// Optional, and the only field on this sheet whose audience is another
    /// person rather than a chart.
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Note").appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.sub)
                Text("optional").appFont(11).foregroundStyle(Palette.muted)
                Spacer()
            }
            TextField("", text: $note,
                      prompt: Text(model.members.count > 1
                                   ? "Anything worth saying about it?"
                                   : "Anything worth remembering?")
                        .foregroundStyle(Palette.muted),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .appFont(14)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .fieldBackground(radius: 13)
                .accessibilityLabel("Note")
            if model.members.count > 1 {
                Text("Everyone on the budget sees this. It's the cheapest way to answer "
                   + "\u{201C}what was that one?\u{201D} before it gets asked.")
                    .appFont(11)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 14)
    }

    private var header: some View {
        HStack {
            Text(title)
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
        .padding(.top, 6).padding(.bottom, 16)
    }

    private var title: String {
        if saved != nil { return "Added" }
        return editing == nil ? "Add a transaction" : "Edit transaction"
    }

    /// Where the sheet lands after an add: what was written, and the choice of
    /// logging another or being done. Nothing here closes on its own — several
    /// entries in a row are one sitting, and the app has no way to know which
    /// one was meant to be the last.
    private func receipt(_ saved: Receipt) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 9) {
                Image(systemName: "checkmark")
                    .appFont(19, weight: .bold)
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 44, height: 44)
                    .background(Palette.tealGradient, in: Circle())
                    .padding(.bottom, 2)

                Text(saved.kind.sign + Fmt.money2(saved.amount))
                    .mono(29)
                    .foregroundStyle(saved.kind == .income ? Palette.green : Palette.text)

                Text(saved.place)
                    .appFont(15, weight: .semibold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 5) {
                    Image(systemName: saved.bucket.symbol)
                        .appFont(10, weight: .semibold)
                        .foregroundStyle(saved.bucket.color)
                    // An entry saved without a place is titled with its
                    // category, so naming the category again just below it
                    // reads as a rendering fault.
                    if saved.bucket.label.caseInsensitiveCompare(saved.place) != .orderedSame {
                        Text(saved.bucket.label)
                        Text("·").foregroundStyle(Palette.muted)
                    }
                    Text(saved.memberName)
                    if saved.isPrivate {
                        Image(systemName: "lock.fill").appFont(9, weight: .semibold)
                        Text("Private")
                    }
                }
                .appFont(12, weight: .medium)
                .foregroundStyle(Palette.sub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22).padding(.horizontal, 16)
            .card(border: Palette.cardBorderSoft, radius: 18)
            // One announcement, rather than five fragments read in a row.
            .accessibilityElement(children: .combine)

            if savedCount > 1 {
                Text("\(Fmt.count(savedCount, "transaction")) logged so far")
                    .appFont(11.5)
                    .foregroundStyle(Palette.muted)
            }

            Button(action: addAnother) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").appFont(16, weight: .bold)
                    Text("Add another").appFont(15, weight: .bold)
                }
                .frame(maxWidth: .infinity).padding(15)
                .foregroundStyle(Palette.tealInk)
                .background(Palette.tealGradient)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(.top, 6)

            Button { dismiss() } label: {
                Text("Done")
                    .appFont(14.5, weight: .semibold)
                    .foregroundStyle(Palette.chipText)
                    .frame(maxWidth: .infinity).padding(13)
                    .fieldBackground(radius: 14)
            }
        }
        .padding(.top, 4)
    }

    /// Money out or money in. Everything downstream — categories, totals,
    /// charts — keys off this.
    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(EntryKind.allCases, id: \.self) { candidate in
                let isSelected = kind == candidate
                Button { kind = candidate } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate == .income ? "arrow.down.left" : "arrow.up.right")
                            .appFont(11, weight: .bold)
                        Text(candidate.label).appFont(13, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).padding(9)
                    .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                    .fieldBackground(isSelected ? AnyShapeStyle(tint.opacity(0.14))
                                                : AnyShapeStyle(Palette.card),
                                     border: isSelected ? tint : Palette.cardBorder,
                                     radius: 14)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.bottom, 14)
    }

    /// Accent for the current direction — green for money in.
    private var tint: Color { kind == .income ? Palette.green : Palette.teal }

    private var amountField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(kind.sign + Fmt.currencySymbol).mono(14, weight: .regular)
                    .foregroundStyle(Palette.muted)
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                    .appFont(46, weight: .bold, design: .monospaced)
                    .foregroundStyle(kind == .income ? Palette.green : Palette.text)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Amount")
            }
            voiceButton
        }
        .padding(.bottom, 6)
    }

    /// Say the amount instead of typing it.
    ///
    /// Hidden entirely when the device can't transcribe on-device — see
    /// `VoiceInput.swift` for why there is no network fallback.
    @ViewBuilder
    private var voiceButton: some View {
        if voice.isSupported {
            VStack(spacing: 6) {
                Button {
                    if voice.isListening { finishListening() } else { beginListening() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.fill")
                            .appFont(12, weight: .semibold)
                        Text(voice.isListening ? "Listening — tap to stop" : "Say it instead")
                            .appFont(12.5, weight: .semibold)
                    }
                    .foregroundStyle(voice.isListening ? Palette.over : Palette.teal)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(
                        (voice.isListening ? Palette.over : Palette.teal).opacity(0.14),
                        in: Capsule()
                    )
                }
                .accessibilityLabel(voice.isListening ? "Stop listening" : "Say the amount")

                if voice.isListening, !voice.transcript.isEmpty {
                    Text(voice.transcript)
                        .appFont(11.5)
                        .foregroundStyle(Palette.sub)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if case let .unavailable(reason) = voice.state {
                    Text(reason)
                        .appFont(11)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: voice.isListening)
        }
    }

    private func beginListening() {
        amountFocused = false
        Task { await voice.start() }
    }

    /// Takes whatever was heard. The amount fills the field; anything else said
    /// fills the place, but only when the user hasn't typed one — a transcript
    /// should never overwrite something they entered deliberately.
    private func finishListening() {
        voice.stop()
        if let heard = voice.amount {
            amount = Fmt.plain(heard)
            Haptics.saved()
        }
        let rest = voice.remainder.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty, place.trimmingCharacters(in: .whitespaces).isEmpty {
            place = rest
        }
    }

    /// Optional. The placeholder says so, because a field that looks required
    /// and isn't makes people abandon the entry rather than guess.
    private var placeField: some View {
        TextField("", text: $place,
                  prompt: Text(kind == .income ? "Where from? (optional)"
                                               : "Where? (optional)")
                    .foregroundStyle(Palette.muted))
            .textFieldStyle(.plain)
            .appFont(15, weight: .medium)
            .padding(.horizontal, 14).padding(.vertical, 13)
            .fieldBackground(radius: 13)
            .accessibilityLabel("Where")
            .padding(.bottom, 12)
    }

    private var personPicker: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Who spent it").appFont(12, weight: .semibold)
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
            HStack(spacing: 6) {
                Text("Category").appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.sub)
                // Say when the category was filled in for them, and why. A
                // silent change would be worse than the tap it saves.
                if let guess, !pickedCategory {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .appFont(9, weight: .semibold)
                        Text(guess.reason).lineLimit(1)
                    }
                    .appFont(10.5, weight: .medium)
                    .foregroundStyle(Palette.teal)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Bucket.list(for: kind, including: editing?.bucket)) { categoryChip($0) }
            }
        }
    }

    /// Optional, and tapping the selected mood clears it. A forced answer would
    /// be a guessed one, and the whole point is that the tag is honest.
    private var moodPicker: some View {
        VStack(spacing: 9) {
            HStack {
                Text("How did it feel?").appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.sub)
                Text("optional").appFont(11).foregroundStyle(Palette.muted)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Mood.allCases) { candidate in
                    let isSelected = mood == candidate
                    Button { mood = isSelected ? nil : candidate } label: {
                        HStack(spacing: 6) {
                            Image(systemName: candidate.symbol)
                                .appFont(11, weight: .semibold)
                                .foregroundStyle(candidate.color)
                            Text(candidate.label)
                                .appFont(12.5, weight: .semibold).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                        .fieldBackground(isSelected ? AnyShapeStyle(candidate.color.opacity(0.14))
                                                    : AnyShapeStyle(Palette.card),
                                         border: isSelected ? candidate.color : Palette.cardBorder,
                                         radius: 14)
                    }
                    .accessibilityLabel(candidate.label)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.top, 14)
    }

    /// Only meaningful in a household with someone else in it — with one member
    /// there's nobody to keep it from.
    @ViewBuilder
    private var privacyToggle: some View {
        if model.members.count > 1 {
            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep this private").appFont(13.5, weight: .semibold)
                    Text(isPrivate
                         ? "Stays on your device. It still counts toward the budget here, but never syncs to anyone else."
                         : "Everyone on the budget will see it.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .fieldBackground(radius: 13)
            .padding(.top, 14)
        }
    }

    private var saveButton: some View {
        let canSave = draft != nil
        return Button(action: save) {
            HStack(spacing: 8) {
                Image(systemName: editing == nil ? "plus" : "checkmark")
                    .appFont(16, weight: .bold)
                Text(editing == nil ? "Add to log" : "Save changes")
                    .appFont(15, weight: .bold)
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

    private var deleteButton: some View {
        Button {
            if let editing { model.delete(editing.id) }
            dismiss()
        } label: {
            Text("Delete transaction")
                .appFont(14, weight: .semibold)
                .foregroundStyle(Palette.over)
                .frame(maxWidth: .infinity).padding(13)
        }
        .padding(.top, 4)
    }

    // MARK: - Chips

    private func personChip(_ candidate: Member) -> some View {
        let isSelected = memberID == candidate.id
        return Button { memberID = candidate.id } label: {
            HStack(spacing: 7) {
                MemberAvatar(member: candidate, size: 18)
                Text(candidate.name)
                    .appFont(13, weight: .semibold)
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
                    .appFont(10, weight: .heavy)
                    .foregroundStyle(Palette.chipText)
                    .frame(width: 18, height: 18)
                    .background(Palette.chip, in: Circle())
                Text("Add").appFont(13, weight: .semibold)
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
        return Button {
            bucket = candidate.id
            pickedCategory = true
        } label: {
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

    // MARK: - Actions

    private func selectDefaultMember() {
        memberID = model.defaultMemberID ?? ""
    }

    /// Fills the category in from the place name. Only ever moves a selection
    /// the user hasn't made themselves.
    private func autoCategorize() {
        guard !pickedCategory else { return }
        let suggestion = model.categorizer.suggest(place: place, kind: kind)
        guess = (suggestion?.confidence ?? 0) >= CategoryGuess.threshold ? suggestion : nil
        if let guess, Bucket.list(for: kind).contains(where: { $0.id == guess.bucket }) {
            bucket = guess.bucket
        }
    }

    /// Fills the form in from a one-tap shortcut. The amount comes in as the
    /// usual figure but stays editable and stays focused — it's a starting
    /// point, not a claim about what was actually spent.
    private func apply(_ shortcut: AppModel.PlaceShortcut) {
        Haptics.selected()
        withAnimation(.easeOut(duration: 0.15)) {
            place = shortcut.place
            bucket = shortcut.bucket.id
            pickedCategory = true
            guess = nil
            if Fmt.amount(from: amount) == nil {
                amount = Fmt.plain(shortcut.typicalAmount)
            }
        }
        amountFocused = true
    }

    /// Seeds the form: from the entry being edited, or empty for a new one.
    private func load() {
        guard let editing else {
            selectDefaultMember()
            // Straight onto the number. It's the only required field, and
            // opening the sheet with the keyboard already up is the difference
            // between a five-second job and a fifteen-second one.
            amountFocused = true
            return
        }
        // An existing entry's category is already the user's answer, and an
        // edit has no "sensible default" to hide — everything opens.
        pickedCategory = true
        showDetails = true
        amount = Fmt.plain(editing.amount)
        place = editing.place
        bucket = editing.bucket
        kind = editing.kind
        mood = editing.mood
        note = editing.note
        isPrivate = editing.isPrivate
        memberID = editing.memberID
    }

    private func save() {
        guard let draft else { return }
        // Income carries no mood — the question only makes sense for spending.
        let tag = kind == .expense ? mood : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            model.updateEntry(editing, place: draft.place, amount: draft.amount,
                              bucket: bucket, memberID: draft.memberID, kind: kind,
                              mood: tag, note: trimmedNote, isPrivate: isPrivate)
            // An edit is one finished job — there's no "another" to offer.
            dismiss()
            return
        }
        model.addEntry(place: draft.place, amount: draft.amount,
                       bucket: bucket, memberID: draft.memberID, kind: kind,
                       mood: tag, note: trimmedNote, isPrivate: isPrivate)
        savedCount += 1
        amountFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            saved = Receipt(place: draft.place, amount: draft.amount, kind: kind,
                            bucket: Bucket.named(bucket),
                            memberName: model.member(draft.memberID).name,
                            isPrivate: isPrivate)
        }
    }

    /// Clears the draft for the next entry, keeping the direction and the person
    /// — a run of entries is usually the same person spending the same way.
    /// Privacy resets deliberately: on a shared budget, an entry should never
    /// inherit being hidden from the one before it, and neither should a note.
    private func addAnother() {
        pickedCategory = false
        guess = nil
        amount = ""
        place = ""
        mood = nil
        note = ""
        isPrivate = false
        showDetails = false
        bucket = Bucket.fallback(for: kind).id
        withAnimation(.easeOut(duration: 0.2)) { saved = nil }
        amountFocused = true
    }
}

#Preview {
    AddSheet()
        .environmentObject(AppModel.preview)
        .preferredColorScheme(.dark)
}
