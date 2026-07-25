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
                Text("Daily log").font(.system(size: 22, weight: .bold))
                Spacer()
                MonthStepper()
            }
            Text("^[\(entries.count) entry](inflect: true)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.sub)
                .padding(.top, 2).padding(.bottom, 14)

            filters

            if entries.isEmpty {
                Text(model.month.entries.isEmpty
                     ? "Nothing logged this month yet."
                     : "Nothing matches these filters.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }

            ForEach(groups(of: entries)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(Fmt.dateLabel(group.date, today: model.today))
                            .font(.system(size: 12.5, weight: .semibold))
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
                            EntryRow(entry: entry, showDelete: true)
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
                .font(.system(size: 12.5, weight: .semibold))
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
                Text(label).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
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
