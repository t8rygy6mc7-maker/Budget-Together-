import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPeople = false
    @State private var showAsk = false
    /// Ties the People sheet to the button it opens from, so it grows out of the
    /// glass rather than sliding up from the bottom of the screen.
    @Namespace private var morph

    /// Avatars shown before the stack collapses into a "+N" badge.
    private static let maxAvatars = 3

    var body: some View {
        Page(title: "Even Keel") {
            VStack(alignment: .leading, spacing: Space.lg) {
                summaryLine

                // Anti-budget mode is entirely "what's left of the fun money",
                // which is a limits calculation. With no limits set it would report
                // a confident $0, so the mode simply isn't available until there's
                // a plan for it to subtract from.
                if showsFunMoney {
                    simplified
                } else {
                    full
                }
            }
        }
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                peopleButton.matchedTransitionSource(id: Self.peopleMorph, in: morph)
            } else {
                peopleButton
            }
        }
        // After the people button in the chain, which puts it first in the bar.
        .monthControls()
        .sheet(isPresented: $showPeople) {
            PeopleSheet().morphs(from: Self.peopleMorph, in: morph)
        }
        .sheet(isPresented: $showAsk) { AskSheet() }
    }

    private static let peopleMorph = "people"

    private var peopleButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showPeople = true } label: {
                // A wide display's floating tab bar leaves the trailing end short
                // of room, and the stack of faces fell into the overflow menu.
                if sizeClass == .regular {
                    Image(systemName: "person.2.fill")
                } else {
                    avatarStack
                }
            }
                .accessibilityLabel("^[\(model.members.count) person](inflect: true) on this budget")
                .accessibilityHint("Opens people and settings")
        }
    }

    /// Whether Home is showing the fun money rather than the whole plan.
    private var showsFunMoney: Bool { model.isSimplified && model.hasPlan }

    /// How the month is going, in a sentence, above everything else.
    ///
    /// The screen used to open with a large number and a red percentage badge —
    /// a verdict, delivered before any context, in the position the eye lands
    /// first. The arithmetic hasn't changed and it's all still below; it just
    /// isn't the greeting any more.
    private var summaryLine: some View {
        // In the simplified view the sentence has to be about the same money
        // as the number under it. Quoting the whole plan there put "$1,178
        // left" above "Free to spend $646", and a weekly figure bigger than
        // everything the screen said was free for the rest of the month.
        //
        // A closed month keeps the whole figure: its sentence is "$N went out
        // in total", and in total means everything.
        let fun = showsFunMoney && model.isCurrentMonth
        let summary = Copy.summary(
            hasPlan: model.hasPlan,
            left: fun ? model.funLeft : model.left,
            daysLeft: model.daysLeft,
            spent: fun ? model.funSpent : model.spent,
            projected: fun ? model.funProjected : model.forecast.projected,
            plan: fun ? model.funMoney : model.plannedTotal,
            entryCount: model.month.entries.count,
            isCurrentMonth: model.isCurrentMonth,
            isUnusualMonth: model.isSelectedMonthUnusual,
            name: model.me?.name
        )
        let leftForWeek = fun ? model.funLeft : model.left
        return VStack(alignment: .leading, spacing: Space.xxs) {
            Text(summary.headline)
                .appFont(19, weight: .semibold)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary.detail)
                .appFont(13)
                .foregroundStyle(summary.needsAttention ? Palette.overText : Palette.sub)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasPlan, leftForWeek > 0, model.weeklyFramingIsUseful {
                weeklyLine(allowance: fun ? model.funWeeklyAllowance : model.weeklyAllowance,
                           spent: model.spentThisWeek(discretionaryOnly: fun))
                    .padding(.top, Space.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The same allowance in the unit people actually think in. "$840 over 19
    /// days" is arithmetic; "about $180 between now and Sunday" is a decision
    /// you can make at a till.
    private func weeklyLine(allowance: Double, spent: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.day.timeline.left")
                .appFont(10, weight: .semibold)
            Text("About \(Fmt.money(allowance)) to see out the week"
               + (spent > 0 ? " — \(Fmt.money(spent)) gone so far" : ""))
                .appFont(11.5, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.teal)
    }

    /// What was spent this month but deliberately set aside from the plan.
    ///
    /// Every headline figure on this screen excludes it, which is the point —
    /// but excluding money from the totals without saying so is how an app
    /// starts quietly disagreeing with somebody's bank balance. So it gets a
    /// line of its own, stated as a deliberate choice rather than a warning.
    @ViewBuilder
    private var oneOffRow: some View {
        if model.month.belowTheLine > 0 {
            Button { model.tab = .log } label: {
                RowLabel(symbol: "minus.diamond.fill", color: Palette.moodJoy,
                         title: Text("\(Fmt.money(model.month.belowTheLine)) in one-offs"),
                         subtitle: Text("^[\(model.month.belowTheLineCount) thing](inflect: true) you set aside — not counted above"))
            }
            .buttonStyle(.row)
        }
    }

    /// The way to the Budget tab while it's still hidden from the bar. Without
    /// this, progressive disclosure would be a locked door rather than a tidy
    /// one — someone who arrives knowing exactly what they want to set up has
    /// to be able to go and set it up.
    ///
    /// It has to stay put for a household that already has a plan but hasn't
    /// earned the tab yet: the bar reveals Budget and Stats as a pair, so
    /// setting limits no longer puts Budget in the bar by itself, and this is
    /// the only door to them until it does.
    @ViewBuilder
    private var planRow: some View {
        if model.isCurrentMonth,
           !model.hasPlan || !model.visibleTabs.contains(.budget) {
            Button { model.reveal(.budget) } label: {
                RowLabel(symbol: "slider.horizontal.3",
                         title: Text(model.hasPlan ? "Your spending limits"
                                     : model.canSuggestPlan ? "Ready to set some limits?"
                                     : "Want to set spending limits?"),
                         subtitle: Text(model.hasPlan
                                        ? "Change them whenever they stop fitting."
                                        : model.canSuggestPlan
                                        ? "There's enough here now to suggest some."
                                        : "Optional — tracking works fine without them."))
            }
            .buttonStyle(.row)
        }
    }

    /// A running challenge, or an invitation to start one.
    private var challengeRow: some View {
        let running = model.featuredChallenge
        return NavigationLink(value: Route.challenges) {
            RowLabel(symbol: running?.isBroken == true ? "xmark.circle.fill" : "flag.fill",
                     color: running?.isBroken == true ? Palette.over : Palette.moodSocial,
                     title: Text(running?.challenge.title ?? "Take on a challenge"),
                     subtitle: Text(running?.detail ?? "No-Spend Weekend and others, together"))
        }
        .buttonStyle(.row)
    }

    private var askRow: some View {
        Button { showAsk = true } label: {
            RowLabel(symbol: "sparkle.magnifyingglass", color: Palette.moodRoutine,
                     title: Text("Ask about your spending"))
        }
        .buttonStyle(.row)
        .accessibilityLabel("Ask a question about your spending")
    }

    /// The forecast in one line, as a way into the full breakdown. Hidden until
    /// there's enough of the month behind it to mean anything.
    @ViewBuilder
    private var forecastRow: some View {
        if model.isCurrentMonth, model.forecast.isReliable {
            let over = model.forecast.isOverPlan
            NavigationLink(value: Route.insights) {
                RowLabel(symbol: over ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis",
                         color: over ? Palette.over : Palette.teal,
                         title: Text("Heading for \(Fmt.money(model.forecast.projected))"),
                         subtitle: Text(over
                                        ? "\(Fmt.money(model.forecast.overBy)) over plan at this rate"
                                        : "\(Fmt.money(model.forecast.underBy)) under plan at this rate"))
            }
            .buttonStyle(.row)
        }
    }

    /// Everything that leads somewhere else, as one group of rows.
    private var linkRows: some View {
        RowGroup {
            oneOffRow
            planRow
            forecastRow
            winsRow
            challengeRow
            askRow
        }
    }

    // MARK: - Anti-budget

    /// One number: what's left to spend freely. Obligations are stated as
    /// handled rather than itemised, which is the entire point of the mode.
    private var simplified: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            AdaptiveCards {
                VStack(alignment: .leading, spacing: 0) {
                    // Nothing in a finished month is free to spend any more; what the
                    // same figure means by then is what went unspent.
                    Text(model.isCurrentMonth ? "Free to spend" : "Left over in \(model.monthTitle)")
                        .appFont(13, weight: .medium)
                        .foregroundStyle(Palette.sub)
                    Text(Fmt.money(max(0, model.funLeft)))
                        .mono(52)
                        .foregroundStyle(model.funLeft < 0 ? Palette.over : Palette.text)
                        .padding(.bottom, Space.xs)

                    ProgressBar(pct: min(100, model.funSpent / max(model.funMoney, 1) * 100),
                                fill: Palette.tealGradient, height: 10)
                        .padding(.bottom, Space.xs)

                    Text("\(Fmt.money(model.funSpent)) of \(Fmt.money(model.funMoney)) used")
                        .appFont(12.5, weight: .medium)
                        .foregroundStyle(Palette.sub)
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                // Live month only, as in the full view. On a closed one this said
                // "Days left 9" about January, and a per-day figure that divided
                // January's leftovers by the days left in September.
                if model.isCurrentMonth {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        StatRow([
                            Stat(title: "A day from here",
                                 value: Fmt.money(model.funDaily), color: Palette.teal),
                            Stat(title: "Days left", value: "\(model.daysLeft)"),
                        ])
                        billsLine(discretionaryOnly: true)
                    }
                }

                RowGroup {
                    RowLabel(symbol: "checkmark.circle.fill", color: Palette.green,
                             title: Text("The fixed stuff is taken care of"),
                             subtitle: Text("\(Fmt.money(model.committed)) of rent, subscriptions and savings is already set aside.")) {
                        EmptyView()
                    }
                    // `hasPlan` as well as the promise: the row exists to relate the
                    // promise to what's free to spend, and with no limits set there is
                    // no such figure — `funMoney` computes to zero, and "more than the
                    // $0 free to spend" reads as a verdict on someone who has simply
                    // not filled anything in yet.
                    if model.hasPlan, model.hasGoalPromise {
                        goalPromiseRow
                    }
                }

                linkRows
            }

            modeToggle
        }
    }

    /// What the goals are asking of this month, stated beside the spending
    /// figure instead of taken out of it.
    ///
    /// The last clause is the important one: it says plainly that the app has
    /// not moved the money, which is what earns it the right not to subtract
    /// it. See `AppModel.funLeftAfterGoals` for the reasoning.
    private var goalPromiseRow: some View {
        let short = model.funLeftAfterGoals < 0
        return RowLabel(symbol: "target", color: short ? Palette.over : Palette.teal,
                        title: Text("\(Fmt.money(model.promisedToGoals)) a month is promised to goals"),
                        subtitle: Text(short
                                       ? "That's more than the \(Fmt.money(max(0, model.funLeft))) free to spend. Nothing moves until you move it."
                                       : "Setting it aside would leave \(Fmt.money(model.funLeftAfterGoals)). Nothing moves until you move it."),
                        subtitleColor: short ? Palette.overText : Palette.sub) {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }

    /// Says what the daily figure has held back, when it has held anything.
    /// See `AppModel.reservedForBills`.
    @ViewBuilder
    private func billsLine(discretionaryOnly: Bool) -> some View {
        let reserve = model.billReserve(discretionaryOnly: discretionaryOnly)
        if reserve.amount > 0 {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .appFont(9.5, weight: .bold)
                Text(Copy.billsLeftOut(reserved: reserve.amount, bills: reserve.bills))
                    .appFont(11)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .foregroundStyle(Palette.sub)
            .accessibilityElement(children: .combine)
        }
    }

    /// The compact form of `goalPromiseRow`, for the full view, where the
    /// figure follows a stat row instead of standing alone on a card. Same
    /// claim, one line, and the same refusal to subtract anything.
    private var goalPromiseLine: some View {
        let short = model.leftAfterGoals < 0
        return HStack(spacing: 5) {
            Image(systemName: "target")
                .appFont(9.5, weight: .bold)
            Text(short
                 ? "\(Fmt.money(model.promisedToGoals)) a month is promised to goals — more than is left"
                 : "\(Fmt.money(model.promisedToGoals)) of this is promised to goals, leaving \(Fmt.money(model.leftAfterGoals))")
                .appFont(11)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .foregroundStyle(short ? Palette.over : Palette.teal)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Full view

    private var full: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            AdaptiveCards {
                spendingCard
                figures
                linkRows
                recent
            }

            modeToggle
        }
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.isCurrentMonth ? "Spent this month" : "Spent in \(model.monthTitle)")
                .appFont(13, weight: .medium).foregroundStyle(Palette.sub)

            // 34pt, down from 44. The total is the anchor for the sentence
            // above it and the breakdown below it, not a headline in its own
            // right — at 44 it was the loudest thing on a screen whose actual
            // job is to say how the month is going.
            // Stacked once the badge can't sit beside the total and still be read:
            // cut to "19% vs Sep…" it no longer said what it was comparing.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(Fmt.money(model.spent)).mono(34)
                    changeBadge
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.money(model.spent)).mono(34)
                    changeBadge
                }
            }

            // What the total is made of, in one line. A figure that size says
            // how much and nothing else; this is the part someone would
            // actually repeat to the person they share the budget with.
            if let takeaway = model.spendTakeaway {
                Text(takeaway)
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xxs)
            }

            SpendBreakdown()
        }
        .padding(.horizontal, Space.md).padding(.top, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var changeBadge: some View {
        if let change = model.monthOverMonth {
            HStack(spacing: 3) {
                Image(systemName: change.isDown ? "arrow.down.right" : "arrow.up.right")
                    .appFont(11, weight: .bold)
                Text("\(change.percent)% vs \(model.previousMonthName)")
                    .appFont(12, weight: .semibold)
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(change.isDown ? Palette.teal : Palette.over)
            // The badge is short to sit beside the total; the spoken
            // form can afford to say what it's actually comparing.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(change.percent)% \(change.isDown ? "less" : "more") than "
                + (model.isCurrentMonth ? "by this point in \(model.previousMonthName)"
                                        : model.previousMonthName))
        }
    }

    /// The month's working figures. Which ones depends on whether it's still
    /// running: what's left and what a day can take, or how it finished.
    private var figures: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if model.isCurrentMonth {
                // Both of these are derived from limits. With none set they
                // compute to zero, and a card announcing "Left to spend $0" to
                // someone who simply hasn't made a budget yet reads as "you are
                // broke" rather than "you haven't told me anything yet".
                if model.hasPlan {
                    StatRow([
                        Stat(title: "Left to spend", value: Fmt.money(model.left),
                             color: Palette.teal),
                        Stat(title: "A day from here", value: Fmt.money(model.safeDaily)),
                        Stat(title: "Days left", value: "\(model.daysLeft)"),
                    ])
                    billsLine(discretionaryOnly: false)
                    if model.hasGoalPromise { goalPromiseLine }
                }
            } else {
                // Safe-daily and days-left are meaningless once the month is
                // over, so a closed month reports how it finished instead.
                StatRow([
                    Stat(title: "Planned", value: Fmt.money(model.capTotal)),
                    Stat(title: "Money in", value: "+" + Fmt.money(model.earned), color: Palette.green),
                    Stat(title: "Kept", value: signed(model.net),
                         color: model.net < 0 ? Palette.over : Palette.text),
                ])
            }

            // Only worth the space once money has actually come in.
            if model.isCurrentMonth, model.earned > 0 {
                StatRow([
                    Stat(title: "Money in", value: "+" + Fmt.money(model.earned), color: Palette.green),
                    Stat(title: "Kept", value: signed(model.net),
                         color: model.net < 0 ? Palette.over : Palette.text),
                ])
            }
        }
    }

    @ViewBuilder
    private var recent: some View {
        if !model.month.entries.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    SectionTitle("Recent")
                    Spacer()
                    Button("See all") { model.tab = .log }
                        .appFont(12.5, weight: .semibold)
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, Space.md)
                }

                RowGroup {
                    ForEach(model.month.entries.prefix(4)) { entry in
                        GroupedRow(separatorInset: Space.md + 32 + Space.sm) {
                            EntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared pieces

    /// Streak and latest badge, as a way into the full wins screen.
    private var winsRow: some View {
        NavigationLink(value: Route.wins) {
            RowLabel(symbol: "flame.fill",
                     color: model.wins.streak > 0 ? Palette.teal : Palette.muted,
                     fill: model.wins.streak > 0 ? nil : Palette.chip,
                     title: Text(Copy.streakLine(days: model.wins.streak,
                                                 graceUsed: model.wins.graceUsed,
                                                 hasPlan: model.hasPlan)),
                     subtitle: Text(Copy.badgeLine(wins: model.wins, new: model.newBadgeIDs)),
                     subtitleColor: model.newBadgeIDs.isEmpty ? Palette.sub : Palette.teal)
        }
        .buttonStyle(.row)
    }

    @ViewBuilder
    private var modeToggle: some View {
        if model.hasPlan {
            modeToggleButton
        }
    }

    private var modeToggleButton: some View {
        Button {
            Haptics.selected()
            withAppAnimation(.easeInOut(duration: 0.2)) { model.isSimplified.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isSimplified ? "list.bullet" : "wand.and.stars")
                    .appFont(11, weight: .semibold)
                Text(model.isSimplified ? "Show the full budget" : "Just show me my fun money")
                    .appFont(12.5, weight: .semibold)
            }
            .foregroundStyle(Palette.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.sm)
        }
    }

    /// Overlapping avatars, capped so a big household doesn't push the title
    /// off the row.
    private var avatarStack: some View {
        let shown = model.members.prefix(Self.maxAvatars)
        let overflow = model.members.count - shown.count
        return HStack(spacing: -7) {
            ForEach(shown) { member in
                MemberAvatar(member: member, size: 28)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .appFont(10, weight: .bold)
                    .foregroundStyle(Palette.chipText)
                    .frame(width: 28, height: 28)
                    .background(Palette.chip, in: Circle())
            }
        }
        // Flattened, or the bar's vibrancy blends the overlapping circles.
        .drawingGroup()
    }

    /// "+$420" / "−$120" — the sign carries the meaning, so it's never dropped.
    private func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + Fmt.money(abs(value))
    }
}

