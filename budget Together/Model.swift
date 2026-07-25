import SwiftUI

// MARK: - People

/// Avatar colours, in the order new people are assigned them. A household can
/// hold more people than there are entries here — `at(_:)` wraps, so the palette
/// never runs out and every member always renders.
struct MemberStyle {
    let color: Color
    let ink: Color

    init(_ hex: String, ink: String) {
        self.color = Color(hex: hex)
        self.ink = Color(hex: ink)
    }

    static let all: [MemberStyle] = [
        MemberStyle("5EEAD4", ink: "0C2B26"),   // teal
        MemberStyle("C69BFF", ink: "2A1740"),   // purple
        MemberStyle("F5C15E", ink: "3A2A08"),   // amber
        MemberStyle("FF9FB2", ink: "40121E"),   // rose
        MemberStyle("7FB2FF", ink: "0E2445"),   // blue
        MemberStyle("A8E063", ink: "1D3208"),   // lime
        MemberStyle("FFAE7B", ink: "40200C"),   // orange
        MemberStyle("6EE7F5", ink: "06303A"),   // cyan
    ]

    /// Grey, for an entry whose member no longer exists (deleted on the
    /// partner's device before that deletion reached us).
    static let unknown = MemberStyle("5A6076", ink: "EDEFF7")

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

// MARK: - Spending buckets

struct Bucket: Identifiable {
    let id: String
    let label: String
    let symbol: String
    /// Resolved once at startup — `Color(hex:)` runs a `Scanner`, which is far
    /// too expensive to repeat on every SwiftUI body evaluation.
    let color: Color
    let tint: Color
    /// First word of `label`, for tight spots like bubbles and category chips.
    let short: String

    init(id: String, label: String, hex: String, symbol: String) {
        let color = Color(hex: hex)
        self.id = id
        self.label = label
        self.symbol = symbol
        self.color = color
        self.tint = color.opacity(0.16)
        self.short = String(label.split(separator: " ").first ?? "")
    }
}

extension Bucket {
    static let all: [Bucket] = [
        Bucket(id: "housing",   label: "Housing",       hex: "E86A4A", symbol: "house.fill"),
        Bucket(id: "food",      label: "Food & Drink",  hex: "3FB984", symbol: "fork.knife"),
        Bucket(id: "transport", label: "Transport",     hex: "5B8DEF", symbol: "car.fill"),
        Bucket(id: "fun",       label: "Fun & Misc",    hex: "D45C87", symbol: "party.popper.fill"),
        Bucket(id: "shopping",  label: "Shopping",      hex: "E0C05B", symbol: "bag.fill"),
        Bucket(id: "personal",  label: "Health",        hex: "F6A5C8", symbol: "heart.fill"),
        Bucket(id: "subs",      label: "Subscriptions", hex: "C69BFF", symbol: "repeat"),
        Bucket(id: "savings",   label: "Savings",       hex: "5EEAD4", symbol: "banknote.fill"),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Bucket for a stored id, falling back to the first bucket so unknown ids
    /// (from a newer build on the partner's phone) still render.
    static func named(_ id: String) -> Bucket { byID[id] ?? all[0] }

    /// Pre-selected category in the add sheet.
    static let fallback = named("food")
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
    /// `Member.id` of whoever spent it.
    var memberID: String
    /// Insertion timestamp — the tiebreaker when several entries share a date.
    var createdAt: Date
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
