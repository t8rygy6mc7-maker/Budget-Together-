import Combine
import SwiftUI

/// Everything the screens derive from the current month's entries, computed in
/// one pass whenever the data changes. Previously each of these was a computed
/// property that re-scanned every entry on every SwiftUI body evaluation.
struct MonthDigest {
    /// This month's entries, both directions, newest first.
    var entries: [Entry] = []
    /// Bucket id → amount spent. Buckets with no spending are absent.
    var totals: [String: Double] = [:]
    /// Buckets with spending, biggest first — drives the bubbles and charts.
    var ranked: [BucketTotal] = []
    var spent: Double = 0
    /// Money in. Never folded into `spent`, `totals` or `ranked`.
    var earned: Double = 0
    /// Income sources with amounts, biggest first.
    var incomeRanked: [BucketTotal] = []
    /// `Member.id` → amount spent.
    var byMember: [String: Double] = [:]
    /// Tagged spending only, biggest first. Untagged entries are simply absent.
    var byMood: [MoodTotal] = []
    /// How much of the month's spending carries a mood tag — the analysis is
    /// only worth showing once enough of it does.
    var moodTagged: Double = 0
    /// Spending in discretionary categories, for anti-budget mode.
    var discretionarySpent: Double = 0
    /// Day of month → spending, for the under-pace streak.
    var byDay: [Int: Double] = [:]
    /// Same-scope total for the previous month, for the header comparison.
    var previousSpent: Double = 0
    /// One-off spending the user has set aside from the plan. Deliberately
    /// *not* folded into `spent` — but tracked, and shown, because money that
    /// left the account has to appear somewhere.
    var belowTheLine: Double = 0
    var belowTheLineCount: Int = 0

    /// What the household actually kept this month.
    var net: Double { earned - spent }
}

/// One month's totals, for the trend chart.
struct MonthPoint: Identifiable {
    let key: String      // "yyyy-MM"
    let label: String    // "Jul"
    let spent: Double
    let earned: Double
    var id: String { key }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: Tab = .home
    /// Drives the add sheet. Lives here rather than in `RootView` so an empty
    /// state anywhere in the app can offer the tap that fills it.
    @Published var isAddingEntry = false
    /// Mirrors of the persisted store, republished whenever data changes
    /// locally or arrives from the partner's device.
    @Published private(set) var month = MonthDigest()
    @Published var caps: [String: Double] = [:]
    /// Everyone sharing the budget, oldest first.
    @Published private(set) var members: [Member] = []
    /// Which month every screen is showing. Defaults to the live one.
    @Published private(set) var selectedMonth = Date()
    /// Bills and paydays that repeat monthly, soonest day first.
    @Published private(set) var recurring: [Recurring] = []
    /// Loans and other balances owed, oldest first.
    @Published private(set) var loans: [Loan] = []
    /// Challenges with their live standing, newest window first.
    @Published private(set) var challenges: [ChallengeProgress] = []
    /// Totals for the months leading up to `selectedMonth`, oldest first.
    @Published private(set) var history: [MonthPoint] = []
    /// Streaks and badges, derived fresh on every reload.
    @Published private(set) var wins = Wins()
    /// Where this month lands if nothing changes.
    @Published private(set) var forecast = Forecast()
    /// What to do about it. Rule-based today; the engine is swappable.
    @Published private(set) var suggestions: [Suggestion] = []
    /// Repeating charges found in the ledger.
    @Published private(set) var subscriptions: [DetectedSubscription] = []
    /// Every category including hidden ones, spending first, in user order.
    /// The published copy exists so views re-render; the actual lookups still
    /// go through `Bucket.named(_:)` and the registry behind it.
    @Published private(set) var categories: [Bucket] = []
    /// Entry id → everyone's reactions to it.
    @Published private(set) var reactions: [String: [Reaction]] = [:]
    /// Months the household has marked unrepresentative, keyed "yyyy-MM".
    @Published private(set) var monthFlags: [String: MonthFlag] = [:]
    /// Whether the app is running on the throwaway "look around first" data.
    @Published private(set) var isSampleHousehold = false
    /// Whether an unspent remainder carries into the next month.
    @Published private(set) var rolloverEnabled = false
    /// The most recent reversible change, and the line offered about it.
    @Published private(set) var undoPrompt: UndoPrompt?

