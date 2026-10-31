import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    /// `nil` means both directions.
    @State private var kindFilter: EntryKind?
    /// `nil` means everyone.
    @State private var memberFilter: String?
    @State private var editing: Entry?
    @State private var query = ""
    /// Whether the search reaches past the month on screen. Only ever set by
    /// the user, from the offer in the empty state — widening silently would
    /// put March's dinners under a July heading with no explanation.
    @State private var allMonths = false

    /// One day's entries with its running totals, kept apart by direction so a
    /// day's spending isn't quietly netted against a paycheque.
    private struct DayGroup: Identifiable {
        let date: String
        let spent: Double
        let earned: Double
        let items: [Entry]
        var id: String { date }
    }

    /// Whether a search is actually narrowing anything. Blank spaces don't
    /// count — a stray space shouldn't switch the screen into search mode.
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The search reaches every month only when there's something to search
    /// for. Clearing the box drops back to the month on screen on its own,
    /// rather than leaving a scope the user can no longer see the effect of.
    private var searchesEverything: Bool { allMonths && isSearching }

    var body: some View {
        let entries = filtered(model.search(query, monthOnly: !searchesEverything))
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.sm) {
                    presenceLine
                    searchSummary(entries.count)
                    kindPicker
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if entries.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(groups(of: entries)) { group in
                Section {
                    ForEach(group.items) { row($0) }
                } header: {
                    dayHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Space.md)
        .listColumn()
        .navigationTitle("Daily log")
        .monthControls(detail: isSearching ? nil : Fmt.count(model.month.entries.count, "entry",
                                                             plural: "entries"))
        .toolbar {
            // Nobody to filter by on a budget of one.
            if model.members.count > 1 {
                ToolbarItem(placement: .topBarLeading) { personFilter }
            }
        }
        // Kept open. Pulling a list down to find its search is the system default,
        // but finding a past purchase is half of what a ledger is for.
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search places, notes, people")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, new in
            // Clearing the box drops the wider scope with it, rather than
            // leaving one the user can no longer see the effect of.
            if new.isEmpty { allMonths = false }
        }
        .sheet(item: $editing) { entry in
            AddSheet(editing: entry).environmentObject(model)
        }
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack(spacing: Space.xs) {
            // Across months a weekday alone is ambiguous, so the
            // heading carries the full date instead.
            Text(searchesEverything ? Fmt.dayTitle(group.date)
                                    : Fmt.dateLabel(group.date, today: model.today))
                .appFont(13, weight: .semibold)
                .foregroundStyle(Palette.sub)
            Spacer()
            if group.earned > 0 {
                Text("+" + Fmt.money2(group.earned))
                    .mono(12.5).foregroundStyle(Palette.green)
            }
            if group.spent > 0 {
                Text(Fmt.money2(group.spent))
                    .mono(12.5, weight: .medium).foregroundStyle(Palette.sub)
            }
        }
        .textCase(nil)
    }

    /// One entry. Tap to edit, swipe to delete, and everything again on a long
    /// press. Each row used to carry its own small ✕, a tap away from anything
    /// else on the row. A swipe can't happen by accident, and the undo offer is
    /// still there if it does.
    private func row(_ entry: Entry) -> some View {
        Button { editing = entry } label: {
            EntryRow(entry: entry, showsSocial: true)
                .contentShape(Rectangle())
                // Under the title on every row. Left alone it follows the first
                // text it finds, which a note pulls out of line.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 44 }
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.card)
        .listRowSeparatorTint(Palette.cardBorderSoft)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.delete(entry.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { editing = entry } label: { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { model.delete(entry.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Presence

    /// Who else has been here today. Warm and ambient on purpose — it says
    /// somebody is keeping up their end without naming a figure, which is the
    /// difference between company and surveillance.
    @ViewBuilder
    private var presenceLine: some View {
        let others = model.othersActiveToday
        if !others.isEmpty {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(others) { MemberAvatar(member: $0, size: 20, ring: Palette.screen) }
                }
                Text(others.count == 1
                     ? "\(others[0].name) added something today"
                     : "\(Fmt.count(others.count, "person", plural: "people")) added something today")
                    .appFont(12)
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Search

    /// What a search found. It changes the question from "how big is this
    /// month" to "how many did I find", and the answer has to name the scope or
    /// a number from every month reads as a number from this one.
    @ViewBuilder
    private func searchSummary(_ count: Int) -> some View {
        if isSearching {
            Text(Fmt.count(count, "match", plural: "matches")
               + (searchesEverything ? " across every month" : " in \(model.monthTitle)"))
                .appFont(13, weight: .medium)
                .foregroundStyle(Palette.sub)
        }
        if searchesEverything {
            Button {
                withAppAnimation(.easeOut(duration: 0.18)) { allMonths = false }
            } label: {
                Label("Back to \(model.monthTitle)", systemImage: "calendar.badge.minus")
                    .appFont(11.5, weight: .semibold)
            }
            .inlineActionStyle()
        }
    }

    // MARK: - Nothing to show

    /// Four different nothings, which are four different problems: an empty
    /// month, a search that found nothing anywhere, a search that found
    /// nothing *here*, and filters hiding what a search did find. Only the
    /// last two have a useful next move, and they're not the same move.
    @ViewBuilder
    private var emptyState: some View {
        let elsewhere = isSearching && !searchesEverything
            ? model.matchesOutsideMonth(query) : 0
        let unfiltered = model.search(query, monthOnly: !searchesEverything)

        if isSearching, !unfiltered.isEmpty {
            EmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "Nothing matches those filters",
                message: "\(Fmt.count(unfiltered.count, "match", plural: "matches")) for \"\(query)\" — just not with these filters on.",
                actionTitle: "Clear filters",
                action: { kindFilter = nil; memberFilter = nil }
            )
        } else if isSearching, elsewhere > 0 {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Nothing here for \"\(query)\"",
                message: "\(Fmt.count(elsewhere, "match", plural: "matches")) in other months, though.",
                actionTitle: "Search every month",
                action: { withAppAnimation(.easeOut(duration: 0.18)) { allMonths = true } }
            )
        } else if isSearching {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Nothing for \"\(query)\"",
                message: searchesEverything
                    ? "Nothing in any month matches that — try a shop, a note, an amount or someone's name."
                    : "Try a shop, a note, an amount or someone's name.",
                actionTitle: "Clear search",
                action: { query = ""; allMonths = false }
            )
        } else if model.month.entries.isEmpty {
            EmptyState(
                symbol: "calendar.badge.plus",
                title: model.isCurrentMonth ? "This month is a blank page"
                                            : "Nothing was logged in \(model.monthTitle)",
                message: model.isCurrentMonth
                    ? "Everything anyone adds shows up here, newest first — with a note about why, if they left one."
                    : "You can still step back to a month that has something in it.",
                actionTitle: model.isCurrentMonth ? "Add something" : nil,
                action: model.isCurrentMonth ? { model.isAddingEntry = true } : nil
            )
        } else {
            EmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "Nothing matches those filters",
                message: "There are \(Fmt.count(model.month.entries.count, "entry", plural: "entries")) this month — just not with these filters on.",
                actionTitle: "Clear filters",
                action: { kindFilter = nil; memberFilter = nil }
            )
        }
    }

    // MARK: - Filters

    private var kindPicker: some View {
        Picker("Show", selection: $kindFilter) {
            Text("All").tag(EntryKind?.none)
            ForEach(EntryKind.allCases, id: \.self) { Text($0.label).tag(EntryKind?.some($0)) }
        }
        .pickerStyle(.segmented)
    }

    /// Lives in the bar, so it costs the list nothing until it's wanted. Filled
    /// in while it's narrowing anything, because a list quietly missing someone's
    /// entries is the one thing a filter mustn't be able to do.
    private var personFilter: some View {
        Menu {
            Picker("Show", selection: $memberFilter) {
                Text("Everyone").tag(String?.none)
                ForEach(model.members) { Text($0.name).tag(String?.some($0.id)) }
            }
        } label: {
            Label("Filter by person", systemImage: memberFilter == nil
                  ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func filtered(_ entries: [Entry]) -> [Entry] {
        entries.filter { entry in
            (kindFilter == nil || entry.kind == kindFilter)
                && (memberFilter == nil || entry.memberID == memberFilter)
        }
    }

    /// Buckets entries by day. `entries` arrives newest-first from the store, so
    /// tracking first-seen order keeps the days in that same order.
    private func groups(of entries: [Entry]) -> [DayGroup] {
        var order: [String] = []
        var byDay: [String: [Entry]] = [:]
        for entry in entries {
            if byDay[entry.date] == nil { order.append(entry.date) }
            byDay[entry.date, default: []].append(entry)
        }
        return order.map { date in
            let items = byDay[date] ?? []
            return DayGroup(
                date: date,
                spent: items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount },
                earned: items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount },
                items: items
            )
        }
    }
}

#Preview {
    PreviewShell { LogView() }
}

#Preview("Log — light") {
    PreviewShell(scheme: .light) { LogView() }
}
