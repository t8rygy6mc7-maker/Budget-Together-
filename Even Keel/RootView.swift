import Combine
import SwiftUI

@main
struct EvenKeelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            // The unit tests are hosted in the app, so the app launches to run
            // them. Without this it would also build its own `AppModel` on the
            // real store, and the two would take turns rewriting the shared
            // category registry underneath the tests.
            if !Self.isHostingTests { RootView() }
        }
    }

    private static let isHostingTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// Where an invite lands between iOS handing it over and the app being
    /// ready for it. See `SceneDelegate`.
    @ObservedObject private var inbox = ShareInbox.shared
    /// The optional Face ID gate. See `AppLock`.
    @ObservedObject private var lock = AppLock.shared
    @State private var showSeatClaim = false

    var body: some View {
        Group {
            if lock.isLocked {
                LockScreen()
            } else {
                unlocked
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        // Drives the whole tree, sheets included: every `Palette` token is a
        // dynamic colour that resolves against the scheme set here.
        .preferredColorScheme(model.appearance.colorScheme)
        // Asks iCloud who's holding this phone, so a device that already has a
        // seat on a shared budget recognises it instead of asking again.
        //
        // Outside the gate on purpose. Sync, invites and the seat question all
        // keep working while the app is locked — they write to the store, not
        // to the screen — so unlocking lands on a budget that's already caught
        // up rather than one that starts catching up at that moment.
        .task {
            await model.adoptCloudIdentity()
            // Checked here as well as in `onChange`: someone who dismissed the
            // question last time relaunches with it already true, and a change
            // handler never fires for a value that was true on arrival.
            if model.needsSeatClaim { showSeatClaim = true }
        }
        // A `@Published` publisher replays its current value on subscribe,
        // which is what covers the cold-launch case: the tap that started the
        // app delivers the invite long before this view exists.
        .onReceive(inbox.$pending.compactMap { $0 }) { metadata in
            ShareInbox.shared.pending = nil
            Task { await model.accept(metadata) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.didEnterBackground()
            case .active:
                lock.didBecomeActive()
                // The app can sit in memory across midnight, or a month end.
                model.refreshIfDayChanged()
            default:
                break
            }
        }
        // A cross-fade, so it keeps a plain animation rather than an
        // `appAnimation` — fading is already what Reduce Motion asks for here.
        // See the rule at the top of `Comfort.swift`.
        //
        // Only on the way *out* of the lock. Closing the gate is a cut: it
        // closes as the app comes back to the front, while the privacy cover
        // above is fading away, and a budget cross-fading out underneath a
        // cover that's cross-fading out is a tenth of a second of exactly what
        // the lock is for.
        .animation(lock.isLocked ? nil : .easeInOut(duration: 0.2), value: lock.isLocked)
        // Covers the screen the moment the app stops being frontmost, before
        // iOS takes the picture it shows in the app switcher. See `PrivacyCover`.
        .overlay {
            if scenePhase != .active { PrivacyCover() }
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase)
    }

    /// Everything the gate stands in front of.
    ///
    /// The sheet, the overlay and the alert live on this branch rather than on
    /// the tree above it, and that placement is the safeguard rather than
    /// tidiness: a `sheet` presents above *everything*, `LockScreen` included,
    /// so a seat-claim question arriving while the app is locked would put a
    /// household's member list on top of the very screen hiding it. Attached
    /// here, there is no presenter until the gate is open. The state behind
    /// them still updates meanwhile — `showSeatClaim` set while locked simply
    /// presents at the moment of unlocking.
    private var unlocked: some View {
        Group {
            if model.hasHousehold {
                main
            } else {
                PairingView()
            }
        }
        // Asked as soon as somebody lands in a budget they were invited into,
        // rather than left to be found three taps deep in People.
        .onChange(of: model.needsSeatClaim) { _, needed in
            if needed { showSeatClaim = true }
        }
        .sheet(isPresented: $showSeatClaim) {
            SeatClaimSheet().environmentObject(model)
        }
        .overlay { JoiningOverlay().environmentObject(model) }
        .animation(.easeInOut(duration: 0.2), value: model.joining)
        .alert("That's already someone's",
               isPresented: Binding(get: { model.seatConflict != nil },
                                    set: { if !$0 { model.dismissSeatConflict() } })) {
            Button("OK", role: .cancel) { model.dismissSeatConflict() }
        } message: {
            Text("\(model.seatConflict ?? "That name") is signed in on another "
               + "phone. Pick a different one, or add yourself.")
        }
        // Last, so a gate it puts up replaces the sheets and alerts above as
        // well as the screens. Inside the lock for the same reason they are.
        .ageChecks(hasBudget: model.hasHousehold)
    }

    private var main: some View {
        MainTabs()
            // Asked once the user is actually in a household — permission prompts
            // before there's anything to alert about get declined.
            .onAppear { Notifier.shared.start() }
    }
}

// MARK: - Privacy cover

/// What the app looks like from outside itself.
///
/// When an app stops being frontmost, iOS photographs it and keeps the picture
/// to show in the app switcher — and, once taken, that picture is a page of
/// somebody's finances sitting in a cache the app doesn't control. Every other
/// promise this app makes is about the data on disk; this is the copy nobody
/// asked for. Covering the window before the shutter goes means the switcher
/// shows the app's own face instead of a month's spending, and a phone handed
/// over to show a photo doesn't quietly show a salary.
///
/// Tied to `scenePhase != .active` rather than to backgrounding alone, because
/// the picture is taken on the way out and `.background` arrives too late to be
/// sure of beating it. The cost is that a system permission alert — the
/// microphone, notifications — briefly shows this instead of the screen behind
/// it. Deliberately built to read as a deliberate screen rather than a blank
/// one, so that moment looks like the app resting, not the app breaking.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.screen
            Image(systemName: "heart.text.square.fill")
                .appFont(34, weight: .semibold)
                .foregroundStyle(Palette.tealInk)
                .frame(width: 74, height: 74)
                .background(Palette.tealGradient,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .ignoresSafeArea()
        .transition(.opacity)
        // The switcher thumbnail isn't something anyone navigates, and reading
        // it out would announce a screen the user never opened.
        .accessibilityHidden(true)
    }
}

