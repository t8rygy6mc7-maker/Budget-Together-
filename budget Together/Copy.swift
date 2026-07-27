import Foundation

// MARK: - Copy
//
// One place for the sentences the app says about someone's money, so tone is a
// single decision rather than fifty scattered ones.
//
// Two rules hold everything here together:
//
// 1. **Lead with a sentence, not a scoreboard.** A large number and a red
//    percentage badge is a verdict delivered before any context. "You're doing
//    fine — $840 left, 12 days to go" is the same information arranged so the
//    reassurance arrives first and the arithmetic second.
//
// 2. **Never imply a moral failing.** The app is allowed to say a number is
//    higher than a plan. It is not allowed to suggest that means the person is
//    bad at this. "Over budget" became "past the plan"; alerts describe a
//    position, not a transgression.
//
// The vocabulary swap that fell out of it: "cap" → "limit" or "plan",
// "household" → "budget" / "everyone", "obligations"/"committed" → "the fixed
// stuff", "discretionary" → "yours to spend".

enum Copy {

    // MARK: The line at the top of Home

    /// How the month is going, in one sentence. Deliberately vague where the
    /// data is vague: early in a month, with a handful of entries, no honest
    /// verdict exists and pretending otherwise is how these apps lose trust.
    struct Summary {
        let headline: String
        let detail: String
        /// Whether this is a "look at this" line rather than a calm one. Only
        /// ever true when something genuinely needs a decision.
        let needsAttention: Bool
    }

    /// - Parameters:
    ///   - hasPlan: whether any limits are set at all.
    ///   - left: what remains of the plan.
    ///   - daysLeft: days remaining in the month.
    ///   - spent: spent so far this month.
    ///   - projected: where the month lands at the current rate.
    ///   - plan: the plan total.
    ///   - entryCount: entries logged this month, for the "too early to say" case.
    ///   - isCurrentMonth: past months get a retrospective line instead.
    ///   - name: what to call the reader, when we know.
    static func summary(hasPlan: Bool, left: Double, daysLeft: Int, spent: Double,
                        projected: Double, plan: Double, entryCount: Int,
                        isCurrentMonth: Bool, isUnusualMonth: Bool,
                        name: String?) -> Summary {
        // "You" is the default name for whoever set the budget up, and
        // addressing someone by it produces "You, you're doing fine." Anything
        // that isn't a real name is dropped rather than pasted in.
        let greeting: String? = name.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  trimmed.caseInsensitiveCompare("You") != .orderedSame else { return nil }
            return trimmed
        }
        let you = greeting.map { "\($0), " } ?? ""

        guard isCurrentMonth else {
            return Summary(
                headline: "That month is done.",
                detail: spent > 0 ? "\(Fmt.money(spent)) went out in total."
                                  : "Nothing was logged.",
                needsAttention: false
            )
        }

        if isUnusualMonth {
            return Summary(
                headline: "You've marked this month as unusual.",
                detail: "It still shows up here, but it won't count against your streak or your averages.",
                needsAttention: false
            )
        }

        guard entryCount > 0 else {
            return Summary(
                headline: "Nothing logged yet this month.",
                detail: "Add whatever you spent today and this fills itself in.",
                needsAttention: false
            )
        }

        // Without limits there's nothing to be over or under, so the app
        // reports rather than judges. This is the normal state for a new
        // household now, not an error to nag about.
        guard hasPlan else {
            return Summary(
                headline: "\(Fmt.money(spent)) so far this month.",
                detail: "No limits set — just keeping track for now.",
                needsAttention: false
            )
        }

        // Too little of the month gone, or too little logged, for a projection
        // to mean anything. Saying "on track" here would be a guess wearing a
        // confident voice.
        let elapsed = plan > 0 ? spent / plan : 0
        if daysLeft > 24 || elapsed < 0.05 {
            return Summary(
                headline: "\(you.isEmpty ? "Off" : you + "off") to a quiet start.",
                detail: "\(Fmt.money(spent)) so far. Too early to call it either way.",
                needsAttention: false
            )
        }

        if left <= 0 {
            return Summary(
                headline: "You're past the plan for this month.",
                detail: "\(Fmt.money(spent - plan)) over, with \(Fmt.count(daysLeft, "day")) to go. "
                      + "Moving money between categories might be all it takes.",
                needsAttention: true
            )
        }

        if projected > plan * 1.1 {
            return Summary(
                headline: "This one's running a bit warm.",
                detail: "At this rate you'd finish around \(Fmt.money(projected)), "
                      + "against a plan of \(Fmt.money(plan)).",
                needsAttention: true
            )
        }

        return Summary(
            headline: "\(you.isEmpty ? "You're" : you + "you're") doing fine.",
            detail: "\(Fmt.money(left)) left, \(Fmt.count(daysLeft, "day")) to go.",
            needsAttention: false
        )
    }

    // MARK: Streaks

    static func streakLine(days: Int, graceUsed: Bool) -> String {
        switch days {
        case 0:  "Start a streak today"
        case 1:  "One day inside your daily allowance"
        default: "\(days) days inside your daily allowance"
                 + (graceUsed ? " — one slip forgiven" : "")
        }
    }

    // MARK: Notifications

    /// Cap alerts, rewritten. The old copy ("Food is over budget") named a
    /// failure; these name a position and leave the judgement to the reader.
    static func limitAlert(bucket: String, spent: Double, limit: Double)
        -> (title: String, body: String) {
        if spent >= limit {
            return ("\(bucket) has hit its limit",
                    "\(Fmt.money(spent)) of \(Fmt.money(limit)). "
                  + "You can move some room over from another category if you need it.")
        }
        let left = limit - spent
        return ("\(bucket): \(Fmt.money(left)) left",
                "\(Fmt.money(spent)) of \(Fmt.money(limit)) used so far this month.")
    }
}
