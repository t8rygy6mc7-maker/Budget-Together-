import Foundation
import Testing
@testable import Even_Keel

// MARK: - The model, against a real store
//
// Everything above this file tests a function. These test the arithmetic the
// screens actually read, with an in-memory Core Data stack underneath — the
// same one the previews use, so nothing here touches the real ledger or
// iCloud.
//
// `AppModel` asks the clock for "now" rather than being handed it, so each
// test builds its ledger relative to today and asserts things that hold on
// any date. Serialised because the category registry is shared state.

@Suite("AppModel", .serialized)
struct AppModelTests {

    private let store: BudgetStore
    private let model: AppModel

    init() {
        store = BudgetStore(inMemory: true)
        model = AppModel(store: store)
        model.createHousehold(name: "Test", ownerName: "Me")
    }

    private var me: String { model.members[0].id }

    private func spend(_ amount: Double, _ place: String = "Shop", bucket: String = "food",
                       oneOff: Bool = false, on day: Date = Date()) {
        model.addEntry(place: place, amount: amount, bucket: bucket, memberID: me,
                       belowTheLine: oneOff, on: day)
    }

    // MARK: Plan

    @Test("A new budget has no limits, and that isn't a broken state")
    func startsWithNoPlan() {
        #expect(model.hasHousehold)
        #expect(model.hasPlan == false)
        #expect(model.capTotal == 0)
        #expect(model.wins.streak == 0)
    }

    @Test("A monthly figure is split into limits that add back up to it")
    func scaledPlan() {
        let scaled = AppModel.caps(forMonthlyTotal: AppModel.defaultTotal * 2)
        #expect(scaled.values.reduce(0, +) == AppModel.defaultTotal * 2)
        #expect(scaled["housing"] == 2600)
    }

    @Test("A limit can't be negative or not-a-number")
    func limitsAreClamped() {
        model.setCap("food", to: -40)
        #expect(model.caps["food"] == 0)
        model.setCap("food", to: .nan)
        #expect(model.caps["food"] == 0)
        model.setCap("food", to: 300)
        #expect(model.caps["food"] == 300)
        #expect(model.hasPlan)
    }

    @Test("Moving money between categories leaves the plan total alone")
    func movingMoney() {
        model.setCap("food", to: 500)
        model.setCap("fun", to: 200)
        model.moveBudget(from: "food", to: "fun", amount: 50)
        #expect(model.caps["food"] == 450)
        #expect(model.caps["fun"] == 250)
        #expect(model.capTotal == 700)
        // You can't lend out more than the category holds.
        model.moveBudget(from: "fun", to: "food", amount: 9000)
        #expect(model.caps["fun"] == 250)
    }

    // MARK: Spending figures

    @Test("One-offs and income stay out of what's been spent")
    func whatCountsAsSpent() {
        spend(50)
        spend(900, "Laptop", bucket: "shopping", oneOff: true)
        model.addEntry(place: "Payday", amount: 2000, bucket: "salary",
                       memberID: me, kind: .income)

        #expect(model.spent == 50)
        #expect(model.earned == 2000)
        #expect(model.month.belowTheLine == 900)
        #expect(model.month.totals["shopping"] == nil)
        #expect(model.totalEntryCount == 3)
    }

    @Test("What's left never goes below zero")
    func leftIsClamped() {
        model.setCap("food", to: 100)
        spend(130)
        #expect(model.left == 0)
        #expect(model.safeDaily == 0)
    }

    @Test("Today is a day that's left")
    func daysLeft() {
        let calendar = Calendar.current
        let length = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
        let today = calendar.component(.day, from: Date())
        #expect(model.daysLeft == length - today + 1)
        #expect(model.daysLeft >= 1)
        #expect(model.daysLeftInWeek >= 1 && model.daysLeftInWeek <= 7)
    }

    // MARK: Dates

    @Test("An entry is filed under the day it's given")
    func backdated() {
        let yesterday = Day.fromToday(-1)
        spend(12, on: yesterday)
        #expect(store.loadSnapshot().entries.first?.date == Fmt.isoDay(yesterday))
    }

    @Test("An entry can't be dated in the future")
    func futureIsClamped() {
        spend(12, on: Day.fromToday(3))
        #expect(store.loadSnapshot().entries.first?.date == Fmt.isoDay(Date()))
    }

