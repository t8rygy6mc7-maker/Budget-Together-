import Foundation

// MARK: - Formatting
//
// Every formatter here is built once and reused. `NumberFormatter`/`DateFormatter`
// are expensive to construct, and these run per row on every SwiftUI body
// evaluation. They're safe to share because the whole module is main-actor
// isolated.

enum Fmt {

    // MARK: Formatters

    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let cents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let thousands: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f
    }()

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
    private static let monthYearFormatter = display("LLLL yyyy")
    private static let monthNameFormatter = display("LLLL")

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

    /// "$1,234" — whole dollars, for headline and summary figures.
    static func money(_ n: Double) -> String {
        "$" + (whole.string(from: NSNumber(value: n)) ?? "0")
    }

    /// "$1,234.56" — exact amounts, for individual entries.
    static func money2(_ n: Double) -> String {
        "$" + (cents.string(from: NSNumber(value: n)) ?? "0.00")
    }

    /// "$1.2k" above a thousand, otherwise plain dollars. For bubble labels.
    static func compact(_ n: Double) -> String {
        guard n >= 1000 else { return money(n) }
        let k = thousands.string(from: NSNumber(value: n / 1000)) ?? "0"
        return "$" + k + "k"
    }

    /// Reads a typed amount, tolerating the user's decimal separator. Returns
    /// `nil` for anything that isn't a positive number.
    static func amount(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let value = input.number(from: trimmed)?.doubleValue ?? Double(trimmed)
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    // MARK: Dates

    /// Storage key for a day: "2026-07-24".
    static func isoDay(_ d: Date) -> String { isoDayFormatter.string(from: d) }

    /// Storage key for a month: "2026-07". Entry dates begin with this, which is
    /// how the month filter works without parsing every date.
    static func isoMonth(_ d: Date) -> String { isoMonthFormatter.string(from: d) }

    /// "July 2026" — screen subtitles.
    static func monthTitle(_ d: Date) -> String { monthYearFormatter.string(from: d) }

    /// "June" — the comparison month in the home header.
    static func monthName(_ d: Date) -> String { monthNameFormatter.string(from: d) }

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
