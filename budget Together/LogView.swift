import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    /// One day's entries with its running total.
    private struct DayGroup: Identifiable {
        let date: String
        let total: Double
        let items: [Entry]
        var id: String { date }
    }

    var body: some View {
        let entries = model.month.entries
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily log").font(.system(size: 22, weight: .bold))
            Text("\(model.monthTitle) · ^[\(entries.count) entry](inflect: true)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.sub)
                .padding(.bottom, 18)

            ForEach(groups(of: entries)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Fmt.dateLabel(group.date, today: model.today))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.label9)
                        Spacer()
                        Text(Fmt.money2(group.total)).mono(12.5).foregroundStyle(Palette.sub)
                    }
                    ForEach(group.items) { EntryRow(entry: $0, showDelete: true) }
                }
                .padding(.bottom, 20)
            }
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
            return DayGroup(date: date, total: items.reduce(0) { $0 + $1.amount }, items: items)
        }
    }
}

#Preview {
    PreviewShell { LogView() }
}
