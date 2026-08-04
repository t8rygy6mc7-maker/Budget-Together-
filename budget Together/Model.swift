import SwiftUI

// MARK: - People

/// Avatar colours, in the order new people are assigned them. A household can
/// hold more people than there are entries here — `at(_:)` wraps, so the palette
/// never runs out and every member always renders.
struct MemberStyle {
    let color: Color
    let ink: Color

    /// Dark mode gives each person a pale avatar with dark ink; light mode
    /// inverts that — the same hue, deep enough to clear AA on a white card,
    /// carrying white ink. The hue is what identifies the person, so it is the
    /// one thing that never moves.
    init(_ hex: String, ink: String, light: String) {
        self.color = Color(dark: hex, light: light)
        self.ink = Color(dark: ink, light: "FFFFFF")
    }

    static let all: [MemberStyle] = [
        MemberStyle("5EEAD4", ink: "0C2B26", light: "107F6E"),   // teal
        MemberStyle("C69BFF", ink: "2A1740", light: "390085"),   // purple
        MemberStyle("F5C15E", ink: "3A2A08", light: "98670A"),   // amber
        MemberStyle("FF9FB2", ink: "40121E", light: "99001E"),   // rose
        MemberStyle("7FB2FF", ink: "0E2445", light: "0048B6"),   // blue
        MemberStyle("A8E063", ink: "1D3208", light: "507C19"),   // lime
        MemberStyle("FFAE7B", ink: "40200C", light: "B94800"),   // orange
        MemberStyle("6EE7F5", ink: "06303A", light: "0A7C89"),   // cyan
    ]

    /// Grey, for an entry whose member no longer exists (deleted on the
    /// partner's device before that deletion reached us).
    static let unknown = MemberStyle("5A6076", ink: "EDEFF7", light: "687089")

    static func at(_ index: Int) -> MemberStyle {
        guard index >= 0 else { return all[0] }
        return all[index % all.count]
    }
}

/// A person sharing the budget. Households start with one — whoever set it up —
/// and any number can be added afterwards.
struct Member: Identifiable, Hashable {
    let id: String
    var name: String
    /// Index into `MemberStyle.all`, wrapped when it runs past the end.
    var colorIndex: Int
    var createdAt: Date
    /// The iCloud account sitting in this seat, once someone has claimed it.
    /// `nil` means the seat is a name on a list and nothing more — which is
    /// every seat in a household nobody has been invited into.
    var userRecordName: String?

    /// Whether somebody's phone is actually behind this name.
    var isClaimed: Bool { !(userRecordName ?? "").isEmpty }

    private var style: MemberStyle {
        id.isEmpty ? MemberStyle.unknown : MemberStyle.at(colorIndex)
    }

    var color: Color { style.color }
    var ink: Color { style.ink }

    /// Avatar glyph: the first letter of the name, uppercased.
    var letter: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : trimmed.prefix(1).uppercased()
    }

    /// Stand-in for an entry pointing at a member we don't have a row for.
    static let unknown = Member(id: "", name: "Someone", colorIndex: 0, createdAt: .distantPast)
}

/// A member paired with what they've spent, for the split bar and its legend.
struct MemberTotal: Identifiable {
    let member: Member
    let total: Double
    var id: String { member.id }
}

// MARK: - Money direction

/// Which way the money moved. Everything that totals, ranks or charts spending
/// filters on this — income must never read as an expense.
enum EntryKind: String, CaseIterable, Hashable {
    case expense, income

    var label: String { self == .income ? "Income" : "Spending" }
    /// Prefix for an amount, so a row's direction survives without colour.
    var sign: String { self == .income ? "+" : "" }
    var color: Color { self == .income ? Palette.green : Palette.text }
}

// MARK: - Feeling behind the spend

/// Why the money went, as opposed to where. Optional on every entry — the tag
/// is only useful if it's honest, and forcing one would guarantee noise.
enum Mood: String, CaseIterable, Identifiable {
    case joy, stress, boredom, routine, social, regret

    var id: String { rawValue }

    var label: String {
        switch self {
        case .joy:     "Joy"
        case .stress:  "Stress"
        case .boredom: "Boredom"
        case .routine: "Routine"
        case .social:  "Social"
        case .regret:  "Regret"
        }
    }

    var symbol: String {
        switch self {
        case .joy:     "sun.max.fill"
        case .stress:  "bolt.fill"
        case .boredom: "cloud.fill"
        case .routine: "clock.fill"
        case .social:  "person.2.fill"
        case .regret:  "arrow.uturn.left"
        }
    }

