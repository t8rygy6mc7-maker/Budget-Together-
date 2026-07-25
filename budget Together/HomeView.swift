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
                    Text("Together").font(.system(size: 22, weight: .bold))
                    MonthStepper()
                }
                Spacer()
                Button { showPeople = true } label: { avatarStack }
                    .accessibilityLabel("^[\(model.members.count) person](inflect: true) on this budget")
                    .accessibilityHint("Opens people")
            }
            .padding(.bottom, 18)

            if model.isSimplified {
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

    /// A running challenge, or an invitation to start one.
    private var challengeStrip: some View {
        Button { showChallenges = true } label: {
            HStack(spacing: 12) {
                let running = model.featuredChallenge
                Image(systemName: running?.isBroken == true ? "xmark.circle.fill" : "flag.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(running?.isBroken == true ? Palette.over : Palette.moodSocial)
                    .frame(width: 32, height: 32)
                    .background((running?.isBroken == true ? Palette.over : Palette.moodSocial)
                        .opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(running?.challenge.title ?? "Take on a challenge")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(running?.detail ?? "No-Spend Weekend and others, together")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 13, weight: .semibold))
                Text("Ask about your spending")
                    .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(over ? Palette.over : Palette.teal)
                        .frame(width: 32, height: 32)
                        .background((over ? Palette.over : Palette.teal).opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heading for \(Fmt.money(model.forecast.projected))")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(over
                             ? "\(Fmt.money(model.forecast.overBy)) over plan at this rate"
                             : "\(Fmt.money(model.forecast.underBy)) under plan at this rate")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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
            Text("Free to spend").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.sub)
            Text(Fmt.money(max(0, model.funLeft)))
                .mono(52, weight: .semibold)
                .foregroundStyle(model.funLeft < 0 ? Palette.over : Palette.text)
                .padding(.bottom, 4)

            ProgressBar(pct: min(100, model.funSpent / max(model.funMoney, 1) * 100),
                        fill: Palette.tealGradient, height: 10)
                .padding(.bottom, 10)

            Text("\(Fmt.money(model.funSpent)) of \(Fmt.money(model.funMoney)) used")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.sub)
                .padding(.bottom, 20)

            HStack(spacing: 0) {
                statCell(model.isCurrentMonth ? "A day from here" : "Per day",
                         Fmt.money(model.funDaily), Palette.teal)
                divider
                statCell("Days left", "\(model.daysLeft)", Palette.text)
            }
            .padding(.horizontal, 17).padding(.vertical, 15)
            .card()
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obligations handled").font(.system(size: 13, weight: .semibold))
                    Text("\(Fmt.money(model.committed)) of rent, subscriptions and savings is already set aside.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)

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
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.sub)

            HStack(alignment: .bottom, spacing: 10) {
                Text(Fmt.money(model.spent)).mono(44, weight: .semibold)
                if let change = model.monthOverMonth {
                    HStack(spacing: 3) {
                        Image(systemName: change.isDown ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(change.percent)% vs \(model.previousMonthName)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(change.isDown ? Palette.teal : Palette.over)
                    .padding(.bottom, 10)
                }
            }

            BubbleCloud()

            HStack(spacing: 0) {
                if model.isCurrentMonth {
                    statCell("Budget left", Fmt.money(model.left), Palette.teal)
                    divider
                    statCell("Safe daily", Fmt.money(model.safeDaily), Palette.text)
                    divider
                    statCell("Days left", "\(model.daysLeft)", Palette.text)
                } else {
                    // Safe-daily and days-left are meaningless once the month is
                    // over, so a closed month reports how it finished instead.
                    statCell("Planned", Fmt.money(model.capTotal), Palette.text)
                    divider
                    statCell("Income", "+" + Fmt.money(model.earned), Palette.green)
                    divider
                    statCell("Net", signed(model.net), model.net < 0 ? Palette.over : Palette.text)
                }
            }
            .padding(.horizontal, 17).padding(.vertical, 15)
            .card()

            // Only worth the space once money has actually come in.
            if model.isCurrentMonth, model.earned > 0 {
                HStack(spacing: 0) {
                    statCell("Income", "+" + Fmt.money(model.earned), Palette.green)
                    divider
                    statCell("Net", signed(model.net),
                             model.net < 0 ? Palette.over : Palette.text)
                }
                .padding(.horizontal, 17).padding(.vertical, 15)
                .card()
                .padding(.top, 8)
            }

            forecastStrip.padding(.top, 12)
            winsStrip.padding(.top, 9)
            challengeStrip.padding(.top, 9)
            askButton.padding(.top, 9)

            HStack {
                Text("Recent").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("See all") { model.tab = .log }
                    .font(.system(size: 12.5, weight: .semibold))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.wins.streak > 0 ? Palette.teal : Palette.muted)
                    .frame(width: 32, height: 32)
                    .background(model.wins.streak > 0 ? Palette.teal.opacity(0.16) : Palette.chip,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.wins.streak > 0
                         ? "^[\(model.wins.streak) day](inflect: true) inside the daily allowance"
                         : "Start a streak today")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(model.wins.headline.map { "Latest badge: \($0.title)" }
                         ?? "^[\(model.wins.badges.count) badge](inflect: true) to earn")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .card(border: Palette.cardBorderSoft, radius: 15)
        }
        .buttonStyle(.plain)
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.isSimplified.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isSimplified ? "list.bullet" : "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.isSimplified ? "Show the full budget" : "Just show me my fun money")
                    .font(.system(size: 12.5, weight: .semibold))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.chipText)
                    .frame(width: 32, height: 32)
                    .background(Palette.chip, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.screen, lineWidth: 2))
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.cardBorder).frame(width: 1, height: 34)
    }

    /// "+$420" / "−$120" — the sign carries the meaning, so it's never dropped.
    private func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + Fmt.money(abs(value))
    }

    private func statCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.sub)
            Text(value).mono(20).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