    private let suggestionEngine: SuggestionEngine = RuleSuggestionEngine()
    /// Rebuilt on every reload from the household's own entries.
    private(set) var categorizer: CategorySuggesting = HistoryCategorizer(entries: [])
    private let queryEngine: QueryEngine = RuleQueryEngine()
    /// Full history, kept for questions that reach past the selected month.
    private var allEntries: [Entry] = []
    /// Anti-budget mode: one number instead of eight. A per-device view
    /// preference, so one partner simplifying doesn't simplify for everyone.
    @Published var isSimplified = UserDefaults.standard.bool(forKey: "antiBudgetMode") {
        didSet { UserDefaults.standard.set(isSimplified, forKey: "antiBudgetMode") }
    }
    /// Light/dark/system. Per-device like `isSimplified` — one partner reading
    /// in bed shouldn't flip the other partner's phone to dark.
    // Parenthesised: without it Swift reads the `didSet` brace as a trailing
    // closure on `.system`.
    @Published var appearance: Appearance = (UserDefaults.standard
        .string(forKey: "appearance")
        .flatMap(Appearance.init(rawValue:)) ?? .system) {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    /// Whether this device has joined/created a household yet. Drives the
    /// pairing gate in `RootView`.
    @Published private(set) var hasHousehold = false

    private let store: BudgetStore
    private var membersByID: [String: Member] = [:]

    /// Caps used to seed a freshly created household. These total $3,110, which
    /// is wrong for most people and very wrong for some — `caps(forMonthlyTotal:)`
    /// rescales them to whatever the user actually has.
    static let defaultCaps: [String: Double] = [
        "housing": 1300, "food": 500, "transport": 250, "fun": 200,
        "shopping": 250, "personal": 150, "subs": 60, "savings": 400,
    ]

    static let defaultTotal: Double = defaultCaps.values.reduce(0, +)

    /// The default split scaled to a real monthly figure, rounded to whole
    /// dollars. Someone budgeting $600 a month gets a plan in their own units
    /// rather than one built for a $3,000 household.
    static func caps(forMonthlyTotal total: Double) -> [String: Double] {
        guard total > 0 else { return defaultCaps }
        let factor = total / defaultTotal
        return defaultCaps.mapValues { ($0 * factor).rounded() }
    }

    convenience init() { self.init(store: BudgetStore.shared) }

    init(store: BudgetStore) {
        self.store = store
        store.onChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: - Pairing

    /// Creates the shared household (seeded with default caps) with its creator
    /// as the first member, and marks this device the owner. In Step 3 this is
    /// followed by generating a CloudKit invite link.
    /// Creates the shared budget. `monthlyTotal` is genuinely optional now: with
    /// nothing supplied the budget starts with **no limits at all** rather than
    /// a scaled guess, and the app runs in plain logging mode until there's
    /// enough real spending to propose limits from. Being asked to commit to a
    /// number before you've seen the app is the single most off-putting thing a
    /// budgeting app can do, and it was the first screen.
    func createHousehold(name: String, ownerName: String = "You",
                         monthlyTotal: Double? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let owner = ownerName.trimmingCharacters(in: .whitespaces)
        store.createHousehold(name: trimmed.isEmpty ? "Together" : trimmed,
                              ownerName: owner.isEmpty ? "You" : owner,
                              defaultCaps: monthlyTotal.map(Self.caps(forMonthlyTotal:)) ?? [:])
        reload()
    }

    /// Fills the app with a worked example so it can be looked at before any
    /// decision is made about it. Nothing here survives "Start my own".
    func startLookingAround() {
        store.createHousehold(name: "Sample budget", ownerName: "You",
                              defaultCaps: Self.defaultCaps, isSample: true)
        let ids = store.loadSnapshot().members.map(\.id)
        var seatIDs = ids
        for (index, name) in ["Sam", "Alex"].enumerated() {
            if let member = store.addMember(name: name, colorIndex: index + 1) {
                seatIDs.append(member.id)
            }
        }
        guard !seatIDs.isEmpty else { return }
        for entry in Self.demoEntries {
            let seat = Int(entry.memberID) ?? 0
            store.addEntry(id: entry.id, date: entry.date, place: entry.place,
                           amount: entry.amount, bucket: entry.bucket,
                           memberID: seatIDs[seat % seatIDs.count], kind: entry.kind,
                           mood: entry.mood, note: entry.note,
                           createdAt: entry.createdAt)
        }
        reload()
    }

    /// Throws the sample away and returns to the welcome screen, so the user's
    /// own first entry isn't logged into a demo household alongside Sam's rent.
    func discardSampleAndStartOver() {
        store.deleteSampleHousehold()
        selectedMonth = Date()
        tab = .home
        dismissUndo()
        reload()
    }

    // MARK: - People

    /// This device's member, when it's known which one that is.
    var me: Member? { store.localMemberID.flatMap { membersByID[$0] } }

    /// The member an entry belongs to, falling back to a grey placeholder so a
    /// row whose member was deleted elsewhere still renders.
    func member(_ id: String) -> Member { membersByID[id] ?? .unknown }

    /// Who a new entry should be attributed to by default.
    var defaultMemberID: String? { me?.id ?? members.first?.id }

    /// Everyone with what they've spent this month, in household order. Members
    /// who haven't spent anything are included with a zero, so the legend shows
    /// the whole household rather than only the active half of it.
    var memberTotals: [MemberTotal] {
        members.map { MemberTotal(member: $0, total: month.byMember[$0.id] ?? 0) }
    }

    /// First unused avatar colour, so a small household never repeats one.
    private var nextColorIndex: Int {
        let used = Set(members.map(\.colorIndex))
        return (0..<MemberStyle.all.count).first { !used.contains($0) } ?? members.count
    }

    func addMember(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.addMember(name: trimmed, colorIndex: nextColorIndex)
        reload()
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != membersByID[id]?.name else { return }
        store.updateMember(id: id, name: trimmed)
        reload()
    }

    /// Steps a member to the next avatar colour — the whole colour picker, in
    /// one tap.
    func cycleColor(_ id: String) {
        guard let member = membersByID[id] else { return }
        store.updateMember(id: id, colorIndex: (member.colorIndex + 1) % MemberStyle.all.count)
        reload()
    }

    /// Marks a member as this device's person. Stored locally only.
    func setMe(_ id: String) {
        store.localMemberID = id
        objectWillChange.send()
    }

    /// Everything this member logged goes with them — `entryCount(for:)` is what
    /// the confirmation dialog warns with. Reversible for the same reason
    /// everything else is: this is the single most expensive tap in the app.
    func removeMember(_ id: String) {
        guard let member = membersByID[id] else { return }
        let theirs = allEntries.filter { $0.memberID == id }
        offerUndo(.deletedMember(member, entries: theirs),
                  message: "Removed \(member.name)"
                         + (theirs.isEmpty ? "." : " and \(Fmt.count(theirs.count, "entry", plural: "entries"))."))
        store.deleteMember(id: id)
        reload()
    }

    func entryCount(for id: String) -> Int { store.entryCount(memberID: id) }

    // MARK: - Live date context

    /// How many months of history the trend chart shows.
    private static let historyLength = 6

    var today: String { Fmt.isoDay(Date()) }
    var monthTitle: String { Fmt.monthTitle(selectedMonth) }
    var monthKey: String { Fmt.isoMonth(selectedMonth) }
    var previousMonthName: String { Fmt.monthName(Self.month(before: selectedMonth)) }

    /// Whether the selected month is the live one. Pace, safe-daily and
    /// days-left only mean anything when it is.
    var isCurrentMonth: Bool { monthKey == Fmt.isoMonth(Date()) }

    var daysLeft: Int {
        let cal = Calendar.current
        let now = Date()
        let total = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        return max(1, total - cal.component(.day, from: now))
    }

    /// There's nothing to show past the current month, so forward stops there.
    var canGoForward: Bool { !isCurrentMonth }

    func stepMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth)
        else { return }
        // Never walk into the future.
        guard Fmt.isoMonth(next) <= Fmt.isoMonth(Date()) else { return }
        selectedMonth = next
        reload()
    }

    func goToCurrentMonth() {
        guard !isCurrentMonth else { return }
        selectedMonth = Date()
        reload()
    }

    private static func month(before date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date
    }

    // MARK: - Derived values

    var spent: Double { month.spent }
    var earned: Double { month.earned }
    var net: Double { month.net }
    var capTotal: Double { caps.values.reduce(0, +) }

    // MARK: Anti-budget

    /// Standing commitments — rent, subscriptions, savings transfers. In
    /// anti-budget mode these are treated as handled, not as decisions.
    var committed: Double {
        // Hidden included, to stay consistent with `capTotal`: hiding a
        // category doesn't clear its limit, so its money is still spoken for.
        CategoryRegistry.allIncludingHidden
            .filter { $0.kind == .expense && $0.cadence == .fixed }
            .reduce(0) { $0 + (caps[$1.id] ?? 0) }
    }

    /// Everything not already spoken for: the only number anti-budget mode shows.
    var funMoney: Double { max(0, capTotal - committed) }
    var funSpent: Double { month.discretionarySpent }
    var funLeft: Double { funMoney - funSpent }
    var funDaily: Double { max(0, funLeft) / Double(daysLeft) }

    /// Even spread of the whole plan across the month — the yardstick a daily
    /// streak is measured against.
    var dailyAllowance: Double {
        let days = Calendar.current.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        return capTotal / Double(days)
    }
    var left: Double { max(0, plannedTotal - spent) }
    var safeDaily: Double { left / Double(daysLeft) }

    // MARK: Weekly framing
    //
    // A month is a long, abstract unit — "$840 left" over 19 days is hard to
    // convert into a decision at a till. A week is a thing people can actually
    // hold in their heads, so the same allowance is offered in both units and
    // the user can lead with whichever they think in.

    /// Days remaining in the current week, today included.
    var daysLeftInWeek: Int {
        guard isCurrentMonth else { return 7 }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let firstDay = calendar.firstWeekday
        let elapsed = (weekday - firstDay + 7) % 7
        // Never promise more days than the month itself has left.
        return max(1, min(7 - elapsed, daysLeft))
    }

    /// What's safe to spend between now and the end of the week.
    var weeklyAllowance: Double { safeDaily * Double(daysLeftInWeek) }

    /// Whether the weekly figure actually tells you anything the monthly one
    /// didn't. In the last few days of a month the two coincide, and repeating
    /// the same number under a different label is noise pretending to be help.
    var weeklyFramingIsUseful: Bool {
        isCurrentMonth && daysLeft > daysLeftInWeek
    }

    /// Spending since the start of the current week.
    var spentThisWeek: Double {
        guard isCurrentMonth else { return 0 }
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        else { return 0 }
        let startKey = Fmt.isoDay(weekStart)
        return month.entries
            .filter { $0.kind == .expense && $0.date >= startKey }
            .reduce(0) { $0 + $1.amount }
    }

    func spent(by memberID: String) -> Double { month.byMember[memberID] ?? 0 }

