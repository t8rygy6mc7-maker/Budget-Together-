import Foundation

// MARK: - Positive reinforcement
//
// The counterweight to the overspend alert. Everything here is *derived* — no
// stored progress, nothing to migrate, and nothing that can drift out of step
// with the ledger. A badge is simply a question asked of the data.
//
// Two things follow from that, and both are deliberate.
//
// A badge is asked of the **whole** ledger, not of this month. "Clean week"
// used to mean "the current streak is at least seven", so it was handed back on
// the 1st of every month, when the streak starts again — an achievement that
// un-happens isn't one. The streak itself is still the live month's; what earns
// the badge is the best run there has ever been.
//
// And a stretch nobody logged in can't earn anything. A day without spending
// counts toward a streak, which is right — doing nothing is the cheapest way to
// stay inside a budget — but only between days when the ledger was actually in
// use. Otherwise setting a limit on the 20th of someone's first month made
// nineteen empty days a nineteen-day streak, and a budget created with limits
// was "Three in a row" before its first entry.

struct Badge: Identifiable {
    /// What a badge is about, and the order the sheet shows them in.
    enum Group: String, CaseIterable, Identifiable {
        case starting, plan, saving, together

        var id: String { rawValue }

        var title: String {
            switch self {
            case .starting: "Getting going"
            case .plan:     "Inside the plan"
            case .saving:   "Saving"
            case .together: "Together"
            }
        }
    }

    /// How far along a badge that isn't earned yet is. Only for the ones that
    /// are a count of something — "6 of 10" is encouragement, and there's no
    /// such number for "finish a month inside the plan".
    struct Progress {
        /// 0–1, for the bar.
        let fraction: Double
        /// "6 of 10", for the line beside it.
        let label: String

        init(_ current: Int, of target: Int) {
            fraction = target > 0 ? min(1, max(0, Double(current) / Double(target))) : 0
            label = "\(min(current, target)) of \(target)"
        }

        init(fraction: Double, label: String) {
            self.fraction = min(1, max(0, fraction))
            self.label = label
        }
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let group: Group
    let isEarned: Bool
    var progress: Progress? = nil
}

struct Wins {
    /// Consecutive days up to today spent at or under the daily allowance,
    /// allowing one over-budget day inside the run — see `streak(byDay:…)`.
    var streak: Int = 0
    /// Whether the grace day has been used up, so the UI can say so rather than
    /// let the next slip look like an unexplained reset.
    var graceUsed: Bool = false
    /// The longest such run there has been, in this month or any before it.
    var bestStreak: Int = 0
    /// Completed months in a row, up to the latest, that finished inside the
    /// plan.
    var monthsUnderBudget: Int = 0
    var badges: [Badge] = []

    var earned: [Badge] { badges.filter(\.isEarned) }

    func badges(in group: Badge.Group) -> [Badge] { badges.filter { $0.group == group } }
}

// MARK: - What the badges are asked of

/// One finished month, as the badges see it. Only months something was logged
/// in exist at all: a month the app wasn't opened in is neither a month inside
/// the plan nor one outside it.
struct ClosedMonth {
    let key: String              // "yyyy-MM"
    /// Length of the month.
    let days: Int
    /// Spending, with one-offs left out as everywhere else.
    var spent: Double = 0
    var earned: Double = 0
    /// The plan total in force at the time.
    var cap: Double = 0
    /// Day of month → spending.
    var byDay: [Int: Double] = [:]
    /// The first and last days anything was logged.
    var firstDay: Int = 0
    var lastDay: Int = 0
    /// Marked by the household as unrepresentative.
    var isUnusual = false

    var wasInsidePlan: Bool { cap > 0 && spent <= cap }
    /// More came in than went out. Needs income to have been logged — without
    /// it this would be true of nobody, and with none logged it isn't known.
    var keptSome: Bool { earned > 0 && earned > spent }
}

/// Everything the badges are allowed to see. A value type with no store access,
/// on the same grounds as `SuggestionInput`.
struct WinsInput {
    // The live month, for the streak.
    var byDay: [Int: Double] = [:]
    /// The plan spread evenly across the month.
    var dailyAllowance: Double = 0
    var today: Int = 1
    /// The first day of this month the streak may count from: the 1st, unless
    /// the ledger itself only begins this month.
    var streakStartsOn: Int = 1

    // The whole ledger.
    var entryCount = 0
    var taggedCount = 0
    /// Longest run of consecutive days with something logged.
    var loggingRun = 0
    /// Every earlier month with entries in it, oldest first.
    var closedMonths: [ClosedMonth] = []

