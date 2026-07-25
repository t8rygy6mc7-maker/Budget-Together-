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
    /// Consecutive days up to today spent at or under the daily allowance.
    var streak: Int = 0
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
        wins.streak = streak(byDay: byDay, allowance: dailyAllowance, today: today)
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

    /// Counts back from today. A day with no spending counts — doing nothing is
    /// the cheapest way to stay inside a budget, and the streak should say so.
    /// Today itself only breaks the streak once it's actually over the line, so
    /// a morning coffee doesn't zero the count before lunch.
    private static func streak(byDay: [Int: Double], allowance: Double, today: Int) -> Int {
        guard allowance > 0, today >= 1 else { return 0 }
        var count = 0
        for day in stride(from: today, through: 1, by: -1) {
            guard byDay[day, default: 0] <= allowance else { break }
            count += 1
        }
        return count
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