    var color: Color {
        switch self {
        case .joy:     Palette.moodJoy
        case .stress:  Palette.moodStress
        case .boredom: Palette.moodBoredom
        case .routine: Palette.moodRoutine
        case .social:  Palette.moodSocial
        case .regret:  Palette.moodRegret
        }
    }

    /// Moods worth surfacing as a prompt to reflect on. Joy and social spending
    /// aren't problems to be solved.
    var isWorthNoticing: Bool {
        self == .stress || self == .boredom || self == .regret
    }
}

/// A mood paired with what was spent while feeling it.
struct MoodTotal: Identifiable {
    let mood: Mood
    let total: Double
    let count: Int
    var id: String { mood.rawValue }
}

// MARK: - Spending buckets

/// Whether a category is a standing commitment or discretionary. Anti-budget
/// mode leans on this: obligations are handled, the rest is yours to spend.
enum Cadence: String, CaseIterable, Identifiable {
    case fixed, variable

    var id: String { rawValue }

    var label: String { self == .fixed ? "A fixed bill" : "Varies" }

    var detail: String {
        switch self {
        case .fixed:    "Same every month — rent, a subscription, a transfer to savings."
        case .variable: "Changes month to month — the day-to-day spending."
        }
    }

    /// Fixed categories are treated as already handled rather than as money
    /// you're deciding about, which is the whole premise of the simplified view.
    var symbol: String { self == .fixed ? "lock.fill" : "chart.line.uptrend.xyaxis" }
}

struct Bucket: Identifiable, Equatable {
    let id: String
    let label: String
    let symbol: String
    /// Resolved when the category is built, not per read — `Color(hex:)` runs a
    /// `Scanner`, which is far too expensive to repeat on every SwiftUI body
    /// evaluation. The dynamic pair is likewise built once; resolving it per
    /// scheme is a trait lookup. Categories are rebuilt only when the stored
    /// set actually changes, so this stays a startup-ish cost.
    let color: Color
    let tint: Color
    /// Halo under a bubble. A bright bloom on a dark screen becomes a heavy
    /// smear on a light one, so the light scheme drops it to a hint.
    let glow: Color
    /// First word of `label`, for tight spots like bubbles and category chips.
    let short: String
    let cadence: Cadence
    /// Which direction this category belongs to. Spending and income are
    /// separate lists that share no ids.
    let kind: EntryKind
    /// Hidden categories keep every entry ever filed under them and still
    /// resolve for display — they just stop being offered as a choice.
    let isHidden: Bool
    /// Whether this shipped with the app. Built-ins can be edited like any
    /// other, but they can also be reset, and their ids are the ones the
    /// keyword categoriser and the demo data refer to.
    let isBuiltIn: Bool
    let sortOrder: Int

    /// The dark-scheme fill and its light-scheme counterpart, kept together so
    /// a category can be round-tripped through storage.
    let hex: String
    let lightHex: String

    /// `hex` is the dark-scheme fill, `light` its light-scheme counterpart at
    /// the same hue. Fill encodes identity in both schemes — see DESIGN-NOTES §1.
    init(id: String, label: String, hex: String, light: String,
         symbol: String, cadence: Cadence = .variable, kind: EntryKind = .expense,
         isHidden: Bool = false, isBuiltIn: Bool = true, sortOrder: Int = 0) {
        let color = Color(dark: hex, light: light)
        self.glow = Color(dark: hex, darkAlpha: 0.65, light: light, lightAlpha: 0.26)
        self.id = id
        self.label = label
        self.symbol = symbol
        self.color = color
        self.tint = color.opacity(0.16)
        self.short = String(label.split(separator: " ").first ?? "")
        self.cadence = cadence
        self.kind = kind
        self.isHidden = isHidden
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.hex = hex
        self.lightHex = light
    }

    static func == (a: Bucket, b: Bucket) -> Bool {
        a.id == b.id && a.label == b.label && a.symbol == b.symbol
            && a.hex == b.hex && a.lightHex == b.lightHex && a.cadence == b.cadence
            && a.kind == b.kind && a.isHidden == b.isHidden && a.sortOrder == b.sortOrder
    }
}

// MARK: Built-in seeds