    /// Change in spending against the previous month. `nil` when there's nothing
    /// to compare against, so the header can omit the badge rather than show a
    /// meaningless figure.
    var monthOverMonth: (percent: Int, isDown: Bool)? {
        let previousKey = Fmt.isoMonth(Self.month(before: selectedMonth))
        // Comparing against a month the user has told us was strange produces a
        // number that's technically correct and completely misleading.
        guard !isUnusual(previousKey), !isSelectedMonthUnusual else { return nil }
        let previous = month.previousSpent
        guard previous > 0 else { return nil }
        let change = Fmt.whole(((month.spent - previous) / previous) * 100)
        guard change != 0 else { return nil }
        return (abs(change), change < 0)
    }

    /// Below this many purchases the ranking turns over with every entry, and a
    /// "takeaway" is really just the last thing somebody bought wearing a
    /// percentage.
    private static let minimumEntriesForTakeaway = 4

    /// One readable thing about where the month's money actually went, for the
    /// line under the total. `nil` whenever the honest answer is "not enough to
    /// say yet" — with two purchases logged, "Food & Drink is 100% of the
    /// total" is arithmetic dressed up as a pattern.
    var spendTakeaway: String? {
        guard spent > 0 else { return nil }
        let logged = month.entries.filter { $0.kind == .expense && !$0.belowTheLine }
        guard logged.count >= Self.minimumEntriesForTakeaway else { return nil }
        return Copy.takeaway(shares: month.ranked.map {
            (label: $0.bucket.label, share: $0.total / spent * 100)
        })
    }

    // MARK: - Bindings & mutations (write through to the store)

