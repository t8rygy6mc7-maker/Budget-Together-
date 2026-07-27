import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    /// `nil` means both directions.
    @State private var kindFilter: EntryKind?
    /// `nil` means everyone.
    @State private var memberFilter: String?
    @State private var editing: Entry?

    /// One day's entries with its running totals, kept apart by direction so a
    /// day's spending isn't quietly netted against a paycheque.
    private struct DayGroup: Identifiable {
        let date: String
        let spent: Double
        let earned: Double
        let items: [Entry]
        var id: String { date }
    }

    var body: some View {
        let entries = filtered(model.month.entries)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Daily log").appFont(22, weight: .bold)
                Spacer()
                MonthStepper()
            }
            Text("^[\(entries.count) entry](inflect: true)")
                .appFont(13, weight: .medium)
                .foregroundStyle(Palette.sub)
                .padding(.top, 2).padding(.bottom, 14)

            presenceLine
            filters

            if entries.isEmpty {
                if model.month.entries.isEmpty {
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

            ForEach(groups(of: entries)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(Fmt.dateLabel(group.date, today: model.today))
                            .appFont(12.5, weight: .semibold)
                            .foregroundStyle(Palette.label9)
                        Spacer()
                        if group.earned > 0 {
                            Text("+" + Fmt.money2(group.earned))
                                .mono(12.5).foregroundStyle(Palette.green)
                        }
                        if group.spent > 0 {
                            Text(Fmt.money2(group.spent))
                                .mono(12.5).foregroundStyle(Palette.sub)
                        }
                    }
                    ForEach(group.items) { entry in
                        Button { editing = entry } label: {
                            EntryRow(entry: entry, showDelete: true, showsSocial: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(item: $editing) { entry in
            AddSheet(editing: entry).environmentObject(model)
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
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                kindChip(nil, label: "All")
                ForEach(EntryKind.allCases, id: \.self) { kindChip($0, label: $0.label) }
            }
            // People wrap rather than scroll, so nobody hides off-screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                personChip(nil, label: "Everyone")
                ForEach(model.members) { personChip($0.id, label: $0.name, color: $0.color) }
            }
        }
        .padding(.bottom, 18)
    }

    private func kindChip(_ candidate: EntryKind?, label: String) -> some View {
        let isSelected = kindFilter == candidate
        let color = candidate?.color ?? Palette.teal
        return Button { kindFilter = candidate } label: {
            Text(label)
                .appFont(12.5, weight: .semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
                .fieldBackground(isSelected ? AnyShapeStyle(color.opacity(0.14))
                                            : AnyShapeStyle(Palette.card),
                                 border: isSelected ? color : Palette.cardBorder,
                                 radius: 12)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func personChip(_ id: String?, label: String, color: Color = Palette.teal) -> some View {
        let isSelected = memberFilter == id
        return Button { memberFilter = id } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).appFont(12.5, weight: .semibold).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(isSelected ? Palette.text : Palette.chipText)
            .fieldBackground(isSelected ? AnyShapeStyle(color.opacity(0.14))
                                        : AnyShapeStyle(Palette.card),
                             border: isSelected ? color : Palette.cardBorder,
                             radius: 12)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