extension Bucket {
    /// The categories a new budget starts with. These are *seeds*, not the live
    /// list: they're written into storage on first run and are editable from
    /// then on, so nothing outside this array should assume they still say what
    /// they say here. Their ids are permanent, though — every stored entry,
    /// cap, recurring item and challenge refers to a category by id.
    static let builtInExpense: [Bucket] = [
        Bucket(id: "housing",   label: "Housing",       hex: "E86A4A", light: "BC3918", symbol: "house.fill", cadence: .fixed, sortOrder: 0),
        Bucket(id: "food",      label: "Food & Drink",  hex: "3FB984", light: "2B7E5A", symbol: "fork.knife", sortOrder: 1),
        Bucket(id: "transport", label: "Transport",     hex: "5B8DEF", light: "1147B0", symbol: "car.fill", sortOrder: 2),
        Bucket(id: "fun",       label: "Fun & Misc",    hex: "D45C87", light: "A82C59", symbol: "party.popper.fill", sortOrder: 3),
        Bucket(id: "shopping",  label: "Shopping",      hex: "E0C05B", light: "886D1A", symbol: "bag.fill", sortOrder: 4),
        Bucket(id: "personal",  label: "Health",        hex: "F6A5C8", light: "790C3B", symbol: "heart.fill", sortOrder: 5),
        Bucket(id: "subs",      label: "Subscriptions", hex: "C69BFF", light: "390085", symbol: "repeat", cadence: .fixed, sortOrder: 6),
        Bucket(id: "savings",   label: "Savings",       hex: "5EEAD4", light: "107F6E", symbol: "banknote.fill", cadence: .fixed, sortOrder: 7),
    ]

    /// Where money comes from. Separate from spending because these are never
    /// budgeted, ranked or charted as spending.
    static let builtInIncome: [Bucket] = [
        Bucket(id: "salary",    label: "Salary",    hex: "3FB984", light: "2B7E5A", symbol: "briefcase.fill", kind: .income, sortOrder: 0),
        Bucket(id: "dividends", label: "Dividends", hex: "5EEAD4", light: "107F6E", symbol: "chart.line.uptrend.xyaxis", kind: .income, sortOrder: 1),
        Bucket(id: "gifts",     label: "Gifts",     hex: "F6A5C8", light: "790C3B", symbol: "gift.fill", kind: .income, sortOrder: 2),
        Bucket(id: "refunds",   label: "Refunds",   hex: "5B8DEF", light: "1147B0", symbol: "arrow.uturn.backward", kind: .income, sortOrder: 3),
        Bucket(id: "other-in",  label: "Other",     hex: "E0C05B", light: "886D1A", symbol: "plus.circle.fill", kind: .income, sortOrder: 4),
    ]

    static let builtInAll: [Bucket] = builtInExpense + builtInIncome

    /// The seed a built-in should snap back to when reset.
    static func builtIn(_ id: String) -> Bucket? { builtInAll.first { $0.id == id } }
}

// MARK: Live list

extension Bucket {
    /// Visible spending categories, in the user's order.
    static var all: [Bucket] { CategoryRegistry.visible(.expense) }

    /// Visible income categories, in the user's order.
    static var income: [Bucket] { CategoryRegistry.visible(.income) }

    /// Discretionary categories — the ones anti-budget mode actually watches.
    static var discretionary: [Bucket] { all.filter { $0.cadence == .variable } }

    static func list(for kind: EntryKind) -> [Bucket] { CategoryRegistry.visible(kind) }

    /// The pickable list, plus one extra id kept in it even if hidden.
    ///
    /// Editing an entry that was filed under a since-hidden category has to
    /// still show that category selected. Without this the chip row wouldn't
    /// contain it, the selection would fall back to the default, and saving
    /// would silently refile the entry somewhere it never was.
    static func list(for kind: EntryKind, including id: String?) -> [Bucket] {
        let visible = list(for: kind)
        guard let id, !visible.contains(where: { $0.id == id }),
              let extra = CategoryRegistry.bucket(id), extra.kind == kind
        else { return visible }
        return visible + [extra]
    }

    /// Category for a stored id. Resolves hidden ones too — an entry filed under
    /// a category that's since been hidden still has to render as itself rather
    /// than silently becoming Housing. Falls back only for ids this build has
    /// genuinely never seen, e.g. a category created on a newer build on the
    /// partner's phone that hasn't synced yet.
    static func named(_ id: String) -> Bucket { CategoryRegistry.bucket(id) ?? .unknown }

    /// Stand-in for an id with no category behind it.
    static let unknown = Bucket(id: "", label: "Uncategorised", hex: "8892B0",
                                light: "626E93", symbol: "questionmark.circle.fill",
                                isBuiltIn: false)