// MARK: - Category breakdown

/// Where the month's money went, biggest first, as something you can read at a
/// glance and open.
///
/// This replaced a cloud of floating bubbles. They were the warmest thing on
/// the screen and the least informative thing on it: diameter encoded amount so
/// loosely that a smaller category in the first slot could out-draw a bigger one
/// in the second (DESIGN-NOTES §3), no bubble carried a share, everything past
/// the fifth category vanished without saying so, and none of it could be
/// tapped. The colour survives — that's where the warmth actually came from —
/// and now sits next to a figure that says what it means.
struct SpendBreakdown: View {
    @EnvironmentObject var model: AppModel

    /// Rows before the tail is folded into one line. Four is a glance; the
    /// whole list is one tap away.
    private static let visibleRows = 4

    var body: some View {
        let items = model.month.ranked
        if items.isEmpty {
            // Only the live month gets the invitation. On a closed one it said
            // "add anything you spent today" under "That month is done", and
            // its button filed the entry under today, not under the month on
            // screen. The sentence above already says there's nothing here.
            if model.isCurrentMonth { EmptySpendPrompt() }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // `spent` and `ranked` are accumulated in the same pass over
                // the same entries, so this guards the division and nothing
                // else — the shares always add up to the total above.
                let spent = max(model.spent, 0.01)
                let rest = items.dropFirst(Self.visibleRows)

                VStack(spacing: Space.sm) {
                    ForEach(items.prefix(Self.visibleRows)) { item in
                        row(label: item.bucket.label, symbol: item.bucket.symbol,
                            color: item.bucket.color, tint: item.bucket.tint,
                            amount: item.total, share: item.total / spent * 100)
                    }
                    // Four rows above a total they don't add up to is worse
                    // than a longer list, so the tail gets a line rather than
                    // silence.
                    if !rest.isEmpty {
                        let tail = rest.reduce(0) { $0 + $1.total }
                        row(label: Fmt.count(rest.count, "more category",
                                             plural: "more categories"),
                            symbol: "ellipsis", color: Palette.sub, tint: Palette.chip,
                            amount: tail, share: tail / spent * 100)
                    }
                }
                .padding(.top, Space.md)

                seeSpending
            }
        }
    }

    /// One category: colour, name, amount, share, and a bar for the eye to
    /// compare without reading any of it.
    private func row(label: String, symbol: String, color: Color, tint: Color,
                     amount: Double, share: Double) -> some View {
        Button {
            Haptics.selected()
            model.reveal(.stats)
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                AdaptiveRow {
                    IconTile(symbol: symbol, color: color, fill: tint)
                    Text(label).appFont(13, weight: .medium).lineLimit(1)
                } figures: {
                    Text(Fmt.money(amount)).mono(13)
                    Text(Fmt.share(share))
                        .appFont(11.5, weight: .medium)
                        .foregroundStyle(Palette.sub)
                        .figureColumn(width: 40)
                }
                // Floored, like the trend chart's columns: a $5 category next
                // to a $1,200 one draws about a pixel of bar, and a row with
                // an amount on it and no mark beside it reads as broken.
                ProgressBar(pct: max(share, 1.5), fill: color, height: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Fmt.money(amount)), "
                          + "\(Fmt.share(share, spoken: true)) of spending")
        .accessibilityHint("Opens the spending charts")
    }

    /// The way into the full breakdown. Every row above goes to the same place;
    /// this exists so the way in is *stated* rather than found by prodding a
    /// row to see whether it does anything.
    private var seeSpending: some View {
        Button {
            Haptics.selected()
            model.reveal(.stats)
        } label: {
            HStack(spacing: Space.xxs) {
                Text("See spending").appFont(13, weight: .medium)
                Image(systemName: "chevron.forward").appFont(11, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.teal)
            .padding(.vertical, Space.md)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the spending charts")
    }
}

#Preview {
    PreviewShell { HomeView() }
}

#Preview("Home — light") {
    PreviewShell(scheme: .light) { HomeView() }
}
