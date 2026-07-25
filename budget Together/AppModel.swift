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
    /// Totals for the months leading up to `selectedMonth`, oldest first.
    @Published private(set) var history: [MonthPoint] = []
    /// Whether this device has joined/created a household yet. Drives the
    /// pairing gate in `RootView`.
    @Published private(set) var hasHousehold = false

    private let store: BudgetStore
    private var membersByID: [String: Member] = [:]

    /// Caps used to seed a freshly created household.
    static let defaultCaps: [String: Double] = [
        "housing": 1300, "food": 500, "transport": 250, "fun": 200,
        "shopping": 250, "personal": 150, "subs": 60, "savings": 400,
    ]

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
    func createHousehold(name: String, ownerName: String = "You") {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let owner = ownerName.trimmingCharacters(in: .whitespaces)
        store.createHousehold(name: trimmed.isEmpty ? "Together" : trimmed,
                              ownerName: owner.isEmpty ? "You" : owner,
                              defaultCaps: Self.defaultCaps)
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
                  memberID: String, kind: EntryKind = .expense) {
        store.addEntry(id: UUID().uuidString, date: today, place: place,
                       amount: amount, bucket: bucket, memberID: memberID, kind: kind)
        reload()
    }

    func updateEntry(_ entry: Entry, place: String, amount: Double, bucket: String,
                     memberID: String, kind: EntryKind) {
        store.updateEntry(id: entry.id, date: entry.date, place: place, amount: amount,
                          bucket: bucket, memberID: memberID, kind: kind)
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
        members = snapshot.members
        membersByID = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.id, $0) })
        month = Self.digest(snapshot.entries,
                            month: monthKey,
                            previous: Fmt.isoMonth(Self.month(before: selectedMonth)))
        history = Self.history(snapshot.entries, endingAt: selectedMonth,
                               length: Self.historyLength)
        checkCapAlerts(snapshot.entries)
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
            } else if entry.date.hasPrefix(previous), entry.kind == .expense {
                digest.previousSpent += entry.amount
            }
        }

        digest.ranked = rank(Bucket.all, by: digest.totals)
        digest.incomeRanked = rank(Bucket.income, by: incomeTotals)
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
                           memberID: ids[seat % max(ids.count, 1)], kind: entry.kind)
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

        var entries = sample.enumerated().map { index, row in
            Entry(id: "demo-\(index)", date: day(row.day, of: now), place: row.place,
                  bucket: row.bucket, amount: row.amount, memberID: "\(row.seat)",
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