    /// Pre-selected category in the add sheet, per direction. Falls back to the
    /// first visible one, since the seeded default may have been hidden.
    static func fallback(for kind: EntryKind) -> Bucket {
        let preferred = kind == .income ? "salary" : "food"
        if let bucket = CategoryRegistry.bucket(preferred), !bucket.isHidden { return bucket }
        return list(for: kind).first ?? .unknown
    }

    static var fallback: Bucket { fallback(for: .expense) }
}

// MARK: - Category registry
//
// Categories are user data now, so the list can't be a `static let` the way it
// was. This holds the live set, rebuilt by `AppModel` whenever the store
// changes, and every `Bucket.all` / `.named(_:)` call site reads through it
// without knowing that happened.

enum CategoryRegistry {
    /// All categories including hidden ones, spending first.
    /// `nonisolated(unsafe)` on the same basis as the shared formatters in
    /// `Fmt`: every read is a SwiftUI body evaluation or an `AppModel` method,
    /// and every write is `AppModel.reload()` — all of it on the main actor.
    nonisolated(unsafe) private static var storage: [Bucket] =
        Bucket.builtInExpense + Bucket.builtInIncome
    nonisolated(unsafe) private static var index: [String: Bucket] =
        Dictionary(uniqueKeysWithValues: (Bucket.builtInExpense + Bucket.builtInIncome)
            .map { ($0.id, $0) })

    static var allIncludingHidden: [Bucket] { storage }

    static func visible(_ kind: EntryKind) -> [Bucket] {
        storage.filter { $0.kind == kind && !$0.isHidden }
    }

    static func hidden(_ kind: EntryKind) -> [Bucket] {
        storage.filter { $0.kind == kind && $0.isHidden }
    }

    static func bucket(_ id: String) -> Bucket? { index[id] }

    /// Swaps in a freshly loaded set. Returns whether anything actually
    /// changed, so the caller can skip republishing when it hasn't.
    ///
    /// An empty set falls back to the built-in seeds rather than emptying the
    /// registry. That case is real: between discarding the sample budget and
    /// creating a new one there's no household to load from, and a registry
    /// with nothing in it would make `Bucket.named(_:)` answer "Uncategorised"
    /// for every id in the app.
    @discardableResult
    static func replace(with categories: [Bucket]) -> Bool {
        let incoming = categories.isEmpty
            ? Bucket.builtInExpense + Bucket.builtInIncome
            : categories
        let sorted = incoming.sorted {
            $0.kind == $1.kind ? $0.sortOrder < $1.sortOrder : $0.kind == .expense
        }
        guard sorted != storage else { return false }
        storage = sorted
        index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return true
    }
}

/// A bucket paired with what's been spent in it. `Identifiable` so the charts
/// and lists can drive `ForEach` directly.
struct BucketTotal: Identifiable {
    let bucket: Bucket
    let total: Double
    var id: String { bucket.id }
}

// MARK: - Entries

struct Entry: Identifiable {
    let id: String
    var date: String     // "yyyy-MM-dd"
    var place: String
    var bucket: String
    var amount: Double
    /// `Member.id` of whoever spent or earned it.
    var memberID: String
    var kind: EntryKind = .expense
    /// How it felt, if the user said. Always optional.
    var mood: Mood?
    /// Why, in the spender's own words. The point of it is to answer the
    /// question a partner would otherwise have to ask out loud — "this was for
    /// your birthday" costs nothing to write and defuses the whole exchange.
    var note: String = ""
    /// A one-off that shouldn't be judged against the monthly plan — a laptop,
    /// a flight, a deposit. It stays in the ledger and in the export, but it's
    /// kept out of the month's spending, the category breakdown, the streak and
    /// the forecast.
    ///
    /// This is a different axis from `Cadence` and from the month-level unusual
    /// flag, and it's worth being clear which is which. Cadence asks whether a
    /// *category* is a standing bill. The month flag says a whole month was
    /// strange. This says one particular purchase was never part of the plan.
    var belowTheLine: Bool = false
    /// Kept out of the shared store entirely — never syncs to anyone else's
    /// device. See `BudgetStore.addEntry` for how that's enforced.
    var isPrivate: Bool = false
    /// Insertion timestamp — the tiebreaker when several entries share a date.
    var createdAt: Date

    /// "$1,234.56" for spending, "+$1,234.56" for income.
    var signedAmount: String { kind.sign + Fmt.money2(amount) }

