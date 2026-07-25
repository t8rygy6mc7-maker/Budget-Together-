import Foundation

// MARK: - Forecasting and suggestions
//
// All of this runs on the device. Nothing is sent anywhere, which is what lets
// the app keep its local/CloudKit-private posture — and it means the numbers are
// deterministic and work offline.
//
// `SuggestionEngine` is a protocol on purpose. The rule-based implementation
// below is the default; swapping in a model-backed one later means conforming a
// new type, not rewriting the callers.

// MARK: Forecast

struct Forecast {
    /// Where the month lands if the rest of it looks like the part so far,
    /// plus bills known to still be coming.
    var projected: Double = 0
    /// The run-rate half of `projected`, before known bills.
    var fromPace: Double = 0
    /// Recurring expenses due later this month that haven't posted yet.
    var billsToCome: Double = 0
    var plan: Double = 0
    /// Days of data behind the estimate. Under a few, it isn't worth showing.
    var daysElapsed: Int = 0

    var overBy: Double { max(0, projected - plan) }
    var underBy: Double { max(0, plan - projected) }
    var isOverPlan: Bool { projected > plan }

    /// A projection from two days of spending is noise. Say nothing instead.
    var isReliable: Bool { daysElapsed >= 5 && plan > 0 }

    static func make(spent: Double, byDay: [Int: Double], today: Int, daysInMonth: Int,
                     plan: Double, recurring: [Recurring], currentMonthKey: String) -> Forecast {
        var forecast = Forecast()
        forecast.plan = plan
        forecast.daysElapsed = today

        // Run rate from what's happened, extended over the days left. Bills
        // already posted are part of `spent`, so they're inside the rate — which
        // is why only *unposted* bills get added on top.
        let daysLeft = max(0, daysInMonth - today)
        let perDay = today > 0 ? spent / Double(today) : 0
        forecast.fromPace = spent + perDay * Double(daysLeft)

        forecast.billsToCome = recurring
            .filter { $0.isActive && $0.kind == .expense
                      && $0.lastPostedMonth != currentMonthKey && $0.dayOfMonth > today }
            .reduce(0) { $0 + $1.amount }

        // A bill that hasn't landed yet isn't in the run rate, but part of it is
        // implicitly there once spread across the month. Taking the larger of
        // the two rather than the sum keeps the estimate from double-counting.
        forecast.projected = max(forecast.fromPace, spent + forecast.billsToCome)
        _ = byDay
        return forecast
    }
}

// MARK: Suggestions

struct Suggestion: Identifiable {
    enum Weight { case win, nudge, warning }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let weight: Weight
}

protocol SuggestionEngine {
    func suggestions(for input: SuggestionInput) -> [Suggestion]
}

/// Everything an engine is allowed to see. Deliberately a value type with no
/// store access, so a future implementation can't quietly widen its reach.
struct SuggestionInput {
    var forecast: Forecast
    var ranked: [BucketTotal]
    var caps: [String: Double]
    var daysLeft: Int
    var moods: [MoodTotal]
    var savingsCap: Double
    var savingsSpent: Double
}

/// Arithmetic against the plan. Every line it produces is a statement the user
/// could check by hand, which is the bar for telling someone what to do with
/// their money.
struct RuleSuggestionEngine: SuggestionEngine {
    func suggestions(for input: SuggestionInput) -> [Suggestion] {
        var out: [Suggestion] = []

        // The headline trade: what a cut in the biggest overspending category
        // would actually be worth by month end.
        if input.forecast.isReliable, input.forecast.isOverPlan,
           let worst = biggestOverrun(input) {
            let cut = worst.projected * 0.2
            out.append(Suggestion(
                id: "cut-\(worst.bucket.id)",
                title: "Trim \(worst.bucket.label) by a fifth",
                detail: "It's tracking to \(Fmt.money(worst.projected)) against a \(Fmt.money(worst.cap)) cap. Spending 20% less from here saves about \(Fmt.money(cut)) and brings the month back to \(Fmt.money(input.forecast.projected - cut)).",
                symbol: "scissors",
                weight: .nudge
            ))
        }

        // Savings is a category people quietly skip; say so before month end.
        if input.savingsCap > 0, input.savingsSpent < input.savingsCap, input.daysLeft <= 10 {
            let short = input.savingsCap - input.savingsSpent
            out.append(Suggestion(
                id: "savings",
                title: "Savings is \(Fmt.money(short)) short",
                detail: "\(Fmt.count(input.daysLeft, "day")) left to move it across and finish the month on plan.",
                symbol: "banknote.fill",
                weight: .nudge
            ))
        }

        // Behavioural, and only when the tagging is strong enough to mean it.
        if let mood = input.moods.first, mood.mood.isWorthNoticing, mood.count >= 3 {
            out.append(Suggestion(
                id: "mood-\(mood.mood.rawValue)",
                title: "\(mood.mood.label) is your biggest tagged driver",
                detail: "\(Fmt.money(mood.total)) across \(Fmt.count(mood.count, "buy", plural: "buys")). Worth a pause before the next one — that's the money most likely to be regretted.",
                symbol: mood.mood.symbol,
                weight: .nudge
            ))
        }

        if input.forecast.isReliable, !input.forecast.isOverPlan {
            out.append(Suggestion(
                id: "on-track",
                title: "On track to finish \(Fmt.money(input.forecast.underBy)) under",
                detail: "At the current rate the month lands at \(Fmt.money(input.forecast.projected)) against a \(Fmt.money(input.forecast.plan)) plan.",
                symbol: "checkmark.circle.fill",
                weight: .win
            ))
        }

        return out
    }

