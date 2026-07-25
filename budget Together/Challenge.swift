import Foundation

// MARK: - Challenges
//
// Time-bound and shared: a challenge belongs to the household, so everyone's
// spending counts toward it and everyone sees the same progress. Like badges,
// the result is derived from the ledger rather than stored — there's no state to
// keep in step, and no way to "win" without the entries agreeing.

enum ChallengeKind: String, CaseIterable {
    /// Spend nothing at all in the window.
    case noSpend
    /// Keep one category under a figure for the window.
    case categoryCap

    var label: String {
        switch self {
        case .noSpend:     "No spending"
        case .categoryCap: "Stay under"
        }
    }
}

struct Challenge: Identifiable, Hashable {
    let id: String
    var title: String
    var kind: ChallengeKind
    /// Only meaningful for `.categoryCap`.
    var bucket: String?
    var target: Double
    /// Inclusive day keys, "yyyy-MM-dd".
    var startDate: String
    var endDate: String
    var createdAt: Date

    func isActive(on day: String) -> Bool { day >= startDate && day <= endDate }
    func hasEnded(by day: String) -> Bool { day > endDate }

    /// Days in the window, inclusive.
    var length: Int {
        guard let start = Fmt.day(from: startDate), let end = Fmt.day(from: endDate),
              let days = Calendar.current.dateComponents([.day], from: start, to: end).day
        else { return 1 }
        return max(1, days + 1)
    }
}

/// Where a challenge stands right now.
struct ChallengeProgress {
    let challenge: Challenge
    /// Spending counted against it.
    let spent: Double
    let entryCount: Int
    let isActive: Bool
    let hasEnded: Bool

    /// A no-spend challenge is a pass/fail; a cap is a proportion.
    var fraction: Double {
        guard challenge.target > 0 else { return spent > 0 ? 1 : 0 }
        return min(1, spent / challenge.target)
    }

    /// Broken the moment spending passes the target — for a no-spend run, the
    /// moment anything is logged at all.
    var isBroken: Bool { spent > challenge.target }

    /// Only a finished, unbroken challenge counts as won.
    var isWon: Bool { hasEnded && !isBroken }

    var statusLabel: String {
        if isBroken { return hasEnded ? "Missed" : "Broken" }
        if isWon { return "Won" }
        if hasEnded { return "Done" }
        return "Running"
    }

    var detail: String {
        switch challenge.kind {
        case .noSpend:
            if isBroken {
                return "\(Fmt.money2(spent)) logged across \(Fmt.count(entryCount, "entry", plural: "entries"))"
            }
            return hasEnded ? "Nothing logged the whole time" : "Nothing logged yet"
        case .categoryCap:
            let name = challenge.bucket.map { Bucket.named($0).label } ?? "spending"
            return "\(Fmt.money2(spent)) of \(Fmt.money(challenge.target)) on \(name)"
        }
    }
}

extension Challenge {
    /// Ready-made challenges, with their windows worked out from today.
    static func templates(from today: Date) -> [Challenge] {
        var out: [Challenge] = []
        if let weekend = nextWeekend(from: today) {
            out.append(Challenge(id: UUID().uuidString, title: "No-Spend Weekend",
                                 kind: .noSpend, bucket: nil, target: 0,
                                 startDate: Fmt.isoDay(weekend.start),
                                 endDate: Fmt.isoDay(weekend.end), createdAt: today))
        }
        let calendar = Calendar.current
        if let weekEnd = calendar.date(byAdding: .day, value: 6, to: today) {
            out.append(Challenge(id: UUID().uuidString, title: "No-Spend Week",
                                 kind: .noSpend, bucket: nil, target: 0,
                                 startDate: Fmt.isoDay(today),
                                 endDate: Fmt.isoDay(weekEnd), createdAt: today))
            out.append(Challenge(id: UUID().uuidString, title: "Cheap Eats Week",
                                 kind: .categoryCap, bucket: "food", target: 60,
                                 startDate: Fmt.isoDay(today),
                                 endDate: Fmt.isoDay(weekEnd), createdAt: today))
            out.append(Challenge(id: UUID().uuidString, title: "Quiet Week Out",
                                 kind: .categoryCap, bucket: "fun", target: 40,
                                 startDate: Fmt.isoDay(today),
                                 endDate: Fmt.isoDay(weekEnd), createdAt: today))
        }
        return out
    }

    /// The coming Saturday and Sunday — or this one, if it's already the weekend.
    private static func nextWeekend(from today: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)   // 1 = Sunday
        let untilSaturday = weekday == 7 ? 0 : (weekday == 1 ? -1 : 7 - weekday)
        guard let saturday = calendar.date(byAdding: .day, value: untilSaturday, to: today),
              let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) else { return nil }
        return (saturday, sunday)
    }
}

enum ChallengeScorer {
    /// Scores every challenge against the ledger in one pass per challenge.
    /// Income never counts — a challenge is about what goes out.
    static func score(_ challenges: [Challenge], entries: [Entry], today: String) -> [ChallengeProgress] {
        challenges.map { challenge in
            let matched = entries.filter { entry in
                entry.kind == .expense
                    && entry.date >= challenge.startDate
                    && entry.date <= min(challenge.endDate, today)
                    && (challenge.bucket == nil || entry.bucket == challenge.bucket)
            }
            return ChallengeProgress(
                challenge: challenge,
                spent: matched.reduce(0) { $0 + $1.amount },
                entryCount: matched.count,
                isActive: challenge.isActive(on: today),
                hasEnded: challenge.hasEnded(by: today)
            )
        }
    }
}