    func capBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { self.caps[id] ?? 0 },
            set: { typed in
                // The cap field binds a `Double` straight to a `TextField`, so
                // unlike every other money field in the app it never passes
                // through `Fmt.amount(from:)`. Without this, a decimal pad with
                // a minus key — or a paste — writes a negative limit, and a
                // negative limit propagates into `capTotal`, `left`,
                // `safeDaily` and the pace maths as a silently nonsensical
                // plan. Clamp on the way in; the field redraws with what was
                // actually stored.
                let newValue = typed.isFinite ? min(max(typed, 0), Fmt.maxAmount) : 0
                self.caps[id] = newValue            // optimistic UI update
                self.store.setCap(bucket: id, month: self.monthKey, amount: newValue)
                // A new limit deserves a fresh judgement — raising a limit should
                // let the 80% warning fire again against the new headroom.
                Notifier.shared.resetCapAlerts(bucketID: id, month: self.monthKey)
            }
        )
    }

    // MARK: - Forgiveness
    //
    // Budgets break. An app that can only report the breakage trains people to
    // stop looking; these are the three ways out that a spreadsheet doesn't
    // have — move the money, carry the slack forward, or say the month was
    // strange and have the app believe you.

    /// Moves headroom from one category to another for the selected month. The
    /// plan total is unchanged: this is a reallocation, not a raise, which is
    /// what makes it an honest answer to being over in one place.
    func moveBudget(from source: String, to destination: String, amount: Double) {
        guard amount > 0, source != destination else { return }
        let fromPrevious = caps[source] ?? 0
        let toPrevious = caps[destination] ?? 0
        guard fromPrevious >= amount else { return }

        offerUndo(.capsMoved(from: source, to: destination, month: monthKey,
                             fromPrevious: fromPrevious, toPrevious: toPrevious),
                  message: "Moved \(Fmt.money(amount)) to \(Bucket.named(destination).label).")
        store.setCap(bucket: source, month: monthKey, amount: fromPrevious - amount)
        store.setCap(bucket: destination, month: monthKey, amount: toPrevious + amount)
        Notifier.shared.resetCapAlerts(bucketID: destination, month: monthKey)
        Haptics.saved()
        reload()
    }

    /// How much could be taken from a category without pushing it over what's
    /// already been spent there — you can't lend out money you've spent.
    func movableAmount(from bucketID: String) -> Double {
        max(0, (caps[bucketID] ?? 0) - (month.totals[bucketID] ?? 0))
    }

    /// Categories with headroom to lend, biggest first.
    func donorBuckets(excluding bucketID: String) -> [(bucket: Bucket, available: Double)] {
        Bucket.all
            .filter { $0.id != bucketID }
            .map { ($0, movableAmount(from: $0.id)) }
            .filter { $0.1 >= 5 }
            .sorted { $0.1 > $1.1 }
    }

    func setRollover(_ enabled: Bool) {
        store.setRollover(enabled)
        reload()
    }

    /// What last month left on the table, carried in when rollover is on. Only
    /// ever positive — carrying an *overspend* forward would be a punishment
    /// mechanic, and this feature exists to be the opposite of one.
    var rollover: Double {
        guard rolloverEnabled, isCurrentMonth else { return 0 }
        let previousKey = Fmt.isoMonth(Self.month(before: selectedMonth))
        let previousCaps = store.caps(for: previousKey).values.reduce(0, +)
        guard previousCaps > 0 else { return 0 }
        return max(0, previousCaps - month.previousSpent)
    }

    /// The plan as it actually stands this month, rollover included.
    var plannedTotal: Double { capTotal + rollover }

    // MARK: Unusual months

    func isUnusual(_ monthKey: String) -> Bool { monthFlags[monthKey]?.isUnusual ?? false }
    var isSelectedMonthUnusual: Bool { isUnusual(monthKey) }
    var selectedMonthReason: String { monthFlags[monthKey]?.reason ?? "" }

    /// Marks the selected month as unrepresentative. It keeps its entries and
    /// its totals — it happened — but drops out of streaks, badges and the
    /// month-over-month comparison.
    func markMonthUnusual(_ isUnusual: Bool, reason: String = "") {
        store.setMonthFlag(month: monthKey, isUnusual: isUnusual, reason: reason)
        reload()
    }

    // MARK: Suggested limits

    /// Whether there's enough real spending to propose a plan from. Ten entries
    /// is roughly the point where the categories stop being noise.
    var canSuggestPlan: Bool {
        !hasPlan && allEntries.filter { $0.kind == .expense }.count >= 10
    }

    /// Limits derived from what the household has actually spent, rather than
    /// from a number they had to invent before they'd seen the app. Each
    /// category is its own average monthly spend, rounded up to something
    /// memorable, with a little headroom so the first month isn't a failure by
    /// construction.
    func suggestedPlan() -> [String: Double] {
        let expenses = allEntries.filter { $0.kind == .expense }
        guard !expenses.isEmpty else { return Self.defaultCaps }

        var byBucket: [String: Double] = [:]
        var months: Set<String> = []
        for entry in expenses {
            byBucket[entry.bucket, default: 0] += entry.amount
            months.insert(String(entry.date.prefix(7)))
        }
        let span = Double(max(months.count, 1))

        // Only propose limits for categories that are actually on offer —
        // suggesting one for a category the user has hidden would put a number
        // on the plan with no row anywhere to change it.
        let offerable = Set(expenseCategories.map(\.id))
        return byBucket
            .filter { offerable.contains($0.key) }
            .compactMapValues { total in
                let monthly = total / span * 1.1        // 10% headroom
                guard monthly >= 1 else { return nil }
                // Round to a figure someone would actually say out loud.
                let step: Double = monthly < 100 ? 10 : (monthly < 500 ? 25 : 50)
                return (monthly / step).rounded(.up) * step
            }
    }

    /// Writes a whole plan at once, for the suggestion flow and onboarding.
    func applyPlan(_ plan: [String: Double]) {
        for (bucket, amount) in plan {
            store.setCap(bucket: bucket, month: monthKey, amount: amount)
        }
        Haptics.saved()
        reload()
    }

    func addEntry(place: String, amount: Double, bucket: String,
                  memberID: String, kind: EntryKind = .expense, mood: Mood? = nil,
                  note: String = "", belowTheLine: Bool = false,
                  isPrivate: Bool = false) {
        store.addEntry(id: UUID().uuidString, date: today, place: place,
                       amount: amount, bucket: bucket, memberID: memberID,
                       kind: kind, mood: mood, note: note,
                       belowTheLine: belowTheLine, isPrivate: isPrivate)
        Haptics.saved()
        reload()
    }

    func updateEntry(_ entry: Entry, place: String, amount: Double, bucket: String,
                     memberID: String, kind: EntryKind, mood: Mood?, note: String,
                     belowTheLine: Bool, isPrivate: Bool) {
        offerUndo(.editedEntry(before: entry), message: "Changes to \(entry.place) saved.")
        store.updateEntry(id: entry.id, date: entry.date, place: place, amount: amount,
                          bucket: bucket, memberID: memberID, kind: kind, mood: mood,
                          note: note, belowTheLine: belowTheLine, isPrivate: isPrivate)
        Haptics.saved()
        reload()
    }

    func delete(_ id: String) {
        guard let entry = allEntries.first(where: { $0.id == id }) else { return }
        offerUndo(.deletedEntry(entry, reactions: reactions[id] ?? []),
                  message: "Deleted \(entry.place).")
        store.delete(id: id)
        Haptics.undone()
        reload()
    }

    // MARK: - Undo
    //
    // Every destructive action in the app routes through here. The point isn't
    // really recovery — most deletions are deliberate — it's that people tap
    // more freely, and explore more, when they can see that a mistake costs one
    // tap to fix. An app you're afraid to touch is an app you stop opening.

    /// What's on offer in the toast. `id` changes on every new prompt so the
    /// dismissal timer restarts rather than inheriting the last one's deadline.
    struct UndoPrompt: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    /// The inverse of whatever was just done. Stored as data rather than a
    /// closure so nothing captures `self` and the whole thing stays inspectable.
    private enum UndoableChange {
        case deletedEntry(Entry, reactions: [Reaction])
        case editedEntry(before: Entry)
        case deletedRecurring(Recurring)
        case deletedLoan(Loan)
        case deletedMember(Member, entries: [Entry])
        case capChanged(bucket: String, month: String, previous: Double)
        case capsMoved(from: String, to: String, month: String,
                       fromPrevious: Double, toPrevious: Double)
        case categoryChanged(before: Bucket)
        case categoryDeleted(Bucket)
    }

    private var pendingUndo: UndoableChange?
    private var undoExpiry: Task<Void, Never>?

    /// How long the offer stands. This was 7s and that turned out to be too
    /// quick: the window has to cover noticing the toast, reading it, deciding,
    /// and then reaching the button — and it's covering part of the list the
    /// whole time, so a miss means tapping whatever was underneath.
    private static let undoWindow: Duration = .seconds(12)

    private func offerUndo(_ change: UndoableChange, message: String) {
        pendingUndo = change
        undoPrompt = UndoPrompt(message: message)
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.dismissUndo()
        }
    }

    func dismissUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        pendingUndo = nil
        withAnimation(.easeOut(duration: 0.2)) { undoPrompt = nil }
    }

    func undo() {
        guard let change = pendingUndo else { return }
        switch change {
        case let .deletedEntry(entry, reactions):
            restore(entry)
            for reaction in reactions {
                store.toggleReaction(entryID: entry.id, memberID: reaction.memberID,
                                     kind: reaction.kind)
            }

        case let .editedEntry(before):
            store.updateEntry(id: before.id, date: before.date, place: before.place,
                              amount: before.amount, bucket: before.bucket,
                              memberID: before.memberID, kind: before.kind,
                              mood: before.mood, note: before.note,
                              belowTheLine: before.belowTheLine,
                              isPrivate: before.isPrivate)

        case let .deletedRecurring(item):
            store.saveRecurring(item)

        case let .deletedLoan(loan):
            store.saveLoan(loan)

        case let .deletedMember(member, entries):
            // The member row has to exist again before its entries can point at
            // it, and the id must be the original or every entry orphans.
            store.restoreMember(member)
            entries.forEach(restore)

        case let .capChanged(bucket, month, previous):
            store.setCap(bucket: bucket, month: month, amount: previous)
            Notifier.shared.resetCapAlerts(bucketID: bucket, month: month)

        case let .capsMoved(from, to, month, fromPrevious, toPrevious):
            store.setCap(bucket: from, month: month, amount: fromPrevious)
            store.setCap(bucket: to, month: month, amount: toPrevious)

        // Both restore by id, so an edit and a delete are the same write —
        // `saveCategory` inserts when the row is gone and updates when it isn't.
        case let .categoryChanged(before):
            store.saveCategory(before)

        case let .categoryDeleted(bucket):
            store.saveCategory(bucket)
        }
        Haptics.undone()
        dismissUndo()
        reload()
    }

    private func restore(_ entry: Entry) {
        store.addEntry(id: entry.id, date: entry.date, place: entry.place,
                       amount: entry.amount, bucket: entry.bucket,
                       memberID: entry.memberID, kind: entry.kind, mood: entry.mood,
                       note: entry.note, belowTheLine: entry.belowTheLine,
                       isPrivate: entry.isPrivate, createdAt: entry.createdAt)
    }

    // MARK: - Your data
    //
    // The two obligations that come with keeping everything on-device: a way
    // to take it with you, and a way to destroy it. Both operate on the whole
    // ledger, not the selected month.

    /// A file ready for the share sheet.
    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private func fullSnapshot() -> BudgetStore.Snapshot { store.loadSnapshot() }

    func exportCSV() -> ExportFile? {
        let snapshot = fullSnapshot()
        let csv = DataExport.csv(entries: snapshot.entries) { [weak self] id in
            self?.member(id).name ?? "Someone"
        }
        guard let data = csv.data(using: .utf8) else { return nil }
        let name = DataExport.filename(budget: store.householdName, ext: "csv")
        return DataExport.writeTemporary(data, named: name).map(ExportFile.init)
    }

    func exportJSON() -> ExportFile? {
        let snapshot = fullSnapshot()
        guard let data = DataExport.json(
            name: store.householdName,
            entries: snapshot.entries,
            categories: snapshot.categories,
            members: snapshot.members,
            caps: store.allCaps(),
            recurring: snapshot.recurring,
            loans: snapshot.loans,
            challenges: snapshot.challenges,
            monthFlags: snapshot.monthFlags,
            reactions: snapshot.reactions,
            rolloverEnabled: snapshot.rolloverEnabled
        ) else { return nil }
        let name = DataExport.filename(budget: store.householdName, ext: "json")
        return DataExport.writeTemporary(data, named: name).map(ExportFile.init)
    }

    /// How many entries are marked private, for the export warning.
    ///
    /// A private entry is the one thing the app promises never leaves the
    /// device, and an export is the one place that promise passes out of the
    /// app's hands. The file has to keep them — a backup that quietly drops
    /// rows isn't a backup — so the export screen says so instead, and only
    /// when there's actually something to say.
    var privateEntryCount: Int { allEntries.filter(\.isPrivate).count }

    /// How much there is to lose, for the confirmation copy. Vague warnings get
    /// dismissed; a count of what's about to go does not.
    var dataFootprint: (entries: Int, people: Int, months: Int) {
        let months = Set(allEntries.map { String($0.date.prefix(7)) })
        return (allEntries.count, members.count, months.count)
    }

    /// Destroys everything, irreversibly, on this device. Deliberately offers
    /// no undo — `offerUndo` is for slips, and this one is guarded by typing
    /// the word instead.
    func eraseEverything() {
        dismissUndo()
        store.eraseEverything()
        // An export is the most complete copy the app ever makes. Leaving one
        // in the temporary directory would mean the single most revealing file
        // is the one thing that survives being erased.
        DataExport.purgeAllExports()
        revealedTabs = []
        isSimplified = false
        selectedMonth = Date()
        tab = .home
        reload()
    }

    // MARK: - Categories
    //
    // Categories are the household's own list, not a fixed eight. Built-ins are
    // seeded rows like any other and can be renamed, recoloured, re-iconed,
    // reordered, hidden and reset — the one thing that never changes is a
    // category's id, because every entry, cap, recurring item and challenge in
    // the ledger points at it.

    func categories(for kind: EntryKind, includeHidden: Bool = false) -> [Bucket] {
        categories.filter { $0.kind == kind && (includeHidden || !$0.isHidden) }
    }

    var expenseCategories: [Bucket] { categories(for: .expense) }
    var incomeCategories: [Bucket] { categories(for: .income) }
    func hiddenCategories(for kind: EntryKind) -> [Bucket] {
        categories.filter { $0.kind == kind && $0.isHidden }
    }

    /// A blank category ready to be filled in, pre-styled so it looks like part
    /// of the set rather than a placeholder the user has to decorate.
    func draftCategory(for kind: EntryKind) -> Bucket {
        let colour = CategoryColor.leastUsed(among: categories.filter { $0.kind == kind })
        let next = (categories.filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
        return Bucket(id: "cat-" + UUID().uuidString, label: "", hex: colour.hex,
                      light: colour.light,
                      symbol: kind == .income ? "banknote.fill" : "tag.fill",
                      cadence: .variable, kind: kind, isBuiltIn: false, sortOrder: next)
    }

    /// Creates or updates. Rejects an empty name rather than storing one, since
    /// a nameless category is unpickable everywhere it appears.
    func saveCategory(_ bucket: Bucket) {
        let trimmed = bucket.label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let existing = categories.first { $0.id == bucket.id }
        if let existing {
            offerUndo(.categoryChanged(before: existing),
                      message: "Updated \(existing.label).")
        }
        store.saveCategory(Bucket(id: bucket.id, label: trimmed, hex: bucket.hex,
                                  light: bucket.lightHex, symbol: bucket.symbol,
                                  cadence: bucket.cadence, kind: bucket.kind,
                                  isHidden: bucket.isHidden, isBuiltIn: bucket.isBuiltIn,
                                  sortOrder: bucket.sortOrder))
        Haptics.saved()
        reload()
    }

    /// Hiding is the safe counterpart to deleting: the category stops being
    /// offered anywhere, but every entry ever filed under it keeps rendering as
    /// itself and keeps counting toward the month's totals.
    /// Whether hiding this one would leave its direction with nothing to pick.
    /// The add sheet has to be able to offer *something*, so the last visible
    /// category in a list stays — the same reason the last person on the budget
    /// can't be removed.
    func canHideCategory(_ id: String) -> Bool {
        guard let bucket = categories.first(where: { $0.id == id }) else { return false }
        return bucket.isHidden || categories(for: bucket.kind).count > 1
    }

    func setCategoryHidden(_ hidden: Bool, id: String) {
        guard let bucket = categories.first(where: { $0.id == id }),
              !hidden || canHideCategory(id) else { return }
        offerUndo(.categoryChanged(before: bucket),
                  message: hidden ? "Hid \(bucket.label)." : "\(bucket.label) is back.")
        store.saveCategory(Bucket(id: bucket.id, label: bucket.label, hex: bucket.hex,
                                  light: bucket.lightHex, symbol: bucket.symbol,
                                  cadence: bucket.cadence, kind: bucket.kind,
                                  isHidden: hidden, isBuiltIn: bucket.isBuiltIn,
                                  sortOrder: bucket.sortOrder))
        Haptics.selected()
        reload()
    }

    /// What still points at a category, and therefore whether deleting it would
    /// leave holes in the ledger.
    func categoryUsage(_ id: String) -> (entries: Int, caps: Int,
                                         recurring: Int, challenges: Int) {
        store.references(categoryID: id)
    }

    /// Whether this category can be removed outright rather than hidden. A
    /// built-in never can — resetting it is the equivalent, and its id may be
    /// referenced by the keyword categoriser.
    func canDeleteCategory(_ id: String) -> Bool {
        guard let bucket = categories.first(where: { $0.id == id }), !bucket.isBuiltIn,
              // Deleting the last visible one would leave nothing to file
              // against, exactly as hiding it would.
              bucket.isHidden || categories(for: bucket.kind).count > 1
        else { return false }
        let usage = categoryUsage(id)
        return usage.entries == 0 && usage.caps == 0
            && usage.recurring == 0 && usage.challenges == 0
    }

    func deleteCategory(_ id: String) {
        guard canDeleteCategory(id),
              let bucket = categories.first(where: { $0.id == id }) else { return }
        offerUndo(.categoryDeleted(bucket), message: "Deleted \(bucket.label).")
        store.deleteCategory(id: id)
        reload()
    }

    /// Puts a built-in back to the label, colour, icon and cadence it shipped
    /// with. Its position and whether it's hidden are left alone — those are
    /// arrangement, not identity.
    func resetCategory(_ id: String) {
        guard let current = categories.first(where: { $0.id == id }),
              let seed = Bucket.builtIn(id) else { return }
        offerUndo(.categoryChanged(before: current), message: "Reset \(current.label).")
        store.saveCategory(Bucket(id: seed.id, label: seed.label, hex: seed.hex,
                                  light: seed.lightHex, symbol: seed.symbol,
                                  cadence: seed.cadence, kind: seed.kind,
                                  isHidden: current.isHidden, isBuiltIn: true,
                                  sortOrder: current.sortOrder))
        Haptics.saved()
        reload()
    }

    /// Applies a drag reorder within one direction's list.
    func moveCategories(for kind: EntryKind, from source: IndexSet, to destination: Int) {
        var visible = categories(for: kind)
        visible.move(fromOffsets: source, toOffset: destination)
        let renumbered = visible.enumerated().map { index, bucket in
            Bucket(id: bucket.id, label: bucket.label, hex: bucket.hex,
                   light: bucket.lightHex, symbol: bucket.symbol, cadence: bucket.cadence,
                   kind: bucket.kind, isHidden: bucket.isHidden,
                   isBuiltIn: bucket.isBuiltIn, sortOrder: index)
        }
        store.saveCategoryOrder(renumbered)
        Haptics.selected()
        reload()
    }

    // MARK: - Shortcuts

    /// A place the household logs often, with the amount it's usually for.
    struct PlaceShortcut: Identifiable {
        let place: String
        let bucket: Bucket
        let typicalAmount: Double
        var id: String { place }
    }

    /// The handful of places worth a one-tap button, most-logged first.
    ///
    /// Built from the household's own ledger rather than a canned list of
    /// "common purchases" — the whole value is that it says *Blue Bottle*, and a
    /// generic list never will. Needs two sightings before a place qualifies, so
    /// a one-off doesn't take up a slot.
    func frequentPlaces(for kind: EntryKind, limit: Int = 4) -> [PlaceShortcut] {
        var seen: [String: (count: Int, amounts: [Double], bucket: String, last: Date)] = [:]
        for entry in allEntries where entry.kind == kind && !entry.place.isEmpty {
            let key = entry.place.lowercased()
            var row = seen[key] ?? (0, [], entry.bucket, .distantPast)
            row.count += 1
            row.amounts.append(entry.amount)
            // Most recent sighting wins the category and the display spelling.
            if entry.createdAt > row.last {
                row.bucket = entry.bucket
                row.last = entry.createdAt
            }
            seen[key] = row
        }

        return seen
            .filter { $0.value.count >= 2 }
            .sorted {
                $0.value.count != $1.value.count ? $0.value.count > $1.value.count
                                                 : $0.value.last > $1.value.last
            }
            .prefix(limit)
            .map { key, row in
                PlaceShortcut(
                    place: displayName(for: key),
                    bucket: Bucket.named(row.bucket),
                    // Median, not mean: one big grocery run shouldn't drag the
                    // suggested amount away from what it usually is.
                    typicalAmount: median(row.amounts)
                )
            }
    }

    /// The most recent spelling the household actually used for a place.
    private func displayName(for lowercased: String) -> String {
        allEntries.first { $0.place.lowercased() == lowercased }?.place ?? lowercased
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// The last thing logged, for "same again".
    var lastEntry: Entry? { allEntries.first { !$0.isPrivate || $0.memberID == store.localMemberID } }

    /// Everyone *other than this device's owner* who has logged something
    /// today, in household order. Drives the presence line in the log.
    var othersActiveToday: [Member] {
        let me = store.localMemberID
        let active = Set(
            allEntries.filter { $0.date == today && $0.memberID != me }.map(\.memberID)
        )
        return members.filter { active.contains($0.id) }
    }

    // MARK: - Reactions

    /// Everyone's reactions to an entry, oldest first.
    func reactions(for entryID: String) -> [Reaction] { reactions[entryID] ?? [] }

    /// This device's own reaction to an entry, if any.
    func myReaction(to entryID: String) -> ReactionKind? {
        guard let me = store.localMemberID else { return nil }
        return reactions(for: entryID).first { $0.memberID == me }?.kind
    }

    /// Tapping the same reaction again clears it; a different one replaces it.
    func react(to entryID: String, with kind: ReactionKind) {
        guard let me = store.localMemberID else { return }
        Haptics.selected()
        store.toggleReaction(entryID: entryID, memberID: me, kind: kind)
        reload()
    }

    // MARK: - Sync

    /// Rebuilds the published mirrors from the persisted store, for whichever
    /// month is selected.
    func reload() {
        hasHousehold = store.hasHousehold
        // Anything due on or before today gets written before we read, so the
        // month's totals already include it.
        if hasHousehold, postDueRecurring() {
            reload()
            return
        }

        let snapshot = store.loadSnapshot(capsFor: monthKey)
        // The registry has to be current *before* anything below reads a
        // category — the digest classifies spending by cadence, and the wins
        // and insights that follow it both resolve buckets by id.
        CategoryRegistry.replace(with: snapshot.categories)
        categories = snapshot.categories
        caps = snapshot.caps
        recurring = snapshot.recurring
        loans = snapshot.loans
        challenges = ChallengeScorer.score(snapshot.challenges,
                                           entries: snapshot.entries, today: today)
        members = snapshot.members
        membersByID = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.id, $0) })
        reactions = snapshot.reactions
        monthFlags = snapshot.monthFlags
        isSampleHousehold = snapshot.isSample
        rolloverEnabled = snapshot.rolloverEnabled
        month = Self.digest(snapshot.entries,
                            month: monthKey,
                            previous: Fmt.isoMonth(Self.month(before: selectedMonth)))
        history = Self.history(snapshot.entries, endingAt: selectedMonth,
                               length: Self.historyLength)
        wins = buildWins(snapshot.entries)
        allEntries = snapshot.entries
        categorizer = HistoryCategorizer(entries: snapshot.entries)
        buildInsights(snapshot.entries)
        checkCapAlerts(snapshot.entries)
        // A tab that's just been hidden can't be left selected under the user.
        if !visibleTabs.contains(tab) { tab = .home }
        // Categories are user data, so the options behind the Siri/Shortcuts
        // category parameter move whenever they do.
        BudgetShortcuts.refresh()
    }

    // MARK: - Progressive disclosure

    /// Total entries the household has ever logged, across every month.
    var totalEntryCount: Int { allEntries.count }

    /// Whether any real spending limits have been set. Empty caps aren't a
    /// broken state — they're the starting state, since the app no longer asks
    /// for a budget before it will open.
    var hasPlan: Bool { caps.values.contains { $0 > 0 } }

    /// Tabs the user has explicitly asked for before they'd earned their place
    /// in the bar. Once revealed, a tab stays put — having it vanish again
    /// under someone who just used it would be worse than never hiding it.
    @Published private(set) var revealedTabs: Set<Tab> = []

    /// Which tabs the bottom bar shows. Budget and Stats stay out of the way
    /// until there's something in them worth opening; both are still reachable
    /// from Home before that, so nothing is actually locked away.
    ///
    /// They arrive as a pair, never one at a time, and that's a layout
    /// constraint as much as a product one. The bar carves a centred gap for
    /// the add button, and with an odd number of tabs an evenly spaced row and
    /// a centred gap are mutually exclusive — three tabs either strand one
    /// against the edge or push the button off centre. All-or-nothing keeps the
    /// bar at two tabs or four. `BottomBar` depends on that being true.
    var visibleTabs: [Tab] {
        [.home, .log] + (showsFullBar ? [.budget, .stats] : [])
    }

    /// Whether the household has earned the second pair of tabs. The threshold
    /// is the later of the two the pair used to have separately — a Stats tab
    /// over three entries is a chart of nothing — so Budget now waits for it
    /// too. Nothing is lost by that: Home links straight into Budget until
    /// then, and taking that link reveals the pair.
    private var showsFullBar: Bool {
        totalEntryCount >= 5 || !revealedTabs.isEmpty
    }

    /// Opens a tab that isn't in the bar yet, and keeps it there.
    func reveal(_ tab: Tab) {
        revealedTabs.insert(tab)
        self.tab = tab
    }

    /// Forecast, suggestions and subscription detection. Like wins, these always
    /// describe the live month — advice about a month that already ended is just
    /// noise.
    private func buildInsights(_ entries: [Entry]) {
        let currentKey = Fmt.isoMonth(Date())
        let current = isCurrentMonth ? month : Self.digest(entries, month: currentKey, previous: "")
        let limits = isCurrentMonth ? caps : store.caps(for: currentKey)
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
        let today = calendar.component(.day, from: Date())

        forecast = Forecast.make(
            spent: current.spent, byDay: current.byDay, today: today,
            daysInMonth: daysInMonth, plan: limits.values.reduce(0, +),
            recurring: recurring, currentMonthKey: currentKey
        )

        suggestions = suggestionEngine.suggestions(for: SuggestionInput(
            forecast: forecast,
            ranked: current.ranked,
            caps: limits,
            daysLeft: max(0, daysInMonth - today),
            moods: current.byMood,
            savingsCap: limits["savings"] ?? 0,
            savingsSpent: current.totals["savings"] ?? 0
        ))

        subscriptions = SubscriptionDetective.detect(
            entries: entries, recurring: recurring, today: Date()
        )
    }

    /// Streaks and badges always describe the live month, whichever month is
    /// being browsed — a win isn't something you scroll back to.
    private func buildWins(_ entries: [Entry]) -> Wins {
        let currentKey = Fmt.isoMonth(Date())
        let current = isCurrentMonth
            ? month
            : Self.digest(entries, month: currentKey, previous: "")

        // Each closed month judged against the caps that were in force then,
        // oldest first. The live month is excluded: it hasn't finished. Months
        // the household flagged as strange are excluded too — a run of good
        // months shouldn't be ended by the one they moved house in.
        let closed: [(spent: Double, cap: Double)] = history
            .filter { $0.key < currentKey && !isUnusual($0.key) }
            .map { ($0.spent, store.caps(for: $0.key).values.reduce(0, +)) }

        let expenses = entries.filter { $0.kind == .expense }
        return Wins.make(
            byDay: current.byDay,
            dailyAllowance: dailyAllowance,
            today: Calendar.current.component(.day, from: Date()),
            entryCount: entries.count,
            taggedCount: expenses.filter { $0.mood != nil }.count,
            closedMonths: closed
        )
    }

    // MARK: - Challenges

    var activeChallenges: [ChallengeProgress] { challenges.filter(\.isActive) }
    var finishedChallenges: [ChallengeProgress] { challenges.filter(\.hasEnded) }

    /// The one worth a line on the home screen: whatever's running now.
    var featuredChallenge: ChallengeProgress? { activeChallenges.first }

    func startChallenge(_ challenge: Challenge) {
        store.saveChallenge(challenge)
        reload()
    }

    func abandonChallenge(_ id: String) {
        store.deleteChallenge(id: id)
        reload()
    }

    // MARK: - Questions

    /// Answers against the live month's caps and the whole ledger. `nil` means
    /// the question wasn't understood — the caller shows what it can handle.
    func ask(_ question: String) -> QueryAnswer? {
        queryEngine.answer(question, context: QueryContext(
            entries: allEntries,
            caps: store.caps(for: Fmt.isoMonth(Date())),
            members: members,
            today: Date()
        ))
    }

    // MARK: - Loans

    var totalOwed: Double { loans.reduce(0) { $0 + $1.balance } }
    var monthlyLoanPayments: Double { loans.reduce(0) { $0 + $1.monthlyPayment } }

    func saveLoan(_ loan: Loan) {
        store.saveLoan(loan)
        reload()
    }

    func deleteLoan(_ id: String) {
        if let loan = loans.first(where: { $0.id == id }) {
            offerUndo(.deletedLoan(loan), message: "Removed \(loan.name).")
        }
        store.deleteLoan(id: id)
        reload()
    }

    // MARK: - Recurring

    func saveRecurring(_ item: Recurring) {
        store.saveRecurring(item)
        reload()
        Notifier.shared.scheduleBillReminders(recurring)
    }

    func deleteRecurring(_ id: String) {
        if let item = recurring.first(where: { $0.id == id }) {
            offerUndo(.deletedRecurring(item), message: "Removed \(item.place).")
        }
        store.deleteRecurring(id: id)
        reload()
        Notifier.shared.scheduleBillReminders(recurring)
    }

    /// Posts an entry for every active item whose day has arrived this month and
    /// that hasn't posted yet. Returns whether anything was written, so the
    /// caller knows to re-read. Idempotent: `lastPostedMonth` is the guard, so
    /// relaunching mid-month doesn't duplicate rent.
    private func postDueRecurring() -> Bool {
        let currentKey = Fmt.isoMonth(Date())
        let dayToday = Calendar.current.component(.day, from: Date())
        var posted = false

        for var item in store.loadRecurringForCurrentHousehold() {
            guard item.isActive,
                  item.lastPostedMonth != currentKey,
                  item.dayOfMonth <= dayToday else { continue }

            store.addEntry(id: UUID().uuidString,
                           date: "\(currentKey)-\(String(format: "%02d", item.dayOfMonth))",
                           place: item.place, amount: item.amount, bucket: item.bucket,
                           memberID: item.memberID, kind: item.kind)
            item.lastPostedMonth = currentKey
            store.saveRecurring(item)
            posted = true
        }
        return posted
    }

    /// Cap alerts always judge the *live* month, even while the user is looking
    /// at an earlier one — otherwise browsing history would mute them.
    private func checkCapAlerts(_ entries: [Entry]) {
        let currentKey = Fmt.isoMonth(Date())
        let totals = isCurrentMonth
            ? month.totals
            : Self.digest(entries, month: currentKey, previous: "").totals
        let limits = isCurrentMonth ? caps : store.caps(for: currentKey)
        Notifier.shared.checkCaps(totals: totals, caps: limits, month: currentKey)
    }

    /// Totals per month for the trend chart, oldest first. Months with nothing
    /// in them still get a point, so the gaps in a household's habits show.
    private static func history(_ entries: [Entry], endingAt end: Date,
                                length: Int) -> [MonthPoint] {
        var spent: [String: Double] = [:]
        var earned: [String: Double] = [:]
        for entry in entries {
            let key = String(entry.date.prefix(7))
            if entry.kind == .income { earned[key, default: 0] += entry.amount }
            else { spent[key, default: 0] += entry.amount }
        }

        let calendar = Calendar.current
        return (0..<length).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: end)
            else { return nil }
            let key = Fmt.isoMonth(date)
            return MonthPoint(key: key, label: Fmt.shortMonth(date),
                              spent: spent[key] ?? 0, earned: earned[key] ?? 0)
        }
    }

    /// Splits the store's (already sorted) entries into this month and last, and
    /// accumulates every total in a single pass. Income is tallied separately at
    /// every step — it belongs in neither the spending totals nor the charts.
    private static func digest(_ entries: [Entry], month: String, previous: String) -> MonthDigest {
        var digest = MonthDigest()
        digest.entries.reserveCapacity(entries.count)
        var incomeTotals: [String: Double] = [:]
        var moodTotals: [Mood: (amount: Double, count: Int)] = [:]

        for entry in entries {
            if entry.date.hasPrefix(month) {
                digest.entries.append(entry)
                guard entry.kind == .expense else {
                    digest.earned += entry.amount
                    incomeTotals[entry.bucket, default: 0] += entry.amount
                    continue
                }
                // Below-the-line spending is held apart from everything the
                // plan is measured with: the month's total, the category
                // breakdown, the fun-money figure and the per-day numbers the
                // streak is built from. A laptop bought once shouldn't read as
                // a blown budget, and it definitely shouldn't end a streak.
                guard !entry.belowTheLine else {
                    digest.belowTheLine += entry.amount
                    digest.belowTheLineCount += 1
                    continue
                }
                digest.spent += entry.amount
                digest.totals[entry.bucket, default: 0] += entry.amount
                digest.byMember[entry.memberID, default: 0] += entry.amount
                if Bucket.named(entry.bucket).cadence == .variable {
                    digest.discretionarySpent += entry.amount
                }
                if let day = Int(entry.date.suffix(2)) {
                    digest.byDay[day, default: 0] += entry.amount
                }
                if let mood = entry.mood {
                    digest.moodTagged += entry.amount
                    let current = moodTotals[mood] ?? (0, 0)
                    moodTotals[mood] = (current.amount + entry.amount, current.count + 1)
                }
            } else if entry.date.hasPrefix(previous), entry.kind == .expense,
                      !entry.belowTheLine {
                // Same exclusion as the current month, or the comparison would
                // be measuring two different things against each other.
                digest.previousSpent += entry.amount
            }
        }

        // Ranked from *every* category, hidden included. A hidden category's
        // past spending still counts toward `spent`, so leaving it out of the
        // breakdown would show a total that its own parts don't add up to.
        let everything = CategoryRegistry.allIncludingHidden
        digest.ranked = rank(everything.filter { $0.kind == .expense }, by: digest.totals)
        digest.incomeRanked = rank(everything.filter { $0.kind == .income }, by: incomeTotals)
        digest.byMood = moodTotals
            .map { MoodTotal(mood: $0.key, total: $0.value.amount, count: $0.value.count) }
            .sorted { $0.total > $1.total }
        return digest
    }

    private static func rank(_ buckets: [Bucket], by totals: [String: Double]) -> [BucketTotal] {
        buckets
            .compactMap { bucket in
                guard let total = totals[bucket.id], total > 0 else { return nil }
                return BucketTotal(bucket: bucket, total: total)
            }
            .sorted { $0.total > $1.total }
    }
}

