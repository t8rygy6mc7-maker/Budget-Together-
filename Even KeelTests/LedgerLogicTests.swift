import Foundation
import Testing
@testable import Even_Keel

// MARK: - Things derived from the ledger
//
// Streaks, forecasts, challenges and detected subscriptions are all questions
// asked of the entries rather than state kept beside them. That makes them
// easy to get subtly wrong and cheap to pin down: each takes plain values in
// and gives plain values back.

@Suite("Streak and badges")
struct WinsTests {

    /// A finished 30-day month with a $3,000 plan, so $100 a day.
    private func month(_ key: String = "2026-03", spent: Double = 0, earned: Double = 0,
                       cap: Double = 3000, byDay: [Int: Double] = [:],
                       first: Int = 1, last: Int = 30, unusual: Bool = false) -> ClosedMonth {
        ClosedMonth(key: key, days: 30, spent: spent, earned: earned, cap: cap,
                    byDay: byDay, firstDay: first, lastDay: last, isUnusual: unusual)
    }

    private func wins(_ change: (inout WinsInput) -> Void = { _ in }) -> Wins {
        var input = WinsInput(dailyAllowance: 100, today: 10)
        change(&input)
        return Wins.make(input)
    }

    private func earned(_ wins: Wins) -> Set<String> { Set(wins.earned.map(\.id)) }

    // MARK: The live streak

    @Test("A day with no spending counts")
    func quietDaysCount() {
        let result = wins { $0.byDay = [3: 40, 7: 99] }
        #expect(result.streak == 10)
        #expect(result.graceUsed == false)
    }

    @Test("One day over is carried, not credited")
    func oneSlipIsForgiven() {
        let result = wins { $0.byDay = [5: 250] }
        #expect(result.streak == 9)
        #expect(result.graceUsed == true)
    }

    @Test("A second day over ends the run")
    func secondSlipEndsIt() {
        // Counting back from the 10th: 10, 9, 8, 7, 6 count; the 5th is
        // forgiven; the 4th counts; the 3rd ends it.
        #expect(wins { $0.byDay = [5: 250, 3: 250] }.streak == 6)
    }

    @Test("No allowance, no streak")
    func needsAnAllowance() {
        #expect(wins { $0.dailyAllowance = 0 }.streak == 0)
    }

    /// Setting a limit on the 8th of someone's first month used to make the
    /// seven empty days before it a seven-day streak.
    @Test("The streak doesn't reach back before the ledger began")
    func streakStartsWithTheLedger() {
        #expect(wins { $0.streakStartsOn = 8 }.streak == 3)
        #expect(wins { $0.streakStartsOn = 11 }.streak == 0)     // nothing logged yet
    }

    // MARK: Best run

    @Test("A badge is earned by the best run there has been, not the current one")
    func bestRunOutlivesTheMonth() {
        // The 2nd of a new month: the live streak can't be more than two days.
        let result = wins {
            $0.today = 2
            $0.closedMonths = [month()]
        }
        #expect(result.streak == 2)
        #expect(result.bestStreak == 30)
        #expect(earned(result).isSuperset(of: ["week", "fortnight"]))
    }

    @Test("A past month's run follows the same one-slip rule")
    func bestRunInAMonth() {
        // Over on the 10th and the 20th. The best stretch forgives one of
        // them: the 1st to the 19th (18 days that count) or the 11th to the
        // 30th (19 that count).
        #expect(Wins.bestRun(in: month(byDay: [10: 500, 20: 500])) == 19)
        #expect(Wins.bestRun(in: month(byDay: [:])) == 30)
        #expect(Wins.bestRun(in: month(cap: 0)) == 0)
    }

    @Test("Only the days the ledger was in use can count")
    func bestRunStaysInsideTheLoggedDays() {
        #expect(Wins.bestRun(in: month(first: 12, last: 16)) == 5)
        #expect(Wins.bestRun(in: month(first: 0, last: 0)) == 0)
    }

    // MARK: Months

    @Test("Months inside the plan count back from the newest")
    func monthsUnderBudget() {
        let result = wins {
            $0.closedMonths = [
                month("2026-01", spent: 2900), month("2026-02", spent: 3100),
                month("2026-03", spent: 2800), month("2026-04", spent: 2700),
            ]
        }
        #expect(result.monthsUnderBudget == 2)
        #expect(earned(result).contains("month"))
        #expect(!earned(result).contains("threepeat"))
    }

