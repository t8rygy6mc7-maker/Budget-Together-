import Foundation

// MARK: - Asking questions of the ledger
//
// A rule parser over a defined set of question shapes, not a language model. It
// handles what it recognises and *says so* when it doesn't, rather than
// guessing — a budgeting answer that's confidently wrong is worse than no
// answer.
//
// `QueryEngine` is the same shape as `SuggestionEngine`: swapping in a
// model-backed parser later means conforming a new type. The answer is still
// computed from the ledger either way; only the understanding would move.

struct QueryAnswer {
    let headline: String
    let detail: String?
    /// Entries behind the number, so the answer can be checked.
    let entries: [Entry]
}

struct QueryContext {
    var entries: [Entry]          // all of them, all months
    var caps: [String: Double]
    var members: [Member]
    var today: Date
}

protocol QueryEngine {
    /// `nil` when the question isn't understood — the caller shows examples.
    func answer(_ question: String, context: QueryContext) -> QueryAnswer?
}

struct RuleQueryEngine: QueryEngine {

    /// The windows a question can ask about.
    private enum Timeframe {
        case today, thisWeek, thisMonth, lastMonth

        var label: String {
            switch self {
            case .today:     "today"
            case .thisWeek:  "this week"
            case .thisMonth: "this month"
            case .lastMonth: "last month"
            }
        }
    }

    func answer(_ question: String, context: QueryContext) -> QueryAnswer? {
        let text = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let timeframe = parseTimeframe(text)
        let scoped = entries(in: timeframe, from: context)

        // "who spent the most"
        if text.contains("who") {
            return whoAnswer(scoped, context: context, timeframe: timeframe)
        }

        let subject = parseSubject(text, context: context)

        // "how much can I spend" / "what's left" — forward-looking, so it needs
        // a cap to answer against.
        if text.contains("can i") || text.contains("left") || text.contains("remaining") {
            return remainingAnswer(subject, scoped: scoped, context: context, timeframe: timeframe)
        }

        // "how much did I spend on X" and everything else that reads as a total.
        if text.contains("spend") || text.contains("spent") || text.contains("how much")
            || text.contains("total") || subject != nil {
            return spentAnswer(subject, scoped: scoped, timeframe: timeframe)
        }
        return nil
    }

    // MARK: Answers

    private func spentAnswer(_ subject: Subject?, scoped: [Entry],
                             timeframe: Timeframe) -> QueryAnswer {
        let matched = filter(scoped, by: subject).filter { $0.kind == .expense }
        let total = matched.reduce(0) { $0 + $1.amount }
        let what = subject?.label ?? "everything"
        return QueryAnswer(
            headline: Fmt.money2(total),
            detail: "on \(what) \(timeframe.label), across \(Fmt.count(matched.count, "entry", plural: "entries")).",
            entries: matched
        )
    }

    private func remainingAnswer(_ subject: Subject?, scoped: [Entry],
                                 context: QueryContext, timeframe: Timeframe) -> QueryAnswer {
        // Caps are monthly, so a weekly question gets a weekly slice of one.
        let monthEntries = entries(in: .thisMonth, from: context)

        guard case let .bucket(bucket)? = subject else {
            if case let .keyword(word)? = subject {
                let spent = filter(scoped, by: subject).reduce(0) { $0 + $1.amount }
                return QueryAnswer(
                    headline: "No cap on \"\(word)\"",
                    detail: "Caps are set per category, not per place. You've spent \(Fmt.money2(spent)) on it \(timeframe.label) — try asking about a category like Food & Drink.",
                    entries: filter(scoped, by: subject)
                )
            }
            let cap = context.caps.values.reduce(0, +)
            let spent = monthEntries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
            return QueryAnswer(
                headline: Fmt.money2(max(0, cap - spent)),
                detail: "left of a \(Fmt.money(cap)) plan this month.",
                entries: []
            )
        }

        let cap = context.caps[bucket.id] ?? 0
        let spentThisMonth = monthEntries
            .filter { $0.kind == .expense && $0.bucket == bucket.id }
            .reduce(0) { $0 + $1.amount }
        let remaining = max(0, cap - spentThisMonth)

        guard cap > 0 else {
            return QueryAnswer(headline: "No cap set for \(bucket.label)",
                               detail: "Set one on the Budget tab and I can answer this.",
                               entries: [])
        }

        // A weekly question against a monthly cap: spread what's left over the
        // days that remain, then give a week of it.
        if timeframe == .thisWeek {
            let calendar = Calendar.current
            let days = calendar.range(of: .day, in: .month, for: context.today)?.count ?? 30
            let daysLeft = max(1, days - calendar.component(.day, from: context.today) + 1)
            let week = remaining / Double(daysLeft) * min(7, Double(daysLeft))
            return QueryAnswer(
                headline: Fmt.money2(week),
                detail: "on \(bucket.label) this week — that's \(Fmt.money2(remaining)) left for the month spread over the \(Fmt.count(daysLeft, "day")) that remain.",
                entries: []
            )
        }

        return QueryAnswer(
            headline: Fmt.money2(remaining),
            detail: "left on \(bucket.label) this month, from a \(Fmt.money(cap)) cap with \(Fmt.money2(spentThisMonth)) spent.",
            entries: []
        )
    }