    // MARK: Suggested limits

    @Test("A suggestion waits for a fortnight of spending")
    func suggestionNeedsHistory() {
        for _ in 0..<10 { spend(14) }
        #expect(model.canSuggestPlan == false)      // ten entries, one day

        spend(14, on: Day.fromToday(-13))
        #expect(model.canSuggestPlan)

        model.setCap("food", to: 100)
        #expect(model.canSuggestPlan == false)      // nothing to suggest once there's a plan
    }

    @Test("Day-to-day spending is scaled by the days it covers")
    func suggestionScalesVariableSpending() {
        // $140 on food, all of it today. Read as a whole month that's a $175
        // limit; it's really a fortnight at most, so the limit is about double.
        for _ in 0..<10 { spend(14) }
        let plan = model.suggestedPlan()
        // 140 / (14 / 30.44) * 1.1 = 334.84, rounded up to the next 25.
        #expect(plan["food"] == 350)
    }

    @Test("A fixed bill isn't stretched the same way")
    func suggestionLeavesFixedBillsAlone() {
        spend(1200, "Rent", bucket: "housing")
        // Once a month whatever day logging began: 1,200 plus headroom, not 2,600.
        #expect(model.suggestedPlan()["housing"] == 1350)
    }

    @Test("One-offs never become a limit")
    func suggestionIgnoresOneOffs() {
        spend(20)
        spend(900, "Laptop", bucket: "shopping", oneOff: true)
        #expect(model.suggestedPlan()["shopping"] == nil)
    }

    // MARK: Recurring

    @Test("A recurring bill posts once a month, however often the app reloads")
    func recurringPostsOnce() {
        model.saveRecurring(.make("Rent", 1200, day: 1))
        model.reload()
        model.reload()

        let rent = store.loadSnapshot().entries.filter { $0.place == "Rent" }
        #expect(rent.count == 1)
        #expect(rent.first?.date == Fmt.isoMonth(Date()) + "-01")
        #expect(model.recurring.first?.lastPostedMonth == Fmt.isoMonth(Date()))
    }

    /// Two phones on one budget each post the rent before hearing from the
    /// other. The copies carry the same id, and the earlier one is kept.
    @Test("The same bill posted twice for one month collapses to one entry")
    func repeatedPostingCollapses() {
        let rent = Recurring.make("Rent", 1200, day: 1)
        model.saveRecurring(rent)

        let month = Fmt.isoMonth(Date())
        let id = BudgetStore.postingID(recurring: rent.id, month: month)
        #expect(store.loadSnapshot().entries.map(\.id) == [id])

        // The other phone's copy arriving, written a minute before this one.
        store.addEntry(id: id, date: month + "-01", place: "Rent (theirs)", amount: 1200,
                       bucket: "housing", memberID: me,
                       createdAt: Date().addingTimeInterval(-60))
        model.reload()

        let posted = store.loadSnapshot().entries.filter { $0.id == id }
        #expect(posted.map(\.place) == ["Rent (theirs)"])
        #expect(model.spent == 1200)
    }

    // MARK: More than one budget

    /// Built-in categories have the same ids in every budget, so anything that
    /// finds one by id alone can land on the wrong budget's row.
    @Test("Renaming a category changes it in this budget only")
    func categoriesBelongToTheirBudget() {
        let first = store.currentHouseholdID ?? ""
        _ = store.loadSnapshot()                      // seeds the first budget's categories
        store.createHousehold(name: "Second", defaultCaps: [:])
        let second = store.currentHouseholdID ?? ""
        #expect(first != second)

        let food = store.loadSnapshot().categories.first { $0.id == "food" }!
        store.saveCategory(Bucket(id: food.id, label: "Eating", hex: food.hex,
                                  light: food.lightHex, symbol: food.symbol,
                                  sortOrder: food.sortOrder))
        #expect(store.loadSnapshot().categories.first { $0.id == "food" }?.label == "Eating")

        store.switchHousehold(to: first)
        #expect(store.loadSnapshot().categories.first { $0.id == "food" }?.label == "Food & Drink")
        #expect(store.loadSnapshot().categories.count == Bucket.builtInAll.count)
    }

    // MARK: Undo

