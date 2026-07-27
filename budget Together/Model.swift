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
enum Cadence { case fixed, variable }

struct Bucket: Identifiable {
    let id: String
    let label: String
    let symbol: String
    /// Resolved once at startup — `Color(hex:)` runs a `Scanner`, which is far
    /// too expensive to repeat on every SwiftUI body evaluation. The dynamic
    /// pair is likewise built once; resolving it per scheme is a trait lookup.
    let color: Color
    let tint: Color
    /// Halo under a bubble. A bright bloom on a dark screen becomes a heavy
    /// smear on a light one, so the light scheme drops it to a hint.
    let glow: Color
    /// First word of `label`, for tight spots like bubbles and category chips.
    let short: String
    let cadence: Cadence

    /// `hex` is the dark-scheme fill, `light` its light-scheme counterpart at
    /// the same hue. Fill encodes identity in both schemes — see DESIGN-NOTES §1.
    init(id: String, label: String, hex: String, light: String,
         symbol: String, cadence: Cadence = .variable) {
        let color = Color(dark: hex, light: light)
        self.glow = Color(dark: hex, darkAlpha: 0.65, light: light, lightAlpha: 0.26)
        self.id = id
        self.label = label
        self.symbol = symbol
        self.color = color
        self.tint = color.opacity(0.16)
        self.short = String(label.split(separator: " ").first ?? "")
        self.cadence = cadence
    }
}

extension Bucket {
    static let all: [Bucket] = [
        Bucket(id: "housing",   label: "Housing",       hex: "E86A4A", light: "BC3918", symbol: "house.fill", cadence: .fixed),
        Bucket(id: "food",      label: "Food & Drink",  hex: "3FB984", light: "2B7E5A", symbol: "fork.knife"),
        Bucket(id: "transport", label: "Transport",     hex: "5B8DEF", light: "1147B0", symbol: "car.fill"),
        Bucket(id: "fun",       label: "Fun & Misc",    hex: "D45C87", light: "A82C59", symbol: "party.popper.fill"),
        Bucket(id: "shopping",  label: "Shopping",      hex: "E0C05B", light: "886D1A", symbol: "bag.fill"),
        Bucket(id: "personal",  label: "Health",        hex: "F6A5C8", light: "790C3B", symbol: "heart.fill"),
        Bucket(id: "subs",      label: "Subscriptions", hex: "C69BFF", light: "390085", symbol: "repeat", cadence: .fixed),
        Bucket(id: "savings",   label: "Savings",       hex: "5EEAD4", light: "107F6E", symbol: "banknote.fill", cadence: .fixed),
    ]

    /// Discretionary categories — the ones anti-budget mode actually watches.
    static let discretionary: [Bucket] = all.filter { $0.cadence == .variable }

    /// Where money comes from. Separate from `all` because these are never
    /// budgeted, ranked or charted as spending.
    static let income: [Bucket] = [
        Bucket(id: "salary",    label: "Salary",    hex: "3FB984", light: "2B7E5A", symbol: "briefcase.fill"),
        Bucket(id: "dividends", label: "Dividends", hex: "5EEAD4", light: "107F6E", symbol: "chart.line.uptrend.xyaxis"),
        Bucket(id: "gifts",     label: "Gifts",     hex: "F6A5C8", light: "790C3B", symbol: "gift.fill"),
        Bucket(id: "refunds",   label: "Refunds",   hex: "5B8DEF", light: "1147B0", symbol: "arrow.uturn.backward"),
        Bucket(id: "other-in",  label: "Other",     hex: "E0C05B", light: "886D1A", symbol: "plus.circle.fill"),
    ]

    static func list(for kind: EntryKind) -> [Bucket] { kind == .income ? income : all }

    private static let byID = Dictionary(uniqueKeysWithValues: (all + income).map { ($0.id, $0) })

    /// Bucket for a stored id, falling back to the first bucket so unknown ids
    /// (from a newer build on the partner's phone) still render.
    static func named(_ id: String) -> Bucket { byID[id] ?? all[0] }

    /// Pre-selected category in the add sheet, per direction.
    static let fallback = named("food")
    static let incomeFallback = named("salary")

    static func fallback(for kind: EntryKind) -> Bucket {
        kind == .income ? incomeFallback : fallback
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

    /// "3rd of each month"
    var scheduleLabel: String {
        let suffix: String
        switch dayOfMonth % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch dayOfMonth % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(dayOfMonth)\(suffix) of each month"
    }
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
        guard monthly > 0 else { return Int(ceil(balance / monthlyPayment)) }
        let interestOnly = balance * monthly
        guard monthlyPayment > interestOnly else { return nil }
        // Standard amortisation: n = -ln(1 - rB/p) / ln(1 + r)
        let months = -log(1 - monthly * balance / monthlyPayment) / log(1 + monthly)
        guard months.isFinite, months > 0 else { return nil }
        return Int(ceil(months))
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