    private func whoAnswer(_ scoped: [Entry], context: QueryContext,
                           timeframe: Timeframe) -> QueryAnswer? {
        var totals: [String: Double] = [:]
        for entry in scoped where entry.kind == .expense {
            totals[entry.memberID, default: 0] += entry.amount
        }
        guard let top = totals.max(by: { $0.value < $1.value }),
              let member = context.members.first(where: { $0.id == top.key }) else { return nil }
        let rest = totals.values.reduce(0, +) - top.value
        return QueryAnswer(
            headline: member.name,
            detail: "spent \(Fmt.money2(top.value)) \(timeframe.label)" +
                    (rest > 0 ? ", against \(Fmt.money2(rest)) from everyone else." : "."),
            entries: scoped.filter { $0.memberID == top.key && $0.kind == .expense }
        )
    }

    // MARK: Parsing

    private enum Subject {
        case bucket(Bucket)
        case keyword(String)

        var label: String {
            switch self {
            case .bucket(let bucket): bucket.label
            case .keyword(let word):  word
            }
        }
    }

    private func parseTimeframe(_ text: String) -> Timeframe {
        if text.contains("today") { return .today }
        if text.contains("this week") || text.contains("week") { return .thisWeek }
        if text.contains("last month") { return .lastMonth }
        return .thisMonth
    }

    /// A category name if one is mentioned, otherwise a place keyword — "coffee"
    /// isn't a category, but it is something the ledger can be searched for.
    private func parseSubject(_ text: String, context: QueryContext) -> Subject? {
        for bucket in Bucket.all + Bucket.income {
            if text.contains(bucket.label.lowercased()) || text.contains(bucket.short.lowercased()) {
                return .bucket(bucket)
            }
        }
        // Whatever follows "on"/"for" is the thing being asked about.
        for marker in [" on ", " for "] {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.upperBound...]
                .replacingOccurrences(of: "?", with: "")
            let word = tail
                .components(separatedBy: " ")
                .prefix(while: { !Self.stopWords.contains($0) })
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if word.count >= 3 { return .keyword(word) }
        }
        return nil
    }

    private static let stopWords: Set<String> = [
        "this", "last", "today", "week", "month", "year", "so", "far", "in", "the", "",
    ]

    // MARK: Filtering

    private func entries(in timeframe: Timeframe, from context: QueryContext) -> [Entry] {
        let calendar = Calendar.current
        switch timeframe {
        case .today:
            let key = Fmt.isoDay(context.today)
            return context.entries.filter { $0.date == key }
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: context.today) else {
                return context.entries
            }
            return context.entries.filter {
                guard let date = Fmt.day(from: $0.date) else { return false }
                return week.contains(date)
            }
        case .thisMonth:
            return context.entries.filter { $0.date.hasPrefix(Fmt.isoMonth(context.today)) }
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: context.today)
                ?? context.today
            return context.entries.filter { $0.date.hasPrefix(Fmt.isoMonth(previous)) }
        }
    }

    private func filter(_ entries: [Entry], by subject: Subject?) -> [Entry] {
        switch subject {
        case .none:
            return entries
        case .bucket(let bucket):
            return entries.filter { $0.bucket == bucket.id }
        case .keyword(let word):
            return entries.filter { $0.place.lowercased().contains(word) }
        }
    }
}