    @Test("Undoing your own removal makes this device you again")
    func undoRestoresWhoYouAre() {
        model.addMember(name: "Sam")
        #expect(model.me?.id == me)
        let mine = me

        model.removeMember(mine)
        #expect(model.me == nil)

        model.undo()
        #expect(model.me?.id == mine)
        #expect(model.members.count == 2)
    }

    // MARK: Browsing months

    @Test("Looking at another month doesn't re-judge this one")
    func streakSurvivesBrowsing() {
        model.setCap("food", to: 3000)
        spend(10)
        let before = model.wins
        let allowance = model.dailyAllowance

        model.stepMonth(-1)
        #expect(model.isCurrentMonth == false)
        #expect(model.wins.streak == before.streak)
        #expect(model.wins.earned.map(\.id) == before.earned.map(\.id))
        #expect(model.dailyAllowance == allowance)

        model.goToCurrentMonth()
        #expect(model.isCurrentMonth)
    }

    @Test("Limits belong to the month they were set in, and carry forward")
    func capsAreMonthly() {
        model.stepMonth(-1)
        model.setCap("food", to: 200)
        model.goToCurrentMonth()
        // Last month's limit is still in force until this month sets its own.
        #expect(model.caps["food"] == 200)
        model.setCap("food", to: 350)
        model.stepMonth(-1)
        #expect(model.caps["food"] == 200)
    }
}

// MARK: - Badges, against the store

@Suite("Badges in the app", .serialized)
struct BadgeModelTests {

    private let store: BudgetStore
    private let model: AppModel

    init() {
        store = BudgetStore(inMemory: true)
        model = AppModel(store: store)
    }

    private var me: String { model.members[0].id }
    private var earned: Set<String> { Set(model.wins.earned.map(\.id)) }

    /// A budget created with a monthly figure has limits from before its first
    /// entry, and every empty month behind it used to count as one finished
    /// inside the plan.
    @Test("A brand-new budget with limits hasn't earned months it never had")
    func newBudgetWithLimits() {
        model.createHousehold(name: "Test", ownerName: "Me", monthlyTotal: 3000)
        #expect(model.hasPlan)
        #expect(model.wins.monthsUnderBudget == 0)
        #expect(model.wins.streak == 0)
        #expect(earned == ["planned"])
    }

    @Test("A month only counts once it has entries, judged by the limits it had")
    func closedMonthFromTheStore() {
        model.createHousehold(name: "Test", ownerName: "Me", monthlyTotal: 3000)
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        model.addEntry(place: "Shop", amount: 40, bucket: "food", memberID: me, on: lastMonth)

        #expect(model.wins.monthsUnderBudget == 1)
        #expect(earned.contains("month"))
        // With a month behind it, the whole of this month counts for the streak.
        #expect(model.wins.streak == Calendar.current.component(.day, from: Date()))
    }

    @Test("A newly earned badge is new until the sheet has been opened")
    func newBadges() {
        model.createHousehold(name: "Test", ownerName: "Me")
        #expect(model.newBadgeIDs.isEmpty)

        model.setCap("food", to: 300)
        model.reload()
        #expect(model.newBadgeIDs == ["planned"])

        model.markBadgesSeen()
        #expect(model.newBadgeIDs.isEmpty)
        model.reload()
        #expect(model.newBadgeIDs.isEmpty)
    }

    @Test("What's already earned when a budget is first seen isn't announced")
    func existingBadgesAreTakenAsRead() {
        model.createHousehold(name: "Test", ownerName: "Me", monthlyTotal: 3000)
        // A second model on the same store stands in for the app after an
        // update: the ledger has earned badges, and nothing is on record yet.
        store.setSeenBadges(nil, household: store.currentHouseholdID ?? "")
        let relaunched = AppModel(store: store)
        #expect(relaunched.wins.earned.isEmpty == false)
        #expect(relaunched.newBadgeIDs.isEmpty)
    }

    @Test("Setting things up earns the setting-up badges")
    func settingUp() {
        model.createHousehold(name: "Test", ownerName: "Me")
        model.saveRecurring(.make("Payday", 2000, day: 1, bucket: "salary", kind: .income))
        model.saveGoal(Goal(id: UUID().uuidString, name: "Trip", target: 1000, saved: 600,
                            monthlyContribution: 0, deadline: "", createdAt: Date()))
        #expect(earned.isSuperset(of: ["autopilot", "goal", "halfway"]))
        #expect(!earned.contains("reached"))
    }
}