    var hasNote: Bool { !note.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The category, unless it's already the entry's name. An entry logged
    /// without a place takes the category as its title, and showing "Fun & Misc"
    /// twice in a row reads like a bug.
    var categorySubtitle: String? {
        let label = Bucket.named(bucket).label
        return label.caseInsensitiveCompare(place) == .orderedSame ? nil : label
    }
}

// MARK: - Reactions

/// A small, warm response to somebody else's entry. Deliberately has no
/// negative option: a shared ledger that lets one person tut at another's
/// coffee is a worse product than one that doesn't, and the disapproval was
/// never the part that needed a button.
enum ReactionKind: String, CaseIterable, Identifiable {
    case heart, thumbsUp, flame, smile

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .heart:    "heart.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .flame:    "flame.fill"
        case .smile:    "face.smiling.inverse"
        }
    }

    var label: String {
        switch self {
        case .heart:    "Love this"
        case .thumbsUp: "Fair enough"
        case .flame:    "Worth it"
        case .smile:    "Made me smile"
        }
    }

    var color: Color {
        switch self {
        case .heart:    Palette.overText
        case .thumbsUp: Palette.moodRoutine
        case .flame:    Palette.moodJoy
        case .smile:    Palette.teal
        }
    }
}

/// One person's reaction to one entry. Stored as its own row rather than a
/// field on the entry so two people reacting at once from two phones merge
/// instead of overwriting each other.
struct Reaction: Identifiable, Hashable {
    let id: String
    var entryID: String
    var memberID: String
    var kind: ReactionKind
    var createdAt: Date
}

// MARK: - Months that shouldn't count

/// A month the user has marked as unrepresentative — a move, a wedding, a
/// medical bill. It still shows in the log and the totals, because it happened,
/// but it's kept out of streaks, badges and the trend averages.
///
/// Without this, one genuinely abnormal month quietly poisons every comparison
/// the app makes for the next half-year, and the app spends that whole time
/// telling the user they're doing worse than they are.
struct MonthFlag: Identifiable, Hashable {
    let month: String        // "yyyy-MM"
    var isUnusual: Bool
    var reason: String
    var id: String { month }
}

// MARK: - Recurring transactions

/// Something that happens every month on the same day — rent, a subscription,
/// a paycheque. Posts an entry automatically and reminds ahead of time.
struct Recurring: Identifiable, Hashable {
    let id: String
    var place: String
    var amount: Double
    var bucket: String
    var memberID: String
    var kind: EntryKind
    /// 1–28. Capped at 28 so every month has the day.
    var dayOfMonth: Int
    var isActive: Bool
    /// Last month ("yyyy-MM") this posted an entry, so it posts once per month.
    var lastPostedMonth: String

    static let maxDay = 28

    /// "3rd" — a day of the month with its ordinal suffix.
    static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    /// The day of the month this would fall on if it were set up today, capped
    /// so it exists in February.
    static var defaultDay: Int {
        min(Calendar.current.component(.day, from: Date()), maxDay)
    }

    /// "3rd of each month"
    var scheduleLabel: String { "\(Self.ordinal(dayOfMonth)) of each month" }
}

// MARK: - Loans

/// Money owed. Balances are entered by hand — there's no bank connection — so
/// the app's job is to hold the number, track payments against it, and be
/// honest about how long it'll take at the current rate.
struct Loan: Identifiable, Hashable {
    let id: String
    var name: String
    var balance: Double
    /// Nominal annual rate as a percentage. 0 for interest-free.
    var rate: Double
    var monthlyPayment: Double
    var createdAt: Date

    /// Months to clear at the current payment, or `nil` when the payment can't
    /// keep up with the interest — in which case the balance never falls and
    /// saying "12 years" would be a lie.
    var monthsToClear: Int? {
        guard balance > 0, monthlyPayment > 0 else { return nil }
        let monthly = rate / 100 / 12
        guard monthly > 0 else { return Fmt.whole(ceil(balance / monthlyPayment)) }
        let interestOnly = balance * monthly
        guard monthlyPayment > interestOnly else { return nil }
        // Standard amortisation: n = -ln(1 - rB/p) / ln(1 + r)
        let months = -log(1 - monthly * balance / monthlyPayment) / log(1 + monthly)
        guard months.isFinite, months > 0 else { return nil }
        return Fmt.whole(ceil(months))
    }

    /// Total interest paid if nothing changes.
    var projectedInterest: Double? {
        guard let months = monthsToClear else { return nil }
        return max(0, monthlyPayment * Double(months) - balance)
    }

