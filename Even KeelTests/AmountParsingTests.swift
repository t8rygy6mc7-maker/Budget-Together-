import Foundation
import Testing
@testable import Even_Keel

// MARK: - Reading amounts
//
// Every path by which a number gets into the ledger: spoken, typed into the
// add sheet, typed into a limit box. These are the tests worth having first,
// because a parser that is wrong here is wrong about somebody's money, and
// wrong silently — "1,250" read as 1.25 looks like a perfectly good entry.

@Suite("Spoken amounts")
struct VoiceAmountParserTests {

    @Test("Digits, with whatever was said around them", arguments: [
        ("12.50 at Joe's", 12.5, "Joe's"),
        ("$12.50 coffee", 12.5, "coffee"),
        ("spent 40 dollars on groceries", 40, "groceries"),
        // "twelve fifty" often arrives from the recogniser as two groups.
        ("12 50 coffee", 12.5, "coffee"),
        ("7", 7, ""),
    ])
    func digits(phrase: String, amount: Double, remainder: String) {
        let parsed = VoiceAmountParser.parse(phrase)
        #expect(parsed.amount == amount)
        #expect(parsed.remainder == remainder)
    }

    /// The recogniser hands numbers back already formatted, so "twelve hundred
    /// and fifty dollars" arrives as "$1,250". Reading that comma as a decimal
    /// point logs $1.25 — a thousandfold error.
    @Test("A grouping separator is not a decimal point")
    func groupingSeparators() {
        #expect(VoiceAmountParser.parse("$1,250 rent").amount == 1250)
        #expect(VoiceAmountParser.parse("$1,250 rent").remainder == "rent")
        #expect(VoiceAmountParser.parse("12,345.67").amount == 12345.67)
    }

    @Test("Three trailing digits are a second number, not pence")
    func doesNotFoldThreeDigits() {
        #expect(VoiceAmountParser.parse("12 500").amount == 12)
    }

    @Test("Spelled-out numbers", arguments: [
        ("twelve", 12.0, ""),
        ("twenty-five dollars lunch", 25, "lunch"),
        ("one hundred", 100, ""),
        // Pounds-and-pence, said the way people say it.
        ("twelve fifty at the cafe", 12.5, "cafe"),
    ])
    func spelled(phrase: String, amount: Double, remainder: String) {
        let parsed = VoiceAmountParser.parse(phrase)
        #expect(parsed.amount == amount)
        #expect(parsed.remainder == remainder)
    }

    /// `NumberFormatter` will read "twelve fifty" as 1250 if asked. The parser
    /// must never return that.
    @Test("Never runs two spoken numbers together")
    func neverConcatenates() {
        #expect(VoiceAmountParser.parse("twelve fifty").amount != 1250)
        #expect(VoiceAmountParser.parse("twenty five").amount != 2005)
    }

    @Test("Says nothing when there is no usable number", arguments: [
        "", "   ", "coffee", "0", "2000000000",
    ])
    func noAmount(phrase: String) {
        #expect(VoiceAmountParser.parse(phrase).amount == nil)
    }

    @Test("The words around an amount are dropped from the place")
    func fillers() {
        #expect(VoiceAmountParser.strippedOfFillers("spent dollars at the Corner Shop")
                == "Corner Shop")
    }
}

@Suite("Typed amounts")
struct TypedAmountTests {

    @Test("An amount has to be a positive number within range")
    func amount() {
        #expect(Fmt.amount(from: "12.50") == 12.5)
        #expect(Fmt.amount(from: "  8 ") == 8)
        #expect(Fmt.amount(from: "") == nil)
        #expect(Fmt.amount(from: "abc") == nil)
        #expect(Fmt.amount(from: "0") == nil)
        #expect(Fmt.amount(from: "-5") == nil)
        #expect(Fmt.amount(from: "2000000000") == nil)
    }

    /// A limit differs from an amount in one way that matters: an empty box is
    /// an answer ("no limit"), not a failure.
    @Test("A cleared limit is zero, and nonsense is left alone")
    func limit() {
        #expect(Fmt.limit(from: "") == 0)
        #expect(Fmt.limit(from: "250") == 250)
        #expect(Fmt.limit(from: "-20") == 0)
        #expect(Fmt.limit(from: "abc") == nil)
        #expect(Fmt.limit(from: "99999999999") == Fmt.maxAmount)
    }

    @Test("Whole-number rounding never traps")
    func whole() {
        #expect(Fmt.whole(.nan) == 0)
        #expect(Fmt.whole(.infinity) == 0)
        #expect(Fmt.whole(61.6) == 62)
    }

    @Test("A share that rounds to nothing still isn't zero")
    func share() {
        #expect(Fmt.share(61.6) == "62%")
        #expect(Fmt.share(0.4) == "<1%")
        #expect(Fmt.share(0.4, spoken: true) == "under 1%")
    }

    @Test("Counts and field values")
    func countsAndPlain() {
        #expect(Fmt.count(1, "day") == "1 day")
        #expect(Fmt.count(3, "day") == "3 days")
        #expect(Fmt.count(2, "entry", plural: "entries") == "2 entries")
        #expect(Fmt.plain(12) == "12")
        // Formatted for wherever the tests are running, so the separator is
        // asked for rather than assumed.
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(Fmt.plain(12.5) == "12\(separator)50")
    }

    /// An amount put into a field has to read back as itself. Where the full
    /// stop groups thousands, a hardcoded "12.50" read back as 1,250 — and
    /// editing an entry puts its amount in a field and reads it back on save.
    @Test("An amount written into a field reads back unchanged", arguments: [
        12.5, 0.05, 4.1, 1234.56, 250, 999_999.99,
    ])
    func fieldRoundTrip(amount: Double) {
        #expect(Fmt.amount(from: Fmt.plain(amount)) == amount)
    }

    @Test("Ordinals", arguments: [
        (1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"),
        (12, "12th"), (13, "13th"), (21, "21st"), (22, "22nd"), (28, "28th"),
    ])
    func ordinal(day: Int, expected: String) {
        #expect(Recurring.ordinal(day) == expected)
    }
}
