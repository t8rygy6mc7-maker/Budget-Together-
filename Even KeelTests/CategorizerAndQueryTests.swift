import Foundation
import Testing
@testable import Even_Keel

// MARK: - Guessing a category, and answering a question
//
// The two places the app interprets what somebody typed. Both are rule-based
// on purpose, and both are meant to say nothing rather than guess — which is
// the behaviour most worth pinning down, because it's the first thing a
// "smarter" replacement would quietly lose.

@Suite("Category guesses")
struct CategorizerTests {

    private let history = HistoryCategorizer(entries: [
        .make("2026-03-01", "Joe's", 12, bucket: "fun"),
        .make("2026-03-08", "joe's ", 9, bucket: "fun"),
        .make("2026-03-09", "Trader Joe's", 60, bucket: "food"),
        .make("2026-03-10", "Payday", 900, bucket: "salary", kind: .income),
    ])

    @Test("This household's own history comes first")
    func exactMatch() {
        let guess = history.suggest(place: "JOE'S", kind: .expense)
        #expect(guess?.bucket == "fun")
        #expect(guess?.confidence == 0.95)
    }

    @Test("Seen once is less certain than seen twice")
    func seenOnce() {
        #expect(history.suggest(place: "Trader Joe's", kind: .expense)?.confidence == 0.8)
    }

    @Test("A place being typed matches what it starts")
    func prefix() {
        let guess = history.suggest(place: "trader", kind: .expense)
        #expect(guess?.bucket == "food")
        #expect(guess?.confidence == 0.7)
    }

    @Test("Keywords cover the cold start")
    func keywords() {
        let empty = HistoryCategorizer(entries: [])
        let guess = empty.suggest(place: "Starbucks", kind: .expense)
        #expect(guess?.bucket == "food")
        #expect((guess?.confidence ?? 0) >= CategoryGuess.threshold)
    }

    @Test("Says nothing for income, short names and places it hasn't met")
    func staysQuiet() {
        #expect(history.suggest(place: "Payday", kind: .income) == nil)
        #expect(history.suggest(place: "ab", kind: .expense) == nil)
        #expect(history.suggest(place: "Zzyzx", kind: .expense) == nil)
    }
}

@Suite("Ask")
struct QueryTests {

    private let engine = RuleQueryEngine()

    private var context: QueryContext {
        QueryContext(
            entries: [
                .make("2026-03-03", "Grocer", 20, bucket: "food", member: "a"),
                .make("2026-03-12", "Lunch", 30, bucket: "food", member: "b"),
                .make("2026-03-12", "Cinema", 15, bucket: "fun", member: "b"),
                .make("2026-03-10", "Laptop", 900, bucket: "shopping", member: "a", oneOff: true),
                .make("2026-03-01", "Payday", 2000, bucket: "salary", member: "a", kind: .income),
                .make("2026-02-20", "Grocer", 45, bucket: "food", member: "a"),
            ],
            caps: ["food": 200, "fun": 100],
            members: [
                Member(id: "a", name: "Ada", colorIndex: 0, createdAt: Date()),
                Member(id: "b", name: "Ben", colorIndex: 1, createdAt: Date()),
            ],
            today: Day.on("2026-03-15")
        )
    }

    @Test("A month's total leaves one-offs out, and says so")
    func monthTotal() {
        let answer = engine.answer("How much did I spend this month?", context: context)
        #expect(answer?.headline == Fmt.money2(65))
        #expect(answer?.detail?.contains(Fmt.money2(900)) == true)
        #expect(answer?.entries.count == 3)
    }

    @Test("A category, and another month")
    func categoryAndTimeframe() {
        #expect(engine.answer("how much on food", context: context)?.headline
                == Fmt.money2(50))
        #expect(engine.answer("what did we spend on food last month", context: context)?.headline
                == Fmt.money2(45))
    }

    @Test("What's left is measured against the limit")
    func remaining() {
        #expect(engine.answer("what's left for food?", context: context)?.headline
                == Fmt.money2(150))
        // The whole plan, with the one-off kept out of it.
        #expect(engine.answer("how much is left", context: context)?.headline
                == Fmt.money2(235))
    }

    @Test("No limit is said plainly rather than answered as zero")
    func noLimit() {
        let answer = engine.answer("what's left on transport", context: context)
        #expect(answer?.headline == "No limit set for Transport")
    }

    @Test("Who spent the most")
    func who() {
        // Ada's laptop is a one-off, but it is still money she spent.
        #expect(engine.answer("who spent the most this month", context: context)?.headline
                == "Ada")
    }

    @Test("Doesn't answer what it doesn't understand", arguments: [
        "", "hello there", "tell me a joke",
    ])
    func declines(question: String) {
        #expect(engine.answer(question, context: context) == nil)
    }
}
