import SwiftUI

@main
struct BudgetTogetherApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            if model.hasHousehold {
                main
            } else {
                PairingView()
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        // Drives the whole tree, sheets included: every `Palette` token is a
        // dynamic colour that resolves against the scheme set here.
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var main: some View {
        ScrollView(showsIndicators: false) {
            Group {
                switch model.tab {
                case .home:   HomeView()
                case .log:    LogView()
                case .budget: BudgetView()
                case .stats:  StatsView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        // The toast rides in the bottom inset with the tab bar rather than in an
        // overlay. As an overlay it rendered correctly but never took the tap —
        // touches fell straight through to the row behind it, which meant
        // "Undo" opened whatever entry happened to be underneath. Living in the
        // layout also means it pushes the list up instead of covering it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                UndoToast()
                BottomBar()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { SampleDataBar() }
        .sheet(isPresented: $model.isAddingEntry) { AddSheet().environmentObject(model) }
        // Asked once the user is actually in a household — permission prompts
        // before there's anything to alert about get declined.
        .onAppear { Notifier.shared.start() }
    }
}

// MARK: - Bottom navigation

struct BottomBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Budget and Stats only appear once there's something in them to look
        // at. Four tabs on a first launch is four rooms to check, three of them
        // empty; the app earns them as the data arrives.
        let tabs = model.visibleTabs
        let split = (tabs.count + 1) / 2

        ZStack {
            HStack(spacing: 0) {
                ForEach(tabs.prefix(split), id: \.self) { navButton($0) }
                Spacer().frame(width: 56)   // gap for the floating add button
                ForEach(tabs.dropFirst(split), id: \.self) { navButton($0) }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(Palette.navBar)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.navBorder).frame(height: 1)
            }
            .animation(.easeInOut(duration: 0.25), value: tabs)
            // Navigational chrome, not content: four labels have to share one
            // row whatever the text size, and letting "Budget" wrap to "Budg/et"
            // helps nobody. The icons carry the meaning past this point.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)

            Button {
                Haptics.selected()
                model.isAddingEntry = true
            } label: {
                Image(systemName: "plus")
                    .appFont(25, weight: .bold)
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 56, height: 56)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Palette.addGlow, radius: 13, x: 0, y: 12)
            }
            .accessibilityLabel("Add something")
            .offset(y: -24)
        }
    }

    private func navButton(_ tab: Tab) -> some View {
        let isSelected = model.tab == tab
        return Button {
            Haptics.selected()
            model.tab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).appFont(20, weight: .medium)
                Text(tab.title)
                    .appFont(9.5, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Palette.teal : Palette.muted)
            .frame(maxWidth: .infinity)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared rows

/// Steps the whole app between months. Forward stops at the current month,
/// since there's nothing to show past it; tapping the label jumps back to today.
struct MonthStepper: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            arrow("chevron.left", enabled: true) { model.stepMonth(-1) }
            Button { model.goToCurrentMonth() } label: {
                Text(model.monthTitle)
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(model.isCurrentMonth ? Palette.sub : Palette.teal)
                    .frame(minWidth: 96)
            }
            .accessibilityLabel(model.isCurrentMonth ? model.monthTitle
                                                     : "\(model.monthTitle), back to this month")
            arrow("chevron.right", enabled: model.canGoForward) { model.stepMonth(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(12, weight: .bold)
                .foregroundStyle(enabled ? Palette.chipText : Palette.muted.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(Palette.chip, in: Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous month" : "Next month")
    }
}

/// A member's initial on their colour. `ring` draws the separating outline used
/// where avatars overlap in a stack.
///
/// The whole circle scales with Dynamic Type rather than only its letter — the
/// glyph is sized as a fraction of the diameter, so scaling the text alone would
/// push it straight out of the circle.
struct MemberAvatar: View {
    let member: Member
    var ring: Color?
    @ScaledMetric private var size: CGFloat

    init(member: Member, size: CGFloat = 32, ring: Color? = nil) {
        self.member = member
        self.ring = ring
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Text(member.letter)
            .font(.system(size: size * 0.375, weight: .bold))
            .foregroundStyle(member.ink)
            .frame(width: size, height: size)
            .background(member.color, in: Circle())
            .overlay {
                if let ring { Circle().strokeBorder(ring, lineWidth: 2) }
            }
            .accessibilityLabel(member.name)
    }
}

struct EntryRow: View {
    @EnvironmentObject var model: AppModel
    let entry: Entry
    var showDelete = false
    /// Whether the note and the reaction controls are shown. Off on Home, where
    /// the list is a glance; on in the log, where it's the shared space.
    var showsSocial = false

    @State private var pickingReaction = false

    var body: some View {
        let bucket = Bucket.named(entry.bucket)
        let member = model.member(entry.memberID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: bucket.symbol)
                    .appFont(16, weight: .semibold)
                    .foregroundStyle(bucket.color)
                    .frame(width: 36, height: 36)
                    .background(bucket.tint,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.place).appFont(14, weight: .semibold).lineLimit(1)
                    HStack(spacing: 5) {
                        if let subtitle = entry.categorySubtitle {
                            Text(subtitle).appFont(11.5).foregroundStyle(Palette.sub)
                        }
                        if entry.isPrivate {
                            Image(systemName: "lock.fill")
                                .appFont(9, weight: .semibold)
                                .foregroundStyle(Palette.label9)
                                .accessibilityLabel("Private")
                        }
                        if let mood = entry.mood {
                            Image(systemName: mood.symbol)
                                .appFont(9, weight: .semibold)
                                .foregroundStyle(mood.color)
                                .accessibilityLabel(mood.label)
                        }
                        if entry.hasNote, !showsSocial {
                            Image(systemName: "text.bubble.fill")
                                .appFont(9, weight: .semibold)
                                .foregroundStyle(Palette.muted)
                                .accessibilityLabel("Has a note")
                        }
                    }
                }

                Spacer(minLength: 4)

                // With more than two people a bare dot stops being readable, so
                // the initial rides along with it.
                HStack(spacing: 4) {
                    Circle().fill(member.color).frame(width: 8, height: 8)
                    Text(member.letter)
                        .appFont(10, weight: .bold)
                        .foregroundStyle(Palette.sub)
                }
                .accessibilityLabel(member.name)

                Text(entry.signedAmount).mono(14).foregroundStyle(entry.kind.color)

                // The react control sits up here with delete rather than on a
                // row of its own: a dedicated row costs ~28pt on every single
                // entry, and a log is mostly entries nobody needs to say
                // anything about.
                if showsSocial, canReact {
                    Button { pickingReaction = true } label: {
                        Image(systemName: model.myReaction(to: entry.id) == nil
                              ? "face.smiling" : "face.smiling.inverse")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(model.myReaction(to: entry.id) == nil
                                             ? Palette.muted : Palette.teal)
                    }
                    .accessibilityLabel("React to \(entry.place)")
                    .popover(isPresented: $pickingReaction) {
                        ReactionPicker(entryID: entry.id)
                            .environmentObject(model)
                            .presentationCompactAdaptation(.popover)
                    }
                }

                if showDelete {
                    Button { model.delete(entry.id) } label: {
                        Image(systemName: "xmark")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(Palette.muted)
                    }
                    .accessibilityLabel("Delete \(entry.place)")
                }
            }

            if showsSocial {
                // The note in the spender's own words, then whatever anyone
                // said back. Together these turn a row of the ledger into a
                // small exchange instead of an audit line.
                if entry.hasNote {
                    Text(entry.note)
                        .appFont(12)
                        .foregroundStyle(Palette.chipText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.field,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.top, 9)
                }
                reactionBar
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .card(border: Palette.cardBorderSoft, radius: 15)
    }

    /// Whether there's anyone to react *to*. Never your own entries — reacting
    /// to yourself isn't a thing anyone wants — and never private ones, which
    /// by definition nobody else can see.
    private var canReact: Bool {
        model.me?.id != entry.memberID && !entry.isPrivate && model.members.count > 1
    }

    /// Reactions people have already left. Only takes a row when there are some.
    @ViewBuilder
    private var reactionBar: some View {
        let existing = model.reactions(for: entry.id)
        if !existing.isEmpty {
            HStack(spacing: 6) {
                ForEach(existing) { reaction in
                    HStack(spacing: 4) {
                        Image(systemName: reaction.kind.symbol)
                            .appFont(9.5, weight: .semibold)
                            .foregroundStyle(reaction.kind.color)
                        Text(model.member(reaction.memberID).letter)
                            .appFont(9, weight: .bold)
                            .foregroundStyle(Palette.sub)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Palette.chip, in: Capsule())
                    .accessibilityLabel("\(model.member(reaction.memberID).name): \(reaction.kind.label)")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 9)
        }
    }
}

/// The four things you can say about somebody else's spending, none of them
/// negative. See `ReactionKind` for why there's no thumbs-down.
struct ReactionPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entryID: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReactionKind.allCases) { kind in
                let isMine = model.myReaction(to: entryID) == kind
                Button {
                    model.react(to: entryID, with: kind)
                    dismiss()
                } label: {
                    Image(systemName: kind.symbol)
                        .appFont(17, weight: .semibold)
                        .foregroundStyle(kind.color)
                        .frame(width: 42, height: 42)
                        .background(isMine ? kind.color.opacity(0.18) : Color.clear, in: Circle())
                }
                .accessibilityLabel(kind.label)
                .accessibilityAddTraits(isMine ? .isSelected : [])
            }
        }
        .padding(8)
        .background(Palette.card)
    }
}

// MARK: - Progress bar

struct ProgressBar<Fill: ShapeStyle>: View {
    let pct: Double
    let fill: Fill
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.field)
                Capsule().fill(fill)
                    .frame(width: max(0, geo.size.width * pct / 100))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview harness

/// Wraps a screen in the chrome `RootView` normally supplies, backed by the
/// in-memory demo store.
struct PreviewShell<Content: View>: View {
    var scheme: ColorScheme = .dark
    @ViewBuilder var content: Content
    @StateObject private var model = AppModel.preview

    var body: some View {
        ScrollView(showsIndicators: false) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .background(Palette.screen.ignoresSafeArea())
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .preferredColorScheme(scheme)
    }
}