    /// The category whose projected end-of-month total most exceeds its cap.
    private func biggestOverrun(_ input: SuggestionInput)
        -> (bucket: Bucket, projected: Double, cap: Double)? {
        let elapsed = max(1, input.forecast.daysElapsed)
        let total = elapsed + input.daysLeft
        return input.ranked
            .compactMap { item -> (bucket: Bucket, projected: Double, cap: Double)? in
                guard let cap = input.caps[item.bucket.id], cap > 0 else { return nil }
                // Fixed commitments don't respond to "spend less" advice.
                guard item.bucket.cadence == .variable else { return nil }
                let projected = item.total / Double(elapsed) * Double(total)
                guard projected > cap else { return nil }
                return (item.bucket, projected, cap)
            }
            .max { ($0.projected - $0.cap) < ($1.projected - $1.cap) }
    }
}

// MARK: Subscription detection

/// A repeating charge found in the ledger. "Unused" isn't knowable without a
/// usage signal the app doesn't have, so this reports what repeats and how long
/// it's been quiet, then asks.
struct DetectedSubscription: Identifiable {
    let id: String            // normalised place name
    let place: String
    let bucket: String
    let typicalAmount: Double
    let occurrences: Int
    /// Days since the most recent charge.
    let daysSinceLast: Int
    /// Already tracked as a `Recurring`, so there's nothing to set up.
    let isTracked: Bool

    /// A monthly charge that hasn't appeared in over ~6 weeks either stopped or
    /// was missed. Either way it's worth a look.
    var looksLapsed: Bool { daysSinceLast > 45 }
}

enum SubscriptionDetective {
    /// Charges seen at least this many times count as repeating.
    private static let minimumOccurrences = 3

    static func detect(entries: [Entry], recurring: [Recurring], today: Date) -> [DetectedSubscription] {
        var groups: [String: [Entry]] = [:]
        for entry in entries where entry.kind == .expense {
            groups[normalise(entry.place), default: []].append(entry)
        }

        let tracked = Set(recurring.map { normalise($0.place) })

        return groups.compactMap { key, rows -> DetectedSubscription? in
            guard rows.count >= minimumOccurrences else { return nil }

            // Roughly the same amount each time — that's what separates a
            // subscription from a shop you happen to visit often.
            let amounts = rows.map(\.amount)
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard mean > 0 else { return nil }
            let spread = (amounts.max() ?? 0) - (amounts.min() ?? 0)
            guard spread / mean <= 0.15 else { return nil }

            // And spread across different months, not three times in one week.
            let months = Set(rows.map { String($0.date.prefix(7)) })
            guard months.count >= minimumOccurrences else { return nil }

            let latest = rows.map(\.date).max() ?? ""
            return DetectedSubscription(
                id: key,
                place: rows.last?.place ?? key,
                bucket: rows.last?.bucket ?? "subs",
                typicalAmount: mean,
                occurrences: rows.count,
                daysSinceLast: days(since: latest, to: today),
                isTracked: tracked.contains(key)
            )
        }
        .sorted { $0.typicalAmount > $1.typicalAmount }
    }

    private static func normalise(_ place: String) -> String {
        place.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func days(since iso: String, to today: Date) -> Int {
        guard let date = Fmt.day(from: iso) else { return 0 }
        return Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
    }
}
