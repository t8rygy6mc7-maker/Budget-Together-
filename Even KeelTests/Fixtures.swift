import Foundation
@testable import Even_Keel

// MARK: - Fixtures
//
// Shorthand for building ledger rows, so a test reads as the situation it
// describes rather than as twelve arguments.

extension Entry {
    /// An entry with everything a test doesn't care about filled in.
    static func make(_ date: String, _ place: String, _ amount: Double,
                     bucket: String = "food", member: String = "me",
                     kind: EntryKind = .expense, oneOff: Bool = false,
                     mood: Mood? = nil) -> Entry {
        Entry(id: UUID().uuidString, date: date, place: place, bucket: bucket,
              amount: amount, memberID: member, kind: kind, mood: mood,
              belowTheLine: oneOff, createdAt: Date())
    }
}

extension Recurring {
    static func make(_ place: String, _ amount: Double, day: Int,
                     bucket: String = "housing", kind: EntryKind = .expense,
                     isActive: Bool = true, lastPosted: String = "") -> Recurring {
        Recurring(id: UUID().uuidString, place: place, amount: amount, bucket: bucket,
                  memberID: "me", kind: kind, dayOfMonth: day, isActive: isActive,
                  lastPostedMonth: lastPosted)
    }
}

enum Day {
    /// Noon on a fixed date, for anything that takes "today" as an argument.
    /// Noon so no time zone can push it across midnight.
    static func on(_ iso: String) -> Date {
        let day = Fmt.day(from: iso) ?? Date()
        return Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
    }

    /// `offset` days from today, as a date.
    static func fromToday(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}