// MARK: - Navigation

/// Places you go, as opposed to jobs you finish. These push, so they come with a
/// back button, a swipe from the edge and a title that collapses as you scroll.
/// Every one of them used to be a bottom sheet, which is the habit that made the
/// app feel like a port: on iOS, a sheet means "deal with this and come back".
enum Route: Hashable {
    case wins, insights, challenges, recurring, goals, loans, categories

    @ViewBuilder
    var destination: some View {
        switch self {
        case .wins:       WinsSheet()
        case .insights:   InsightsSheet()
        case .challenges: ChallengesSheet()
        case .recurring:  RecurringSheet()
        case .goals:      GoalsSheet()
        case .loans:      LoansSheet()
        case .categories: CategoriesSheet()
        }
    }
}

/// What a tab bar item does. Add sits in the bar so it's a thumb away from every
/// screen, but it opens the add panel rather than being somewhere to go, so it's
/// never actually selected.
private enum TabSlot: Hashable {
    case page(Tab)
    case add
}

/// The app's top level. Which bar that means is the system's call: along the
/// bottom on a phone, floating along the top or as a sidebar on a wide display,
/// and on its end in the poses where iPhone Duo moves its own bars to the side.
struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    /// Where the app was left, so reopening it goes back there.
    @SceneStorage("selectedTab") private var savedTab = Tab.home.rawValue

    var body: some View {
        Group {
            if #available(iOS 26.1, *) {
                GlassTabs(selection: selection)
            } else {
                ClassicTabs(selection: selection)
            }
        }
        .modifier(AddPanel())
        .onAppear {
            // `visibleTabs` because a tab that hasn't been earned yet can't be
            // landed on, whatever was saved.
            if model.tab == .home, let tab = Tab(rawValue: savedTab),
               model.visibleTabs.contains(tab) {
                model.tab = tab
            }
        }
        .onChange(of: model.tab) { _, tab in savedTab = tab.rawValue }
    }

    private var selection: Binding<TabSlot> {
        Binding(get: { .page(model.tab) }, set: { slot in
            switch slot {
            case .page(let tab):
                model.tab = tab
            case .add:
                Haptics.selected()
                model.isAddingEntry = true
            }
        })
    }
}

