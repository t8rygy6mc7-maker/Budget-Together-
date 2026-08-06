import Foundation

// MARK: - Formatting
//
// Every formatter here is built once and reused. `NumberFormatter`/`DateFormatter`
// are expensive to construct, and these run per row on every SwiftUI body
// evaluation. They're safe to share because the whole module is main-actor
// isolated.

enum Fmt {

    // MARK: Formatters

    /// Money is formatted in the user's own currency and their own conventions
    /// for where the symbol sits and how digits are grouped. The app never
    /// converts between currencies — it has no rates and no bank connection —
    /// so this is presentation only: whatever they type is whatever they meant.
    private static let whole: NumberFormatter = currency(fractionDigits: 0)
    private static let cents: NumberFormatter = currency(fractionDigits: 2)

    private static func currency(fractionDigits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f
    }

    private static let thousands: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.maximumFractionDigits = 1
        return f
    }()

    /// Just the symbol, for the amount fields that draw their own prefix.
    static let currencySymbol: String = whole.currencySymbol ?? "$"

    /// Parses user input, so it must accept whatever the decimal pad produces
    /// in the user's locale ("12,50" as well as "12.50").
    private static let input: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.isLenient = true
        return f
    }()

    /// Fixed-format storage dates. `en_US_POSIX` keeps the pattern stable
    /// regardless of the user's locale; the time zone stays local, because a
    /// "day" here means the user's calendar day.
    private static let isoDayFormatter = fixed("yyyy-MM-dd")
    private static let isoMonthFormatter = fixed("yyyy-MM")

    private static let weekdayFormatter = display("EEEE, MMM d")
    /// Localised medium date — "12 Mar 2027". Built from a style rather than a
    /// pattern because a date this far out is read, not scanned, and the order
    /// of its parts should be the reader's own.
    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    private static let monthYearFormatter = display("LLLL yyyy")
    private static let monthNameFormatter = display("LLLL")
    private static let shortMonthFormatter = display("LLL")

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static func display(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = template
        return f
    }

    // MARK: Money

    /// "$1,234" — whole units, for headline and summary figures.
    static func money(_ n: Double) -> String {
        whole.string(from: NSNumber(value: n)) ?? currencySymbol + "0"
    }

    /// "$1,234.56" — exact amounts, for individual entries.
    static func money2(_ n: Double) -> String {
        cents.string(from: NSNumber(value: n)) ?? currencySymbol + "0.00"
    }

    /// "$1.2k" above a thousand, otherwise the plain amount. For bubble labels,
    /// where there is room for roughly five characters and no more.
    static func compact(_ n: Double) -> String {
        guard n >= 1000 else { return money(n) }
        let k = thousands.string(from: NSNumber(value: n / 1000)) ?? "0"
        return currencySymbol + k + "k"
    }

    /// Bare number for putting an existing amount back into a text field —
    /// no currency symbol, no grouping, and no trailing ".0" on whole dollars.
    static func plain(_ n: Double) -> String {
        n == n.rounded() ? String(whole(n)) : String(format: "%.2f", n)
    }

    /// The largest figure the app will accept on a single line.
    ///
    /// Not a limit anyone will meet: it's a billion, and this app is somebody
    /// logging a coffee. It's here because the alternative is unbounded, and an
    /// unbounded amount doesn't stay in its own row — it lands in a total, then
    /// an average, then a percentage, and one of those is an `Int(_:)` away
    /// from trapping. A typo with the decimal pad held down, or a Shortcut
    /// handing over a stray `Double`, shouldn't be able to make a screen
    /// un-openable.
    static let maxAmount: Double = 1_000_000_000

    /// Reads a typed amount, tolerating the user's decimal separator. Returns
    /// `nil` for anything that isn't a positive number within `maxAmount`.
    static func amount(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let value = input.number(from: trimmed)?.doubleValue ?? Double(trimmed)
        guard let value, value > 0, value.isFinite, value <= maxAmount else { return nil }
        return value
    }

    /// Reads a typed limit, where an empty field is a real answer rather than a
    /// failure to parse: clearing the box is how someone says "no limit", so it
    /// reads as 0. Out-of-range figures are clamped instead of rejected, and
    /// `nil` is kept for text that isn't a number at all — which lets a caller
    /// leave the stored limit alone rather than wipe it on a fumbled paste.
    static func limit(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = input.number(from: trimmed)?.doubleValue ?? Double(trimmed),
              value.isFinite else { return nil }
        return min(max(value, 0), maxAmount)
    }

    /// Rounds to a whole number without ever trapping.
    ///
    /// `Int(_:)` is a runtime trap on NaN, on an infinity and on anything past
    /// `Int.max`, and nearly every whole number the UI shows is the result of a
    /// division — a percentage, a share, a payoff term. Clamping is free and
    /// takes the whole family of crashes off the table, including for ledgers
    /// that already hold a bad figure from before `maxAmount` existed.
    static func whole(_ n: Double) -> Int {
        guard n.isFinite else { return 0 }
        return Int(min(max(n.rounded(), -1e15), 1e15))
    }

    /// "1 day" / "25 days".
    ///
    /// SwiftUI's `^[…](inflect: true)` markup only applies when the literal
    /// reaches `Text` as a `LocalizedStringKey`. Strings that are built up first
    /// — concatenated, returned from a property, stored in a model — arrive as
    /// plain `String` and render the markup verbatim, so they need this instead.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : plural ?? singular + "s")
    }

    // MARK: Dates

    /// Storage key for a day: "2026-07-24".
    static func isoDay(_ d: Date) -> String { isoDayFormatter.string(from: d) }

    /// Back the other way, for date maths on stored keys.
    static func day(from iso: String) -> Date? { isoDayFormatter.date(from: iso) }

    /// Storage key for a month: "2026-07". Entry dates begin with this, which is
    /// how the month filter works without parsing every date.
    static func isoMonth(_ d: Date) -> String { isoMonthFormatter.string(from: d) }

    /// "July 2026" — screen subtitles.
    static func monthTitle(_ d: Date) -> String { monthYearFormatter.string(from: d) }

    /// "June" — the comparison month in the home header.
    static func monthName(_ d: Date) -> String { monthNameFormatter.string(from: d) }

    /// "Jul" — axis labels on the trend chart.
    static func shortMonth(_ d: Date) -> String { shortMonthFormatter.string(from: d) }

    /// "12 Mar 2027" for a stored day key — a date far enough off that a
    /// weekday tells the reader nothing.
    static func dayTitle(_ iso: String) -> String {
        guard let day = isoDayFormatter.date(from: iso) else { return iso }
        return dayTitleFormatter.string(from: day)
    }

    /// "Today" / "Yesterday" / "Monday, Jul 20" for a stored day key.
    static func dateLabel(_ iso: String, today: String) -> String {
        guard let day = isoDayFormatter.date(from: iso),
              let now = isoDayFormatter.date(from: today) else { return iso }
        switch Calendar.current.dateComponents([.day], from: day, to: now).day {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return weekdayFormatter.string(from: day)
        }
    }
}
