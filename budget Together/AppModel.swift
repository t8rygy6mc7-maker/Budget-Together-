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
    func createHousehold(name: String, ownerName: String = "You",
                         monthlyTotal: Double? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let owner = ownerName.trimmingCharacters(in: .whitespaces)
        store.createHousehold(name: trimmed.isEmpty ? "Together" : trimmed,
                              ownerName: owner.isEmpty ? "You" : owner,
                              defaultCaps: monthlyTotal.map(Self.caps(forMonthlyTotal:))
                                           ?? Self.defaultCaps)
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
    /// the confirmation dialog warns with.
    func removeMember(_ id: String) {
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
        Bucket.all
            .filter { $0.cadence == .fixed }
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
    var left: Double { max(0, capTotal - spent) }
    var safeDaily: Double { left / Double(daysLeft) }

    func spent(by memberID: String) -> Double { month.byMember[memberID] ?? 0 }

    /// Change in spending against the previous month. `nil` when there's nothing
    /// to compare against, so the header can omit the badge rather than show a
    /// meaningless figure.
    var monthOverMonth: (percent: Int, isDown: Bool)? {
        let previous = month.previousSpent
        guard previous > 0 else { return nil }
        let change = Int((((month.spent - previous) / previous) * 100).rounded())
        guard change != 0 else { return nil }
        return (abs(change), change < 0)
    }

    // MARK: - Bindings & mutations (write through to the store)

    func capBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { self.caps[id] ?? 0 },
            set: { newValue in
                self.caps[id] = newValue            // optimistic UI update
                self.store.setCap(bucket: id, month: self.monthKey, amount: newValue)
                // A new limit deserves a fresh judgement — raising a cap should
                // let the 80% warning fire again against the new headroom.
                Notifier.shared.resetCapAlerts(bucketID: id, month: self.monthKey)
            }
        )
    }

    func addEntry(place: String, amount: Double, bucket: String,
                  memberID: String, kind: EntryKind = .expense, mood: Mood? = nil,
                  isPrivate: Bool = false) {
        store.addEntry(id: UUID().uuidString, date: today, place: place,
                       amount: amount, bucket: bucket, memberID: memberID,
                       kind: kind, mood: mood, isPrivate: isPrivate)
        reload()
    }

    func updateEntry(_ entry: Entry, place: String, amount: Double, bucket: String,
                     memberID: String, kind: EntryKind, mood: Mood?, isPrivate: Bool) {
        store.updateEntry(id: entry.id, date: entry.date, place: place, amount: amount,
                          bucket: bucket, memberID: memberID, kind: kind, mood: mood,
                          isPrivate: isPrivate)
        reload()
    }

    func delete(_ id: String) {
        store.delete(id: id)
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
        caps = snapshot.caps
        recurring = snapshot.recurring
        loans = snapshot.loans
        challenges = ChallengeScorer.score(snapshot.challenges,
                                           entries: snapshot.entries, today: today)
        members = snapshot.members
        membersByID = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.id, $0) })
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
        // oldest first. The live month is excluded: it hasn't finished.
        let closed: [(spent: Double, cap: Double)] = history
            .filter { $0.key < currentKey }
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
            } else if entry.date.hasPrefix(previous), entry.kind == .expense {
                digest.previousSpent += entry.amount
            }
        }

        digest.ranked = rank(Bucket.all, by: digest.totals)
        digest.incomeRanked = rank(Bucket.income, by: incomeTotals)
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
        var entries = sample.enumerated().map { index, row in
            Entry(id: "demo-\(index)", date: day(row.day, of: now), place: row.place,
                  bucket: row.bucket, amount: row.amount, memberID: "\(row.seat)",
                  mood: tags[index],
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