@available(iOS 26.1, *)
private struct GlassTabs: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: TabSlot

    var body: some View {
        // Budget and Stats only appear once there's something in them to look
        // at. Four tabs on a first launch is four rooms to check, three of them
        // empty; the app earns them as the data arrives.
        TabView(selection: $selection) {
            page(.home)
            page(.log)
            if model.visibleTabs.contains(.budget) { page(.budget) }
            if model.visibleTabs.contains(.stats) { page(.stats) }
            SwiftUI.Tab("Add", systemImage: "plus", value: TabSlot.add, role: addRole) {
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: model.undoPrompt != nil || model.isSampleHousehold) {
            BarAccessory()
        }
    }

    /// What sets Add apart as its own control at the end of the bar, and keeps
    /// it there when the bar shrinks on scroll. iOS 27 has a role for exactly
    /// this; iOS 26 only gives that treatment to search.
    private var addRole: TabRole {
        if #available(iOS 27, *) { .prominent } else { .search }
    }

    private func page(_ tab: Tab) -> some TabContent<TabSlot> {
        SwiftUI.Tab(tab.title, systemImage: tab.symbol, value: TabSlot.page(tab)) {
            TabRoot(tab: tab)
        }
    }
}

/// The same shape on systems without the bar accessory, which arrived in 26.1.
/// Add is a plain item at the end of the bar.
private struct ClassicTabs: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: TabSlot

    var body: some View {
        TabView(selection: $selection) {
            ForEach(model.visibleTabs, id: \.self) { tab in
                TabRoot(tab: tab, carriesBanners: true)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(TabSlot.page(tab))
            }
            Color.clear
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(TabSlot.add)
        }
    }
}

/// One tab's navigation stack. Each tab has its own, so leaving one mid-scroll or
/// three screens deep and coming back finds it exactly where it was.
private struct TabRoot: View {
    let tab: Tab
    /// Whether the sample banner and undo offer live here, for systems without
    /// the bar accessory that otherwise carries them.
    var carriesBanners = false

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .home:   HomeView()
                case .log:    LogView()
                case .budget: BudgetView()
                case .stats:  StatsView()
                }
            }
            .navigationDestination(for: Route.self) { $0.destination }
            // In the layout rather than an overlay: as an overlay the undo offer
            // drew correctly but never took the tap, so touches fell through and
            // "Undo" opened the row underneath.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if carriesBanners {
                    VStack(spacing: 0) {
                        UndoToast()
                        SampleDataBar()
                    }
                }
            }
        }
    }
}

/// Logging something. A sheet on a phone. On anything wide enough, a panel pinned
/// beside the screen instead, which the user can resize, so several entries can
/// go in while the ledger they're being copied from stays in view.
private struct AddPanel: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: presented(pinned: false)) {
                AddSheet().environmentObject(model)
            }
            .inspector(isPresented: presented(pinned: true)) {
                AddSheet()
                    .environmentObject(model)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
            }
    }

    /// Only ever closes. iOS remembers an inspector column and writes `true`
    /// here while it sets the scene up, which opened the panel, keyboard and all,
    /// on launch. Opening it is the user's decision alone.
    private func presented(pinned: Bool) -> Binding<Bool> {
        Binding(get: { model.isAddingEntry && (sizeClass == .regular) == pinned },
                set: { if !$0 { model.isAddingEntry = false } })
    }
}

