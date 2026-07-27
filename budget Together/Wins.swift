import Foundation

// MARK: - Positive reinforcement
//
// The counterweight to the overspend alert. Everything here is *derived* — no
// stored progress, nothing to migrate, and nothing that can drift out of step
// with the ledger. A badge is simply a question asked of the data.

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let isEarned: Bool
}

struct Wins {
    /// Consecutive days up to today spent at or under the daily allowance,
    /// allowing one over-budget day inside the run — see `streak(byDay:…)`.
    var streak: Int = 0
    /// Whether the grace day has been used up, so the UI can say so rather than
    /// let the next slip look like an unexplained reset.
    var graceUsed: Bool = false
    /// Completed months in a row that finished inside the budget.
    var monthsUnderBudget: Int = 0
    var badges: [Badge] = []

    var earned: [Badge] { badges.filter(\.isEarned) }

    /// The one worth putting on the home screen.
    var headline: Badge? { earned.last }
}

extension Wins {
    /// Builds the whole set from the month's spending and the closed months
    /// behind it.
    ///
    /// - Parameters:
    ///   - byDay: day of month → spent, for the current month.
    ///   - dailyAllowance: total caps spread evenly across the month.
    ///   - closedMonths: finished months, oldest first, each with what was spent
    ///     and the cap in force at the time.
    static func make(byDay: [Int: Double],
                     dailyAllowance: Double,
                     today: Int,
                     entryCount: Int,
                     taggedCount: Int,
                     closedMonths: [(spent: Double, cap: Double)]) -> Wins {
        var wins = Wins()
        let run = streak(byDay: byDay, allowance: dailyAllowance, today: today)
        wins.streak = run.length
        wins.graceUsed = run.graceUsed
        wins.monthsUnderBudget = trailingMonthsUnder(closedMonths)

        wins.badges = [
            Badge(id: "logging", title: "Getting it down",
                  detail: "Log 10 transactions", symbol: "square.and.pencil",
                  isEarned: entryCount >= 10),
            Badge(id: "aware", title: "Self-aware",
                  detail: "Tag 10 spends with how they felt", symbol: "brain.head.profile",
                  isEarned: taggedCount >= 10),
            Badge(id: "week", title: "Clean week",
                  detail: "7 days in a row inside the daily allowance", symbol: "flame.fill",
                  isEarned: wins.streak >= 7),
            Badge(id: "fortnight", title: "Two weeks steady",
                  detail: "14 days in a row inside the daily allowance", symbol: "flame.circle.fill",
                  isEarned: wins.streak >= 14),
            Badge(id: "month", title: "Under budget",
                  detail: "Finish a month inside the plan", symbol: "checkmark.seal.fill",
                  isEarned: wins.monthsUnderBudget >= 1),
            Badge(id: "threepeat", title: "Three in a row",
                  detail: "Three months running inside the plan", symbol: "trophy.fill",
                  isEarned: wins.monthsUnderBudget >= 3),
        ]
        return wins
    }

    /// One over-allowance day is forgiven inside a run. A second ends it.
    static let graceDays = 1

    /// Counts back from today. A day with no spending counts — doing nothing is
    /// the cheapest way to stay inside a budget, and the streak should say so.
    /// Today itself only breaks the streak once it's actually over the line, so
    /// a morning coffee doesn't zero the count before lunch.
    ///
    /// A single bad day is absorbed rather than fatal. Without that, the first
    /// dinner out in a good fortnight resets the count to zero, and a counter
    /// that punishes one ordinary evening is one people stop caring about by
    /// about the third time it happens. The forgiven day still doesn't *count*
    /// toward the total — it's carried, not credited.
    private static func streak(byDay: [Int: Double], allowance: Double,
                               today: Int) -> (length: Int, graceUsed: Bool) {
        guard allowance > 0, today >= 1 else { return (0, false) }
        var count = 0
        var grace = graceDays
        for day in stride(from: today, through: 1, by: -1) {
            if byDay[day, default: 0] <= allowance {
                count += 1
            } else if grace > 0 {
                grace -= 1          // absorbed: doesn't extend the run, doesn't end it
            } else {
                break
            }
        }
        return (count, grace < graceDays)
    }

    /// Trailing run of closed months that came in at or under cap, newest first.
    private static func trailingMonthsUnder(_ months: [(spent: Double, cap: Double)]) -> Int {
        var count = 0
        for month in months.reversed() {
            guard month.cap > 0, month.spent <= month.cap else { break }
            count += 1
        }
        return count
    }
}