// MARK: - Bubble cloud

struct BubbleCloud: View {
    @EnvironmentObject var model: AppModel

    /// Hand-placed positions from the design comp, largest bucket first.
    private struct Slot {
        let base: CGFloat
        let offset: CGSize
        let fontSize: CGFloat
    }

    private static let slots: [Slot] = [
        Slot(base: 148, offset: CGSize(width: 6,   height: 22),  fontSize: 17),
        Slot(base: 100, offset: CGSize(width: 158, height: 6),   fontSize: 14),
        Slot(base: 82,  offset: CGSize(width: 192, height: 122), fontSize: 12),
        Slot(base: 74,  offset: CGSize(width: 96,  height: 168), fontSize: 12),
        Slot(base: 60,  offset: CGSize(width: 16,  height: 178), fontSize: 11),
    ]

    var body: some View {
        let items = model.month.ranked.prefix(Self.slots.count)
        let largest = items.first?.total ?? 1

        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                Text("No spending yet — tap + to add one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let slot = Self.slots[index]
                    let size = (slot.base * (0.74 + 0.26 * (item.total / largest))).rounded()
                    Bubble(item: item, size: size, fontSize: slot.fontSize, index: index)
                        .frame(width: size, height: size)
                        .offset(x: slot.offset.width, y: slot.offset.height)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 250)
        .padding(.top, 10).padding(.bottom, 4)
    }
}

struct Bubble: View {
    let item: BucketTotal
    let size: CGFloat
    let fontSize: CGFloat
    let index: Int

    @State private var floating = false

    var body: some View {
        let bucket = item.bucket
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [bucket.color.opacity(0.95), bucket.color],
                                     center: UnitPoint(x: 0.34, y: 0.30),
                                     startRadius: 0, endRadius: size * 0.7))
                .shadow(color: bucket.glow, radius: 19)

            VStack(spacing: 2) {
                if size >= 66 {
                    Image(systemName: bucket.symbol)
                        .font(.system(size: size * 0.16, weight: .semibold))
                }
                Text(Fmt.compact(item.total))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                if size >= 96 {
                    Text(bucket.short).font(.system(size: 10)).opacity(0.82)
                }
            }
            .foregroundStyle(.white)
        }
        .offset(y: floating ? -6 : 0)
        // The float has to be started with `withAnimation`, not `.animation(_:value:)`:
        // a repeatForever curve attached as a modifier becomes the ambient
        // animation for the whole subtree, so every later amount change
        // cross-fades forever and the bubble shows a stale figure behind the
        // new one.
        .onAppear {
            withAnimation(
                .easeInOut(duration: 5 + Double(index) * 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.3)
            ) {
                floating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bucket.label): \(Fmt.money(item.total))")
    }
}

#Preview {
    PreviewShell { HomeView() }
}

#Preview("Home — light") {
    PreviewShell(scheme: .light) { HomeView() }
}