// MARK: - Shared rows

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
    /// Whether the note and the reaction controls are shown. Off on Home, where
    /// the list is a glance; on in the log, where it's the shared space.
    var showsSocial = false

    @State private var pickingReaction = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let bucket = Bucket.named(entry.bucket)
        VStack(alignment: .leading, spacing: 0) {
            // Past the accessibility sizes the place, its category and up to
            // five trailing controls can't share one line: the place truncated
            // to "Par…" and "Transport" broke into three pieces to make room.
            // So the controls drop onto a line of their own under the text.
            if typeSize.prefersStackedLayout {
                HStack(alignment: .top, spacing: 12) {
                    icon(bucket)
                    VStack(alignment: .leading, spacing: 6) {
                        titles
                        HStack(spacing: 12) {
                            memberTag
                            Spacer(minLength: 0)
                            controls
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    icon(bucket)
                    titles
                    Spacer(minLength: 4)
                    memberTag
                    controls
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
                                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                        .padding(.top, Space.xs)
                }
                reactionBar
            }
        }
    }

    private func icon(_ bucket: Bucket) -> some View {
        IconTile(symbol: bucket.symbol, color: bucket.color, fill: bucket.tint)
    }

    /// The place, then its category and whatever's worth flagging about it.
    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.place)
                .appFont(14, weight: .medium)
                .lineLimit(typeSize.prefersStackedLayout ? 2 : 1)
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
                if entry.belowTheLine {
                    Image(systemName: "minus.diamond.fill")
                        .appFont(9, weight: .semibold)
                        .foregroundStyle(Palette.moodJoy)
                        .accessibilityLabel("One-off, not counted against the budget")
                }
                if entry.hasNote, !showsSocial {
                    Image(systemName: "text.bubble.fill")
                        .appFont(9, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                        .accessibilityLabel("Has a note")
                }
            }
        }
    }

    /// With more than two people a bare dot stops being readable, so the
    /// initial rides along with it.
    private var memberTag: some View {
        let member = model.member(entry.memberID)
        return HStack(spacing: 4) {
            Circle().fill(member.color).frame(width: 8, height: 8)
            Text(member.letter)
                .appFont(10, weight: .bold)
                .foregroundStyle(Palette.sub)
        }
        .accessibilityLabel(member.name)
    }

    /// The amount, then what can be done to the row.
    @ViewBuilder
    private var controls: some View {
        Text(entry.signedAmount).mono(14).foregroundStyle(entry.kind.color)

        // The react control sits up here with delete rather than on a row of
        // its own: a dedicated row costs ~28pt on every single entry, and a log
        // is mostly entries nobody needs to say anything about.
        if showsSocial, canReact {
            Button { pickingReaction = true } label: {
                Image(systemName: model.myReaction(to: entry.id) == nil
                      ? "face.smiling" : "face.smiling.inverse")
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(model.myReaction(to: entry.id) == nil
                                     ? Palette.muted : Palette.teal)
            }
            // Its own target inside a row that's tappable as a whole.
            .buttonStyle(.borderless)
            .accessibilityLabel("React to \(entry.place)")
            .popover(isPresented: $pickingReaction) {
                ReactionPicker(entryID: entry.id)
                    .environmentObject(model)
                    .presentationCompactAdaptation(.popover)
            }
        } else if showsSocial, model.members.count > 1 {
            // Holds the react button's place on rows that can't have one —
            // your own, private ones — so the amounts stay in a column instead
            // of jumping right on every row of yours.
            Image(systemName: "face.smiling")
                .appFont(13, weight: .semibold)
                .hidden()
        }
    }

    /// Whether there's anyone to react *to*. Never your own entries — reacting
    /// to yourself isn't a thing anyone wants — and never private ones, which
    /// by definition nobody else can see.
    ///
    /// The `model.me` binding is load-bearing rather than incidental: written as
    /// `model.me?.id != entry.memberID`, a device that doesn't yet know which
    /// member it is compares `nil` against every id, passes, and grows a react
    /// button on *every* row — including the user's own entries — which then
    /// does nothing at all, because `AppModel.react` guards on the same missing
    /// id and returns. That state isn't hypothetical: `localMemberID` lives in
    /// UserDefaults and is deliberately never mirrored, so it is empty on any
    /// device that didn't create the household, and `deleteMember` clears it
    /// when you remove yourself.
    private var canReact: Bool {
        guard let me = model.me else { return false }
        return me.id != entry.memberID && !entry.isPrivate && model.members.count > 1
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
            .padding(.top, Space.xs)
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
        .padding(Space.xs)
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
        NavigationStack {
            content.navigationDestination(for: Route.self) { $0.destination }
        }
        .environmentObject(model)
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
        .preferredColorScheme(scheme)
    }
}
