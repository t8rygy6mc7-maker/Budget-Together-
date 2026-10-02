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

    private func wins(byDay: [Int: Double] = [:], allowance: Double = 100,
                      today: Int = 10, entries: Int = 0, tagged: Int = 0,
                      closed: [(spent: Double, cap: Double)] = []) -> Wins {
        Wins.make(byDay: byDay, dailyAllowance: allowance, today: today,
                  entryCount: entries, taggedCount: tagged, closedMonths: closed)
    }

    @Test("A day with no spending counts")
    func quietDaysCount() {
        let result = wins(byDay: [3: 40, 7: 99])
        #expect(result.streak == 10)
        #expect(result.graceUsed == false)
    }

    @Test("One day over is carried, not credited")
    func oneSlipIsForgiven() {
        let result = wins(byDay: [5: 250])
        #expect(result.streak == 9)
        #expect(result.graceUsed == true)
    }

    @Test("A second day over ends the run")
    func secondSlipEndsIt() {
        // Counting back from the 10th: 10, 9, 8, 7, 6 count; the 5th is
        // forgiven; the 4th counts; the 3rd ends it.
        let result = wins(byDay: [5: 250, 3: 250])
        #expect(result.streak == 6)
    }

    @Test("No allowance, no streak")
    func needsAnAllowance() {
        #expect(wins(allowance: 0).streak == 0)
    }

    @Test("Closed months count back from the newest")
    func monthsUnderBudget() {
        let result = wins(closed: [(90, 100), (110, 100), (80, 100), (70, 100)])
        #expect(result.monthsUnderBudget == 2)
        // A month with no plan can't have been inside one.
        #expect(wins(closed: [(90, 100), (10, 0)]).monthsUnderBudget == 0)
    }

    @Test("Badges are earned by the numbers and nothing else")
    func badges() {
        let none = wins()
        #expect(none.badges.first { $0.id == "logging" }?.isEarned == false)

        let some = wins(entries: 10, tagged: 10, closed: [(1, 2), (1, 2), (1, 2)])
        let earned = Set(some.earned.map(\.id))
        #expect(earned.isSuperset(of: ["logging", "aware", "week", "month", "threepeat"]))
        #expect(!earned.contains("fortnight"))
    }
}

@Suite("Forecast")
struct ForecastTests {

    private func forecast(spent: Double = 300, today: Int = 10,
                          recurring: [Recurring] = []) -> Forecast {
        Forecast.make(spent: spent, byDay: [:], today: today, daysInMonth: 30,
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