// MARK: - Bills still to come

/// The daily figure, with a bill that hasn't landed yet.
///
/// These need a bill due *later this month*, which doesn't exist on the last
/// day of one — recurring days stop at the 28th so that every month has them.
/// On those few days the suite has nothing to test and says so by not running,
/// rather than passing vacuously.
@Suite("Safe to spend", .serialized,
       .enabled(if: Calendar.current.component(.day, from: Date()) < Recurring.maxDay,
                "No recurring day falls later than today this month"))
struct SafeToSpendTests {

    private let model: AppModel
    private let later = Recurring.maxDay

    init() {
        model = AppModel(store: BudgetStore(inMemory: true))
        model.createHousehold(name: "Test", ownerName: "Me")
    }

    private var me: String { model.members[0].id }

    @Test("A bill still to come is held back from the daily figure, not from what's left")
    func billIsHeldBack() {
        model.setCap("housing", to: 1300)
        model.setCap("food", to: 600)
        model.saveRecurring(.make("Rent", 1200, day: later))

        #expect(model.left == 1900)
        #expect(model.reservedForBills() == 1200)
        #expect(model.safeDaily == 700 / Double(model.daysLeft))
        #expect(model.billReserve().bills.map(\.place) == ["Rent"])
    }

    @Test("A bill outside the plan has nothing of the plan's to hold")
    func billWithNoLimit() {
        model.setCap("food", to: 600)
        model.saveRecurring(.make("Rent", 1200, day: later))

        #expect(model.reservedForBills() == 0)
        #expect(model.safeDaily == 600 / Double(model.daysLeft))
        #expect(model.billReserve().bills.isEmpty)
    }

    @Test("A bill can only claim the room its category has left")
    func billBiggerThanItsCategory() {
        model.setCap("housing", to: 1000)
        model.addEntry(place: "Repair", amount: 300, bucket: "housing", memberID: me)
        model.saveRecurring(.make("Rent", 1200, day: later))

        #expect(model.reservedForBills() == 700)
        #expect(model.safeDaily == 0)
    }

    @Test("Paydays, paused items and bills already posted aren't held back")
    func whatIsNotABillToCome() {
        model.setCap("housing", to: 1300)
        model.saveRecurring(.make("Payday", 3000, day: later, bucket: "salary", kind: .income))
        model.saveRecurring(.make("Paused", 100, day: later, isActive: false))
        model.saveRecurring(.make("Posted", 100, day: later,
                                  lastPosted: Fmt.isoMonth(Date())))
        #expect(model.billsStillToCome.isEmpty)
        #expect(model.reservedForBills() == 0)
    }

    @Test("The simplified view holds back only what its figure still contains")
    func simplifiedView() {
        model.setCap("housing", to: 1300)      // fixed: already outside the fun money
        model.setCap("personal", to: 200)      // variable
        model.saveRecurring(.make("Rent", 1200, day: later))
        model.saveRecurring(.make("Gym", 40, day: later, bucket: "personal"))

        #expect(model.reservedForBills() == 1240)
        #expect(model.reservedForBills(discretionaryOnly: true) == 40)
        #expect(model.funDaily == 160 / Double(model.daysLeft))
    }

    @Test("Looking at a closed month, nothing is held back")
    func closedMonth() {
        model.setCap("housing", to: 1300)
        model.saveRecurring(.make("Rent", 1200, day: later))
        model.stepMonth(-1)
        #expect(model.reservedForBills() == 0)
    }

    @Test("The line on Home names a single bill and counts several")
    func copy() {
        let one = Copy.billsLeftOut(reserved: 1200, bills: [.make("Rent", 1200, day: 5)])
        #expect(one == "A day from here leaves out \(Fmt.money(1200)) for Rent on the 5th.")
        let two = Copy.billsLeftOut(reserved: 1240, bills: [
            .make("Rent", 1200, day: 5), .make("Gym", 40, day: 20),
        ])
        #expect(two == "A day from here leaves out \(Fmt.money(1240)) for 2 bills still to come.")
    }
}
