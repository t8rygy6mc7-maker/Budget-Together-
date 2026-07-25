import Combine
import SwiftUI

/// Everything the screens derive from the current month's entries, computed in
/// one pass whenever the data changes. Previously each of these was a computed
/// property that re-scanned every entry on every SwiftUI body evaluation.
struct MonthDigest {
    /// This month's entries, newest first.
    var entries: [Entry] = []
    /// Bucket id → amount spent. Buckets with no spending are absent.
    var totals: [String: Double] = [:]
    /// Buckets with spending, biggest first — drives the bubbles and charts.
    var ranked: [BucketTotal] = []
    var spent: Double = 0
    /// `Member.id` → amount spent.
    var byMember: [String: Double] = [:]
    /// Same-scope total for the previous month, for the header comparison.
    var previousSpent: Double = 0
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

    var today: String { Fmt.isoDay(Date()) }
    var monthTitle: String { Fmt.monthTitle(Date()) }
    var previousMonthName: String { Fmt.monthName(Self.previousMonth) }

    var daysLeft: Int {
        let cal = Calendar.current
        let now = Date()
        let total = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        return max(1, total - cal.component(.day, from: now))
    }

    private static var previousMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    // MARK: - Derived values

    var spent: Double { month.spent }
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
                self.store.setCap(bucket: id, amount: newValue)
            }
        )
    }

    func addEntry(place: String, amount: Double, bucket: String, memberID: String) {
        store.addEntry(id: UUID().uuidString, date: today, place: place,
                       amount: amount, bucket: bucket, memberID: memberID)
        reload()
    }

    func delete(_ id: String) {
        store.delete(id: id)
        reload()
    }

    // MARK: - Sync

    /// Rebuilds the published mirrors from the persisted store.
    func reload() {
        hasHousehold = store.hasHousehold
        let snapshot = store.loadSnapshot()
        caps = snapshot.caps
        members = snapshot.members
        membersByID = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.id, $0) })
        month = Self.digest(snapshot.entries,
                            month: Fmt.isoMonth(Date()),
                            previous: Fmt.isoMonth(Self.previousMonth))
    }

    /// Splits the store's (already sorted) entries into this month and last, and
    /// accumulates every total in a single pass.
    private static func digest(_ entries: [Entry], month: String, previous: String) -> MonthDigest {
        var digest = MonthDigest()
        digest.entries.reserveCapacity(entries.count)

        for entry in entries {
            if entry.date.hasPrefix(month) {
                digest.entries.append(entry)
                digest.spent += entry.amount
                digest.totals[entry.bucket, default: 0] += entry.amount
                digest.byMember[entry.memberID, default: 0] += entry.amount
            } else if entry.date.hasPrefix(previous) {
                digest.previousSpent += entry.amount
            }
        }

        digest.ranked = Bucket.all
            .compactMap { bucket in
                guard let total = digest.totals[bucket.id], total > 0 else { return nil }
                return BucketTotal(bucket: bucket, total: total)
            }
            .sorted { $0.total > $1.total }

        return digest
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
                           memberID: ids[seat % max(ids.count, 1)])
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
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now

        var entries = sample.enumerated().map { index, row in
            Entry(id: "demo-\(index)", date: day(row.day, of: now), place: row.place,
                  bucket: row.bucket, amount: row.amount, memberID: "\(row.seat)",
                  createdAt: Date(timeIntervalSince1970: Double(index)))
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