    @Test("A badge for months in a row isn't taken back by a later bad month")
    func monthRunIsKept() {
        let result = wins {
            $0.closedMonths = [
                month("2026-01", spent: 100), month("2026-02", spent: 100),
                month("2026-03", spent: 100), month("2026-04", spent: 9000),
            ]
        }
        #expect(result.monthsUnderBudget == 0)
        #expect(earned(result).isSuperset(of: ["month", "threepeat"]))
        #expect(!earned(result).contains("halfyear"))
    }

    @Test("An unusual month is stepped over; a month with no plan isn't inside one")
    func unusualAndUnplannedMonths() {
        let stepped = wins {
            $0.closedMonths = [
                month("2026-01", spent: 100),
                month("2026-02", spent: 9000, unusual: true),
                month("2026-03", spent: 100),
            ]
        }
        #expect(stepped.monthsUnderBudget == 2)

        let unplanned = wins { $0.closedMonths = [month(spent: 10, cap: 0)] }
        #expect(unplanned.monthsUnderBudget == 0)
        #expect(!earned(unplanned).contains("month"))
    }

    // MARK: Badges

    @Test("A new budget has earned nothing")
    func nothingToStart() {
        let result = Wins.make(WinsInput())
        #expect(result.earned.isEmpty)
        #expect(result.badges.count == 16)
    }

    @Test("Getting going")
    func starting() {
        let result = wins {
            $0.entryCount = 100
            $0.taggedCount = 10
            $0.loggingRun = 7
            $0.hasPlan = true
            $0.recurringCount = 1
        }
        #expect(earned(result).isSuperset(of:
            ["logging", "habit", "aware", "everyday", "planned", "autopilot"]))
    }

    @Test("Saving")
    func saving() {
        let half = Goal(id: "a", name: "Trip", target: 1000, saved: 500,
                        monthlyContribution: 0, deadline: "", createdAt: Date())
        let some = wins { $0.goals = [half] }
        #expect(earned(some).isSuperset(of: ["goal", "halfway"]))
        #expect(!earned(some).contains("reached"))

        var done = half
        done.saved = 1000
        #expect(earned(wins { $0.goals = [done] }).contains("reached"))

        let kept = wins { $0.closedMonths = [month(spent: 2000, earned: 2600)] }
        #expect(earned(kept).contains("kept"))
        // Without income logged there's no knowing what was kept.
        #expect(!earned(wins { $0.closedMonths = [month(spent: 2000)] }).contains("kept"))
    }

    @Test("The shared badge is only offered where it can be earned")
    func together() {
        #expect(wins().badges.contains { $0.id == "together" } == false)

        let waiting = wins { $0.memberCount = 2; $0.membersLogged = 1 }
        #expect(waiting.badges.count == 17)
        #expect(!earned(waiting).contains("together"))
        #expect(earned(wins { $0.memberCount = 2; $0.membersLogged = 2 }).contains("together"))
    }

    @Test("A locked badge says how far along it is")
    func progress() {
        let result = wins { $0.entryCount = 6 }
        let logging = result.badges.first { $0.id == "logging" }
        #expect(logging?.progress?.label == "6 of 10")
        #expect(logging?.progress?.fraction == 0.6)
        // Past the target it stops at the target.
        #expect(Badge.Progress(14, of: 10).label == "10 of 10")
    }

    @Test("The line on Home leads with what's new")
    func badgeLine() {
        let result = wins { $0.entryCount = 10; $0.hasPlan = true }
        #expect(Copy.badgeLine(wins: result, new: []) == "3 of 16 badges earned")
        #expect(Copy.badgeLine(wins: result, new: ["planned"]) == "New badge: Made a plan")
        #expect(Copy.badgeLine(wins: result, new: ["planned", "logging"])
                == "2 new badges, Getting it down among them")
        #expect(Copy.badgeLine(wins: Wins.make(WinsInput()), new: []) == "16 badges to earn")
    }

    // MARK: Reading the ledger

    @Test("Closed months are built from the entries, and only where there are some")
    func closedMonthsFromEntries() {
        let months = ClosedMonth.all(
            from: [
                .make("2026-01-05", "Shop", 40),
                .make("2026-01-20", "Shop", 60),
                .make("2026-01-12", "Laptop", 900, bucket: "shopping", oneOff: true),
                .make("2026-01-01", "Payday", 2000, bucket: "salary", kind: .income),
                .make("2026-03-09", "Shop", 25),
                .make("2026-04-02", "This month", 10),
            ],
            before: "2026-04",
            planTotal: { $0 == "2026-01" ? 500 : 0 },
            isUnusual: { $0 == "2026-03" }
        )
        #expect(months.map(\.key) == ["2026-01", "2026-03"])     // no February, no April

        let january = months[0]
        #expect(january.days == 31)
        #expect(january.spent == 100)            // the laptop is a one-off
        #expect(january.earned == 2000)
        #expect(january.byDay == [5: 40, 20: 60])
        #expect(january.firstDay == 1 && january.lastDay == 20)
        #expect(january.cap == 500)
        #expect(january.wasInsidePlan && january.keptSome)
        #expect(months[1].isUnusual)
    }

    @Test("A logging run is consecutive days, across a month end")
    func loggingRun() {
        let entries: [Entry] = [
            .make("2026-01-30", "a", 1), .make("2026-01-31", "b", 1),
            .make("2026-02-01", "c", 1), .make("2026-02-01", "d", 1),
            .make("2026-02-03", "e", 1),
        ]
        #expect(Wins.longestLoggingRun(entries) == 3)
        #expect(Wins.longestLoggingRun([]) == 0)
    }
}