    var payoffLabel: String {
        guard let months = monthsToClear else {
            return monthlyPayment > 0 ? "Payment doesn't cover the interest" : "No payment set"
        }
        if months < 12 { return Fmt.count(months, "month") + " to clear" }
        let years = months / 12
        let rest = months % 12
        return rest == 0 ? Fmt.count(years, "year") + " to clear"
                         : "\(years)y \(rest)m to clear"
    }
}

// MARK: - Goals

/// Money being saved toward something — an emergency fund, a deposit, a
/// holiday. The balance is typed in by hand for the same reason a loan's is:
/// there's no bank connection, so the app holds the number it was given, does
/// the arithmetic honestly, and never claims to know what's actually in an
/// account.
///
/// This is deliberately not derived from entries filed under Savings. With more
/// than one goal running there's no way to tell which transfer belonged to
/// which, and a progress bar that guessed would be worse than one that asked.
struct Goal: Identifiable, Hashable {
    let id: String
    var name: String
    var target: Double
    var saved: Double
    /// Put aside each month, if they said. 0 means they haven't.
    var monthlyContribution: Double
    /// "yyyy-MM-dd" — when they want it by. Empty means no date, which is the
    /// normal case: most saving doesn't have a deadline attached.
    var deadline: String
    var createdAt: Date

    var remaining: Double { max(0, target - saved) }

    var isComplete: Bool { target > 0 && saved >= target }

    /// 0–1, for the progress bar. A goal with no target set reads as empty
    /// rather than full — dividing by nothing shouldn't look like success.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, saved / target))
    }

    var hasDeadline: Bool { !deadline.isEmpty }

    /// Months to reach the target at the current monthly contribution, or `nil`
    /// when nothing is going in. "Never" is technically the answer there, but
    /// it's a scolding rather than information — the UI asks for a figure
    /// instead.
    var monthsToTarget: Int? {
        guard remaining > 0, monthlyContribution > 0 else { return nil }
        return max(1, Fmt.whole((remaining / monthlyContribution).rounded(.up)))
    }

    /// Whole months between today and the deadline, rounding a part-month up —
    /// a fortnight of runway still has to be saved for. `nil` when there's no
    /// deadline or it's already here.
    func monthsLeft(from today: Date) -> Int? {
        guard let due = Fmt.day(from: deadline) else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: due)
        guard end > start else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: start, to: end)
        return max(1, (parts.month ?? 0) + ((parts.day ?? 0) > 0 ? 1 : 0))
    }

    /// What has to go in each month to land on the deadline.
    func requiredMonthly(from today: Date) -> Double? {
        guard remaining > 0, let months = monthsLeft(from: today) else { return nil }
        return remaining / Double(months)
    }

    /// The deadline has come and gone with money still to find.
    func isOverdue(on today: Date) -> Bool {
        guard hasDeadline, !isComplete, let due = Fmt.day(from: deadline) else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: today)
    }

    /// Whether the monthly contribution is short of what the deadline needs.
    /// Only meaningful once both have been set — an unanswered question isn't
    /// a problem to flag.
    func isBehind(on today: Date) -> Bool {
        guard monthlyContribution > 0, let needed = requiredMonthly(from: today) else { return false }
        return monthlyContribution < needed
    }

    /// The one line under the name. Says the most useful true thing available,
    /// which depends on how much the user has actually told us.
    func paceLabel(on today: Date) -> String {
        if isComplete { return "Reached" }
        if target <= 0 { return "No target set" }
        if isOverdue(on: today) {
            return "\(Fmt.money(remaining)) short, past \(Fmt.dayTitle(deadline))"
        }
        if let needed = requiredMonthly(from: today), let months = monthsLeft(from: today) {
            return "\(Fmt.money(needed)) a month for \(Fmt.count(months, "month"))"
        }
        if let months = monthsToTarget {
            if months < 12 { return Fmt.count(months, "month") + " to go" }
            let years = months / 12
            let rest = months % 12
            return rest == 0 ? Fmt.count(years, "year") + " to go" : "\(years)y \(rest)m to go"
        }
        return "\(Fmt.money(remaining)) to go"
    }
}

// MARK: - Navigation

enum Tab: CaseIterable {
    case home, log, budget, stats

    var title: String {
        switch self {
        case .home:   "Home"
        case .log:    "Log"
        case .budget: "Budget"
        case .stats:  "Stats"
        }
    }

    var symbol: String {
        switch self {
        case .home:   "house.fill"
        case .log:    "calendar"
        case .budget: "creditcard.fill"
        case .stats:  "chart.pie.fill"
        }
    }
}