    // What's been set up.
    var hasPlan = false
    var recurringCount = 0
    var goals: [Goal] = []
    var challengesWon = 0
    var memberCount = 1
    /// How many of those members have logged at least one entry.
    var membersLogged = 0
}

extension Wins {
    static func make(_ input: WinsInput) -> Wins {
        var wins = Wins()
        let run = streak(byDay: input.byDay, allowance: input.dailyAllowance,
                         today: input.today, since: input.streakStartsOn)
        wins.streak = run.length
        wins.graceUsed = run.graceUsed
        wins.bestStreak = max(run.length, input.closedMonths.map { bestRun(in: $0) }.max() ?? 0)

        // Months the household called strange are stepped over: a run of good
        // months shouldn't be ended by the one they moved house in.
        let months = input.closedMonths.filter { !$0.isUnusual }.map(\.wasInsidePlan)
        wins.monthsUnderBudget = months.reversed().prefix { $0 }.count
        let bestMonths = longestRun(in: months)

        let closed = input.closedMonths
        let hadPlan = input.hasPlan || closed.contains { $0.cap > 0 }
        let furthestGoal = input.goals.map(\.fraction).max() ?? 0
        let percent = Fmt.whole(furthestGoal * 100)

        var badges = [
            Badge(id: "logging", title: "Getting it down",
                  detail: "Log 10 transactions", symbol: "square.and.pencil",
                  group: .starting, isEarned: input.entryCount >= 10,
                  progress: Badge.Progress(input.entryCount, of: 10)),
            Badge(id: "everyday", title: "Every day for a week",
                  detail: "Log something seven days running", symbol: "calendar",
                  group: .starting, isEarned: input.loggingRun >= 7,
                  progress: Badge.Progress(input.loggingRun, of: 7)),
            Badge(id: "habit", title: "In the habit",
                  detail: "Log 100 transactions", symbol: "checklist",
                  group: .starting, isEarned: input.entryCount >= 100,
                  progress: Badge.Progress(input.entryCount, of: 100)),
            Badge(id: "aware", title: "Self-aware",
                  detail: "Tag 10 spends with how they felt", symbol: "brain.head.profile",
                  group: .starting, isEarned: input.taggedCount >= 10,
                  progress: Badge.Progress(input.taggedCount, of: 10)),
            Badge(id: "planned", title: "Made a plan",
                  detail: "Set a limit for a category", symbol: "slider.horizontal.3",
                  group: .starting, isEarned: hadPlan),
            Badge(id: "autopilot", title: "On autopilot",
                  detail: "Set up a bill or payday that repeats", symbol: "repeat",
                  group: .starting, isEarned: input.recurringCount > 0),

            Badge(id: "week", title: "Clean week",
                  detail: "7 days in a row inside the daily allowance", symbol: "flame.fill",
                  group: .plan, isEarned: wins.bestStreak >= 7,
                  progress: Badge.Progress(wins.bestStreak, of: 7)),
            Badge(id: "fortnight", title: "Two weeks steady",
                  detail: "14 days in a row inside the daily allowance", symbol: "flame.circle.fill",
                  group: .plan, isEarned: wins.bestStreak >= 14,
                  progress: Badge.Progress(wins.bestStreak, of: 14)),
            Badge(id: "month", title: "Under budget",
                  detail: "Finish a month inside the plan", symbol: "checkmark.seal.fill",
                  group: .plan, isEarned: bestMonths >= 1),
            Badge(id: "threepeat", title: "Three in a row",
                  detail: "Three months running inside the plan", symbol: "trophy.fill",
                  group: .plan, isEarned: bestMonths >= 3,
                  progress: Badge.Progress(bestMonths, of: 3)),
            Badge(id: "halfyear", title: "Half a year steady",
                  detail: "Six months running inside the plan", symbol: "medal.fill",
                  group: .plan, isEarned: bestMonths >= 6,
                  progress: Badge.Progress(bestMonths, of: 6)),
            Badge(id: "challenge", title: "Saw it through",
                  detail: "Finish a challenge without breaking it", symbol: "flag.checkered",
                  group: .plan, isEarned: input.challengesWon > 0),

            Badge(id: "kept", title: "Kept some",
                  detail: "Finish a month with more coming in than going out",
                  symbol: "arrow.down.to.line.circle.fill",
                  group: .saving, isEarned: closed.contains(where: \.keptSome)),
            Badge(id: "goal", title: "Something to save for",
                  detail: "Set a savings goal", symbol: "target",
                  group: .saving, isEarned: !input.goals.isEmpty),
            Badge(id: "halfway", title: "Halfway there",
                  detail: "Get a goal to half its target", symbol: "circle.lefthalf.filled",
                  group: .saving, isEarned: furthestGoal >= 0.5,
                  progress: input.goals.isEmpty ? nil
                    : Badge.Progress(fraction: furthestGoal / 0.5, label: "\(percent)% saved")),
            Badge(id: "reached", title: "Goal reached",
                  detail: "Save the whole of a goal", symbol: "star.circle.fill",
                  group: .saving, isEarned: input.goals.contains(where: \.isComplete),
                  progress: input.goals.isEmpty ? nil
                    : Badge.Progress(fraction: furthestGoal, label: "\(percent)% saved")),
        ]

        // Only offered where it can be earned. On a budget of one it would sit
        // locked for good, which is a strange thing to show somebody.
        if input.memberCount > 1 {
            badges.append(Badge(
                id: "together", title: "All in",
                detail: "Everyone on the budget has logged something",
                symbol: "person.2.fill", group: .together,
                isEarned: input.membersLogged >= input.memberCount,
                progress: Badge.Progress(input.membersLogged, of: input.memberCount)))
        }

        wins.badges = badges
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
                               today: Int, since: Int) -> (length: Int, graceUsed: Bool) {
        guard allowance > 0, since >= 1, today >= since else { return (0, false) }
        var count = 0
        var grace = graceDays
        for day in stride(from: today, through: since, by: -1) {
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

    /// The best run a finished month held, by the same rule as the live streak:
    /// the longest stretch with no more than one day over inside it, counting
    /// the days that weren't. Looked for only between the first and last days
    /// anything was logged that month.
    static func bestRun(in month: ClosedMonth) -> Int {
        guard month.cap > 0, month.days > 0, month.firstDay >= 1,
              month.lastDay >= month.firstDay else { return 0 }
        let allowance = month.cap / Double(month.days)

        var best = 0
        var start = month.firstDay
        var over = 0
        for day in month.firstDay...month.lastDay {
            if month.byDay[day, default: 0] > allowance { over += 1 }
            while over > graceDays {
                if month.byDay[start, default: 0] > allowance { over -= 1 }
                start += 1
            }
            best = max(best, day - start + 1 - over)
        }
        return best
    }

    /// Longest unbroken run of `true`.
    private static func longestRun(in flags: [Bool]) -> Int {
        var best = 0
        var current = 0
        for flag in flags {
            current = flag ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    /// Longest run of consecutive calendar days with at least one entry.
    static func longestLoggingRun(_ entries: [Entry], calendar: Calendar = .current) -> Int {
        let days = Set(entries.map(\.date)).compactMap { Fmt.day(from: $0) }.sorted()
        var best = 0
        var current = 0
        var previous: Date?
        for day in days {
            if let previous,
               calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }
}

extension ClosedMonth {
    /// Every month before `currentKey` that has entries in it, oldest first.
    ///
    /// `planTotal` and `isUnusual` are asked per month rather than passed in as
    /// tables, so this stays a function of the ledger and two questions — and
    /// can be tested without a store behind it.
    static func all(from entries: [Entry], before currentKey: String,
                    calendar: Calendar = .current,
                    planTotal: (String) -> Double,
                    isUnusual: (String) -> Bool) -> [ClosedMonth] {
        var months: [String: ClosedMonth] = [:]
        for entry in entries {
            let key = String(entry.date.prefix(7))
            guard key < currentKey, let day = Int(entry.date.suffix(2)),
                  let date = Fmt.day(from: entry.date) else { continue }

            var month = months[key] ?? ClosedMonth(
                key: key,
                days: calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            )
            month.firstDay = month.firstDay == 0 ? day : min(month.firstDay, day)
            month.lastDay = max(month.lastDay, day)
            if entry.kind == .income {
                month.earned += entry.amount
            } else if !entry.belowTheLine {
                month.spent += entry.amount
                month.byDay[day, default: 0] += entry.amount
            }
            months[key] = month
        }
        return months.values
            .map { month in
                var month = month
                month.cap = planTotal(month.key)
                month.isUnusual = isUnusual(month.key)
                return month
            }
            .sorted { $0.key < $1.key }
    }
}