@Suite("Forecast")
struct ForecastTests {

    private func forecast(spent: Double = 300, today: Int = 10,
                          recurring: [Recurring] = []) -> Forecast {
        Forecast.make(spent: spent, today: today, daysInMonth: 30,
                      plan: 1000, recurring: recurring, currentMonthKey: "2026-03")
    }

    @Test("Run rate carried to the end of the month")
    func pace() {
        let result = forecast()
        #expect(result.fromPace == 900)
        #expect(result.projected == 900)
        #expect(result.isOverPlan == false)
    }

    @Test("A bill still to come is added only when it outweighs the pace")
    func billsToCome() {
        let small = forecast(recurring: [.make("Gym", 500, day: 20)])
        #expect(small.billsToCome == 500)
        #expect(small.projected == 900)        // already inside the run rate

        let large = forecast(recurring: [.make("Rent", 1000, day: 20)])
        #expect(large.projected == 1300)
        #expect(large.isOverPlan)
    }

    @Test("Posted, paused, past and incoming items aren't bills to come")
    func notBillsToCome() {
        let result = forecast(recurring: [
            .make("Posted", 100, day: 20, lastPosted: "2026-03"),
            .make("Paused", 100, day: 20, isActive: false),
            .make("Earlier", 100, day: 5),
            .make("Payday", 100, day: 20, kind: .income),
        ])
        #expect(result.billsToCome == 0)
    }

    @Test("A few days of spending isn't a forecast")
    func reliability() {
        #expect(forecast(today: 3).isReliable == false)
        #expect(forecast(today: 5).isReliable == true)
    }
}

@Suite("Challenges")
struct ChallengeTests {

    private func challenge(_ kind: ChallengeKind, bucket: String? = nil,
                           target: Double = 0) -> Challenge {
        Challenge(id: "c", title: "Test", kind: kind, bucket: bucket, target: target,
                  startDate: "2026-03-02", endDate: "2026-03-08", createdAt: Date())
    }

    @Test("Anything logged breaks a no-spend run; income doesn't")
    func noSpend() {
        let clean = ChallengeScorer.score([challenge(.noSpend)], entries: [
            .make("2026-03-04", "Payday", 900, bucket: "salary", kind: .income),
            .make("2026-03-01", "Before it began", 20),
        ], today: "2026-03-05")[0]
        #expect(clean.isBroken == false)
        #expect(clean.isActive)

        let broken = ChallengeScorer.score([challenge(.noSpend)], entries: [
            .make("2026-03-04", "Coffee", 4),
        ], today: "2026-03-05")[0]
        #expect(broken.isBroken)
        #expect(broken.statusLabel == "Broken")
    }

    @Test("A category cap watches one category")
    func categoryCap() {
        let progress = ChallengeScorer.score(
            [challenge(.categoryCap, bucket: "food", target: 60)],
            entries: [
                .make("2026-03-03", "Lunch", 25, bucket: "food"),
                .make("2026-03-04", "Cinema", 200, bucket: "fun"),
            ],
            today: "2026-03-09")[0]
        #expect(progress.spent == 25)
        #expect(progress.hasEnded)
        #expect(progress.isWon)
    }
}

@Suite("Detected subscriptions")
struct SubscriptionTests {

    private let today = Day.on("2026-04-10")

    @Test("The same charge in three different months is a subscription")
    func detects() {
        let found = SubscriptionDetective.detect(entries: [
            .make("2026-01-05", "Netflix", 15.99, bucket: "subs"),
            .make("2026-02-05", "netflix", 15.99, bucket: "subs"),
            .make("2026-03-05", "Netflix ", 16.49, bucket: "subs"),
        ], recurring: [], today: today)
        #expect(found.count == 1)
        #expect(found.first?.occurrences == 3)
        #expect(found.first?.isTracked == false)
        #expect(found.first?.looksLapsed == false)
    }