// MARK: - Demo data (previews / design work)

extension AppModel {
    /// An in-memory model seeded with sample data, for SwiftUI previews and
    /// design work. Never touches disk or CloudKit.
    static var preview: AppModel {
        let store = BudgetStore(inMemory: true)
        store.createHousehold(name: "Together", ownerName: "You", defaultCaps: defaultCaps)
        // The creator is member 0; the rest of the sample household follows.
        var ids = store.loadSnapshot().members.map(\.id)
        for (index, name) in ["Sam", "Alex"].enumerated() {
            if let member = store.addMember(name: name, colorIndex: index + 1) {
                ids.append(member.id)
            }
        }
        for entry in demoEntries {
            // `memberID` holds the seat index until there are real ids to use.
            let seat = Int(entry.memberID) ?? 0
            store.addEntry(id: entry.id, date: entry.date, place: entry.place,
                           amount: entry.amount, bucket: entry.bucket,
                           memberID: ids[seat % max(ids.count, 1)], kind: entry.kind,
                           mood: entry.mood)
        }
        // Already marked as posted this month, so the demo entries above aren't
        // duplicated the moment the model loads.
        let thisMonth = Fmt.isoMonth(Date())
        let bills: [(String, Double, String, EntryKind, Int, Int)] = [
            ("Rent",    1200,  "housing", .expense, 1, 1),
            ("Netflix", 15.99, "subs",    .expense, 2, 1),
            ("Payroll", 2400,  "salary",  .income,  1, 0),
        ]
        for (place, amount, bucket, kind, day, seat) in bills {
            store.saveRecurring(Recurring(
                id: "demo-rec-\(place)", place: place, amount: amount, bucket: bucket,
                memberID: ids[seat % max(ids.count, 1)], kind: kind,
                dayOfMonth: day, isActive: true, lastPostedMonth: thisMonth
            ))
        }
        // One running, one already finished, so both states are visible.
        let calendar = Calendar.current
        let from = { (offset: Int) in
            Fmt.isoDay(calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        }
        store.saveChallenge(Challenge(id: "demo-ch-1", title: "Quiet Week Out",
                                      kind: .categoryCap, bucket: "fun", target: 250,
                                      startDate: from(-3), endDate: from(3), createdAt: Date()))
        store.saveChallenge(Challenge(id: "demo-ch-2", title: "No-Spend Weekend",
                                      kind: .noSpend, bucket: nil, target: 0,
                                      startDate: from(-9), endDate: from(-8), createdAt: Date()))

        store.saveLoan(Loan(id: "demo-loan-1", name: "Student loan", balance: 18400,
                            rate: 6.5, monthlyPayment: 260, createdAt: Date()))
        store.saveLoan(Loan(id: "demo-loan-2", name: "Credit card", balance: 1250,
                            rate: 21.9, monthlyPayment: 90, createdAt: Date()))
        return AppModel(store: store)
    }

    /// Sample spending, dated relative to *this* month so previews keep working
    /// as time passes. `memberID` carries a seat index (0 = you) that `preview`
    /// swaps for the real member ids. A few last-month rows give the header
    /// comparison something to render.
    static let demoEntries: [Entry] = {
        let sample: [(day: Int, place: String, bucket: String, amount: Double, seat: Int)] = [
            (1,  "Rent",            "housing",   1200,  1),
            (2,  "Netflix",         "subs",      15.99, 1),
            (2,  "Spotify",         "subs",      11.99, 0),
            (3,  "Trader Joe's",    "food",      92.4,  0),
            (4,  "Shell",           "transport", 48.2,  2),
            (5,  "Chipotle",        "food",      26,    1),
            (6,  "Target",          "shopping",  82.15, 0),
            (8,  "Concert tickets", "fun",       140,   2),
            (9,  "Pharmacy",        "personal",  34.5,  0),
            (11, "Gym",             "personal",  45,    2),
            (12, "Groceries",       "food",      76.3,  0),
            (13, "Blue Bottle",     "food",      19,    0),
            (14, "Dinner out",      "fun",       68,    1),
            (15, "Amazon",          "shopping",  54.2,  1),
            (16, "Parking",         "transport", 18,    2),
        ]

        let now = Date()
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now

        // Most entries untagged, which is the honest case — tagging is optional
        // and people do it when something felt worth noting.
        let tags: [Int: Mood] = [
            3: .routine, 5: .stress, 6: .boredom, 7: .joy,
            10: .routine, 13: .social, 14: .stress, 12: .boredom,
        ]
        // A few notes, because the feature is invisible until someone has seen
        // one — and the "why" is the whole reason the field exists.
        let notes: [Int: String] = [
            7:  "Birthday present for Alex — don't look 🙈",
            13: "Anniversary. Worth every penny.",
            9:  "Prescription refill",
        ]
        var entries = sample.enumerated().map { index, row in
            Entry(id: "demo-\(index)", date: day(row.day, of: now), place: row.place,
                  bucket: row.bucket, amount: row.amount, memberID: "\(row.seat)",
                  mood: tags[index], note: notes[index] ?? "",
                  createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        // Money in, so the income and net figures have something to show.
        let paydays: [(day: Int, place: String, bucket: String, amount: Double, seat: Int)] = [
            (1,  "Payroll",       "salary",    2400, 0),
            (1,  "Payroll",       "salary",    1950, 1),
            (7,  "Index fund",    "dividends", 128,  0),
            (12, "Birthday card", "gifts",     100,  2),
        ]
        entries += paydays.enumerated().map { index, row in
            Entry(id: "demo-in-\(index)", date: day(row.day, of: now), place: row.place,
                  bucket: row.bucket, amount: row.amount, memberID: "\(row.seat)",
                  kind: .income, createdAt: Date(timeIntervalSince1970: Double(100 + index)))
        }
        // Last month, slightly higher, so the home header shows a decrease.
        entries += [
            Entry(id: "demo-prev-0", date: day(3, of: lastMonth), place: "Rent",
                  bucket: "housing", amount: 1200, memberID: "1",
                  createdAt: .distantPast),
            Entry(id: "demo-prev-1", date: day(12, of: lastMonth), place: "Groceries",
                  bucket: "food", amount: 480, memberID: "0",
                  createdAt: .distantPast),
        ]

        // Coarse earlier months, so the trend chart and month stepping have
        // history to show. One rent-sized expense and one payday each.
        let earlier: [(back: Int, spent: Double, earned: Double)] = [
            (2, 2380, 4100), (3, 1870, 4100), (4, 2540, 4350), (5, 2020, 4100),
        ]
        for row in earlier {
            guard let date = calendar.date(byAdding: .month, value: -row.back, to: now)
            else { continue }
            entries += [
                Entry(id: "demo-hist-\(row.back)-out", date: day(6, of: date),
                      place: "Monthly costs", bucket: "housing", amount: row.spent,
                      memberID: "0", createdAt: .distantPast),
                Entry(id: "demo-hist-\(row.back)-in", date: day(1, of: date),
                      place: "Payroll", bucket: "salary", amount: row.earned,
                      memberID: "0", kind: .income, createdAt: .distantPast),
                // Same charge, same amount, month after month — what the
                // subscription detective is looking for.
                Entry(id: "demo-hist-\(row.back)-sub", date: day(2, of: date),
                      place: "Netflix", bucket: "subs", amount: 15.99,
                      memberID: "1", createdAt: .distantPast),
                // And one that quietly stopped being used.
                Entry(id: "demo-hist-\(row.back)-gym", date: day(4, of: date),
                      place: "Gym membership", bucket: "personal", amount: 29,
                      memberID: "2", createdAt: .distantPast),
            ]
        }
        return entries
    }()

    /// Clamps `day` into the month containing `reference` and renders a storage
    /// date key for it.
    private static func day(_ day: Int, of reference: Date) -> String {
        let cal = Calendar.current
        let span = cal.range(of: .day, in: .month, for: reference)?.count ?? 28
        var parts = cal.dateComponents([.year, .month], from: reference)
        parts.day = min(day, span)
        return Fmt.isoDay(cal.date(from: parts) ?? reference)
    }
}
