import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPeople = false
    @State private var showWins = false
    @State private var showInsights = false
    @State private var showAsk = false
    @State private var showChallenges = false

    /// Avatars shown before the stack collapses into a "+N" badge.
    private static let maxAvatars = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Together")
                        .appFont(22, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    MonthStepper()
                }
                Spacer()
                Button { showPeople = true } label: { avatarStack }
                    .accessibilityLabel("^[\(model.members.count) person](inflect: true) on this budget")
                    .accessibilityHint("Opens people")
            }
            .padding(.bottom, 18)

            summaryLine.padding(.bottom, 18)

            // Anti-budget mode is entirely "what's left of the fun money",
            // which is a limits calculation. With no limits set it would report
            // a confident $0, so the mode simply isn't available until there's
            // a plan for it to subtract from.
            if model.isSimplified, model.hasPlan {
                simplified
            } else {
                full
            }
        }
        .sheet(isPresented: $showPeople) { PeopleSheet() }
        .sheet(isPresented: $showWins) { WinsSheet() }
        .sheet(isPresented: $showInsights) { InsightsSheet() }
        .sheet(isPresented: $showAsk) { AskSheet() }
        .sheet(isPresented: $showChallenges) { ChallengesSheet() }
    }

    /// How the month is going, in a sentence, above everything else.
    ///
    /// The screen used to open with a large number and a red percentage badge —
    /// a verdict, delivered before any context, in the position the eye lands
    /// first. The arithmetic hasn't changed and it's all still below; it just
    /// isn't the greeting any more.
    private var summaryLine: some View {
        let summary = Copy.summary(
            hasPlan: model.hasPlan,
            left: model.left,
            daysLeft: model.daysLeft,
            spent: model.spent,
            projected: model.forecast.projected,
            plan: model.plannedTotal,
            entryCount: model.month.entries.count,
            isCurrentMonth: model.isCurrentMonth,
            isUnusualMonth: model.isSelectedMonthUnusual,
            name: model.me?.name
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text(summary.headline)
                .appFont(19, weight: .bold)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary.detail)
                .appFont(13)
                .foregroundStyle(summary.needsAttention ? Palette.overText : Palette.sub)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasPlan, model.left > 0, model.weeklyFramingIsUseful {
                weeklyLine.padding(.top, 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The same allowance in the unit people actually think in. "$840 over 19
    /// days" is arithmetic; "about $180 between now and Sunday" is a decision
    /// you can make at a till.
    private var weeklyLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.day.timeline.left")
                .appFont(10, weight: .semibold)
            Text("About \(Fmt.money(model.weeklyAllowance)) to see out the week"
               + (model.spentThisWeek > 0
                  ? " — \(Fmt.money(model.spentThisWeek)) gone so far" : ""))
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
    private var oneOffStrip: some View {
        if model.month.belowTheLine > 0 {
            Button { model.tab = .log } label: {
                HStack(spacing: 12) {
                    Image(systemName: "minus.diamond.fill")
                        .appFont(14, weight: .semibold)
                        .foregroundStyle(Palette.moodJoy)
                        .frame(width: 32, height: 32)
                        .background(Palette.moodJoy.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.money(model.month.belowTheLine)) in one-offs")
                            .appFont(13, weight: .semibold).lineLimit(1)
                        Text("^[\(model.month.belowTheLineCount) thing](inflect: true) you set aside — not counted above")
                            .appFont(11.5).foregroundStyle(Palette.sub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card(border: Palette.cardBorderSoft, radius: 15)
            }
            .buttonStyle(.plain)
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
    private var planStrip: some View {
        if model.isCurrentMonth,
           !model.hasPlan || !model.visibleTabs.contains(.budget) {
            Button { model.reveal(.budget) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .appFont(14, weight: .semibold)
                        .foregroundStyle(Palette.teal)
                        .frame(width: 32, height: 32)
                        .background(Palette.teal.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasPlan ? "Your spending limits"
                             : model.canSuggestPlan ? "Ready to set some limits?"
                             : "Want to set spending limits?")
                            .appFont(13, weight: .semibold).lineLimit(1)
                        Text(model.hasPlan
                             ? "Change them whenever they stop fitting."
                             : model.canSuggestPlan
                             ? "There's enough here now to suggest some."
                             : "Optional — tracking works fine without them.")
                            .appFont(11.5).foregroundStyle(Palette.sub)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card(border: Palette.cardBorderSoft, radius: 15)
            }
            .buttonStyle(.plain)
        }
    }

    /// A running challenge, or an invitation to start one.
    private var challengeStrip: some View {
        Button { showChallenges = true } label: {
            HStack(spacing: 12) {
                let running = model.featuredChallenge
                Image(systemName: running?.isBroken == true ? "xmark.circle.fill" : "flag.fill")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(running?.isBroken == true ? Palette.over : Palette.moodSocial)
                    .frame(width: 32, height: 32)
                    .background((running?.isBroken == true ? Palette.over : Palette.moodSocial)
                        .opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(running?.challenge.title ?? "Take on a challenge")
                        .appFont(13, weight: .semibold).lineLimit(1)
                    Text(running?.detail ?? "No-Spend Weekend and others, together")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    private var askButton: some View {
        Button { showAsk = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .appFont(13, weight: .semibold)
                Text("Ask about your spending")
                    .appFont(13, weight: .medium)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.chipText)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .fieldBackground(radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask a question about your spending")
    }

    /// The forecast in one line, as a way into the full breakdown. Hidden until
    /// there's enough of the month behind it to mean anything.
    @ViewBuilder
    private var forecastStrip: some View {
        if model.isCurrentMonth, model.forecast.isReliable {
            let over = model.forecast.isOverPlan
            Button { showInsights = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: over ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis")
                        .appFont(14, weight: .semibold)
                        .foregroundStyle(over ? Palette.over : Palette.teal)
                        .frame(width: 32, height: 32)
                        .background((over ? Palette.over : Palette.teal).opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heading for \(Fmt.money(model.forecast.projected))")
                            .appFont(13, weight: .semibold).lineLimit(1)
                        Text(over
                             ? "\(Fmt.money(model.forecast.overBy)) over plan at this rate"
                             : "\(Fmt.money(model.forecast.underBy)) under plan at this rate")
                            .appFont(11.5).foregroundStyle(Palette.sub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card(border: Palette.cardBorderSoft, radius: 15)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Anti-budget

    /// One number: what's left to spend freely. Obligations are stated as
    /// handled rather than itemised, which is the entire point of the mode.
    private var simplified: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Free to spend").appFont(13, weight: .medium)
                .foregroundStyle(Palette.sub)
            Text(Fmt.money(max(0, model.funLeft)))
                .mono(52, weight: .semibold)
                .foregroundStyle(model.funLeft < 0 ? Palette.over : Palette.text)
                .padding(.bottom, 4)

            ProgressBar(pct: min(100, model.funSpent / max(model.funMoney, 1) * 100),
                        fill: Palette.tealGradient, height: 10)
                .padding(.bottom, 10)

            Text("\(Fmt.money(model.funSpent)) of \(Fmt.money(model.funMoney)) used")
                .appFont(12.5, weight: .medium)
                .foregroundStyle(Palette.sub)
                .padding(.bottom, 20)

            StatRow([
                Stat(title: model.isCurrentMonth ? "A day from here" : "Per day",
                     value: Fmt.money(model.funDaily), color: Palette.teal),
                Stat(title: "Days left", value: "\(model.daysLeft)"),
            ])
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The fixed stuff is taken care of").appFont(13, weight: .semibold)
                    Text("\(Fmt.money(model.committed)) of rent, subscriptions and savings is already set aside.")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)

            oneOffStrip.padding(.top, 9)
            planStrip.padding(.top, 9)
            forecastStrip.padding(.top, 9)
            winsStrip.padding(.top, 9)
            challengeStrip.padding(.top, 9)
            askButton.padding(.top, 9)

            modeToggle
        }
    }

    // MARK: - Full view

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(model.isCurrentMonth ? "Spent this month" : "Spent in \(model.monthTitle)")
                .appFont(13, weight: .medium).foregroundStyle(Palette.sub)

            // 34pt, down from 44. The total is the anchor for the sentence
            // above it and the breakdown below it, not a headline in its own
            // right — at 44 it was the loudest thing on a screen whose actual
            // job is to say how the month is going.
            HStack(alignment: .bottom, spacing: 10) {
                Text(Fmt.money(model.spent)).mono(34, weight: .medium)
                if let change = model.monthOverMonth {
                    HStack(spacing: 3) {
                        Image(systemName: change.isDown ? "arrow.down.right" : "arrow.up.right")
                            .appFont(13, weight: .bold)
                        Text("\(change.percent)% vs \(model.previousMonthName)")
                            .appFont(13, weight: .semibold)
                    }
                    .foregroundStyle(change.isDown ? Palette.teal : Palette.over)
                    .padding(.bottom, 6)
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
                    .padding(.top, 5)
            }

            SpendBreakdown()

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
                .padding(.top, 8)
            }

            oneOffStrip.padding(.top, 12)
            planStrip.padding(.top, 9)
            forecastStrip.padding(.top, 9)
            winsStrip.padding(.top, 9)
            challengeStrip.padding(.top, 9)
            askButton.padding(.top, 9)

            HStack {
                Text("Recent").appFont(15, weight: .bold)
                Spacer()
                Button("See all") { model.tab = .log }
                    .appFont(12.5, weight: .semibold)
                    .foregroundStyle(Palette.teal)
            }
            .padding(.horizontal, 2)
            .padding(.top, 24).padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(model.month.entries.prefix(4)) { EntryRow(entry: $0) }
            }

            modeToggle
        }
    }

    // MARK: - Shared pieces

    /// Streak and latest badge, as a way into the full wins sheet.
    private var winsStrip: some View {
        Button { showWins = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .appFont(14, weight: .semibold)
                    .foregroundStyle(model.wins.streak > 0 ? Palette.teal : Palette.muted)
                    .frame(width: 32, height: 32)
                    .background(model.wins.streak > 0 ? Palette.teal.opacity(0.16) : Palette.chip,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.streakLine(days: model.wins.streak,
                                         graceUsed: model.wins.graceUsed))
                        .appFont(13, weight: .semibold)
                        .lineLimit(1)
                    Text(model.wins.headline.map { "Latest badge: \($0.title)" }
                         ?? "^[\(model.wins.badges.count) badge](inflect: true) to earn")
                        .appFont(11.5).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
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
            withAnimation(.easeInOut(duration: 0.2)) { model.isSimplified.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isSimplified ? "list.bullet" : "wand.and.stars")
                    .appFont(11, weight: .semibold)
                Text(model.isSimplified ? "Show the full budget" : "Just show me my fun money")
                    .appFont(12.5, weight: .semibold)
            }
            .foregroundStyle(Palette.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .padding(.top, 8)
    }

    /// Overlapping avatars, capped so a big household doesn't push the title
    /// off the row.
    private var avatarStack: some View {
        let shown = model.members.prefix(Self.maxAvatars)
        let overflow = model.members.count - shown.count
        return HStack(spacing: -9) {
            ForEach(shown) { member in
                MemberAvatar(member: member, ring: Palette.screen)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .appFont(11, weight: .bold)
                    .foregroundStyle(Palette.chipText)
                    .frame(width: 32, height: 32)
                    .background(Palette.chip, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.screen, lineWidth: 2))
            }
        }
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
            EmptySpendPrompt()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // `spent` and `ranked` are accumulated in the same pass over
                // the same entries, so this guards the division and nothing
                // else — the shares always add up to the total above.
                let spent = max(model.spent, 0.01)
                let rest = items.dropFirst(Self.visibleRows)

                VStack(spacing: 11) {
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
                .padding(.top, 14)

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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .appFont(12, weight: .semibold)
                        .foregroundStyle(color)
                        .frame(width: 28, height: 28)
                        .background(tint,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(label).appFont(13, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Fmt.money(amount)).mono(13)
                    Text(shareLabel(share))
                        .appFont(11.5, weight: .medium)
                        .foregroundStyle(Palette.sub)
                        .frame(width: 38, alignment: .trailing)
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
                          + "\(shareLabel(share, spoken: true)) of spending")
        .accessibilityHint("Opens the spending charts")
    }

    /// A share that rounds to zero still isn't zero, and "0%" beside a real
    /// amount reads as an arithmetic bug. The spoken form differs only so
    /// VoiceOver doesn't have to pronounce the chevron.
    private func shareLabel(_ share: Double, spoken: Bool = false) -> String {
        let whole = Fmt.whole(share)
        guard whole > 0 else { return spoken ? "under 1%" : "<1%" }
        return "\(whole)%"
    }

    /// The way into the full breakdown. Every row above goes to the same place;
    /// this exists so the way in is *stated* rather than found by prodding a
    /// row to see whether it does anything.
    private var seeSpending: some View {
        Button {
            Haptics.selected()
            model.reveal(.stats)
        } label: {
            HStack(spacing: 5) {
                Text("See spending").appFont(13, weight: .semibold)
                Image(systemName: "chevron.right").appFont(11, weight: .bold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.teal)
            .padding(.vertical, 14)
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