    /// The store hands the ledger over newest first, which is the order that
    /// used to pick the oldest spelling and the category it started out in.
    @Test("It's named and filed by its most recent charge")
    func usesTheLatestCharge() {
        let found = SubscriptionDetective.detect(entries: [
            .make("2026-03-05", "Netflix", 15.99, bucket: "subs"),
            .make("2026-02-05", "netflix", 15.99, bucket: "fun"),
            .make("2026-01-05", "NETFLIX", 15.99, bucket: "fun"),
        ], recurring: [], today: today)
        #expect(found.first?.place == "Netflix")
        #expect(found.first?.bucket == "subs")
        #expect(found.first?.daysSinceLast == 36)
    }

    @Test("Three visits in one month, or wildly different amounts, are not")
    func ignoresLookalikes() {
        let sameMonth = SubscriptionDetective.detect(entries: [
            .make("2026-03-01", "Cafe", 5), .make("2026-03-02", "Cafe", 5),
            .make("2026-03-03", "Cafe", 5),
        ], recurring: [], today: today)
        #expect(sameMonth.isEmpty)

        let uneven = SubscriptionDetective.detect(entries: [
            .make("2026-01-05", "Grocer", 40), .make("2026-02-05", "Grocer", 95),
            .make("2026-03-05", "Grocer", 62),
        ], recurring: [], today: today)
        #expect(uneven.isEmpty)
    }

    @Test("One that's already a recurring item says so")
    func tracked() {
        let found = SubscriptionDetective.detect(entries: [
            .make("2026-01-05", "Gym", 30), .make("2026-02-05", "Gym", 30),
            .make("2026-03-05", "Gym", 30),
        ], recurring: [.make("gym", 30, day: 5)], today: today)
        #expect(found.first?.isTracked == true)
    }
}

@Suite("Loans and goals")
struct LoanAndGoalTests {

    private func loan(balance: Double, rate: Double, payment: Double) -> Loan {
        Loan(id: "l", name: "Car", balance: balance, rate: rate,
             monthlyPayment: payment, createdAt: Date())
    }

    private func goal(target: Double = 1000, saved: Double = 250, monthly: Double = 0,
                      deadline: String = "") -> Goal {
        Goal(id: "g", name: "Holiday", target: target, saved: saved,
             monthlyContribution: monthly, deadline: deadline, createdAt: Date())
    }

    @Test("Interest-free payoff is simple division")
    func interestFree() {
        let result = loan(balance: 1200, rate: 0, payment: 100)
        #expect(result.monthsToClear == 12)
        #expect(result.payoffLabel == "1 year to clear")
        #expect(result.projectedInterest == 0)
    }

    @Test("Interest lengthens the payoff")
    func amortised() {
        // 1% a month on 1,000 at 100 a month: 10.6 months, so 11.
        let result = loan(balance: 1000, rate: 12, payment: 100)
        #expect(result.monthsToClear == 11)
        #expect(result.projectedInterest == 100)
    }

    @Test("A payment that only meets the interest never clears it")
    func neverClears() {
        let result = loan(balance: 1000, rate: 12, payment: 10)
        #expect(result.monthsToClear == nil)
        #expect(result.payoffLabel == "Payment doesn't cover the interest")
        #expect(loan(balance: 1000, rate: 12, payment: 0).payoffLabel == "No payment set")
    }

    @Test("Goal progress")
    func progress() {
        let result = goal(monthly: 100)
        #expect(result.remaining == 750)
        #expect(result.fraction == 0.25)
        #expect(result.monthsToTarget == 8)
        #expect(result.isComplete == false)
        #expect(goal(saved: 1000).isComplete)
        // No target set shouldn't read as finished.
        #expect(goal(target: 0, saved: 50).isComplete == false)
        #expect(goal(target: 0, saved: 50).fraction == 0)
    }

    @Test("A deadline says what each month has to carry")
    func deadline() {
        let today = Day.on("2026-03-10")
        let result = goal(monthly: 100, deadline: "2026-06-10")
        #expect(result.monthsLeft(from: today) == 3)
        #expect(result.requiredMonthly(from: today) == 250)
        #expect(result.isBehind(on: today))
        // A part-month still has to be saved for.
        #expect(goal(deadline: "2026-06-11").monthsLeft(from: today) == 4)
        #expect(goal(deadline: "2026-03-01").isOverdue(on: today))
    }
}
