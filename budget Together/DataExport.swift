import Foundation

// MARK: - Export
//
// An app that keeps your data on your own device owes you a way to get it off
// again. Without an export, "your data never leaves the phone" quietly means
// "your data is trapped on the phone", which is a worse deal than it sounds
// like and turns the privacy promise into lock-in.
//
// Two formats, because they answer different questions:
//
// **CSV** is the one people actually use — one row per transaction, opens in
// Numbers or Excel, easy to pivot. It is deliberately lossy: it holds the
// ledger, not the app's state.
//
// **JSON** is a genuine backup. Every category, every limit in every month,
// every member, template, loan, challenge and month flag. If this file were the
// only thing that survived, the budget could be rebuilt from it.
//
// Neither writes anywhere but a temporary file. Where it goes next is the
// user's choice, made in the share sheet.

enum DataExport {

    // MARK: CSV

    /// One row per transaction, newest first, with the category resolved to its
    /// current name so the file is readable without the app to decode ids.
    static func csv(entries: [Entry], memberName: (String) -> String) -> String {
        var out = "Date,Amount,Direction,Category,Where,Who,Mood,Note,One-off,Private\n"
        for entry in entries {
            let bucket = Bucket.named(entry.bucket)
            let fields = [
                entry.date,
                // Unformatted and unrounded: this is the archive copy, so it
                // carries the number as stored rather than as displayed.
                String(format: "%.2f", entry.amount),
                entry.kind == .income ? "in" : "out",
                bucket.label,
                entry.place,
                memberName(entry.memberID),
                entry.mood?.label ?? "",
                entry.note,
                entry.belowTheLine ? "yes" : "no",
                entry.isPrivate ? "yes" : "no",
            ]
            out += fields.map(escape).joined(separator: ",") + "\n"
        }
        return out
    }

    /// RFC 4180: wrap in quotes when the value contains a comma, a quote or a
    /// newline, and double any embedded quotes. A note saying `He said "fine"`
    /// otherwise shreds every column to its right.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: JSON

    /// Everything, structured. Built with `JSONSerialization` rather than
    /// `Codable` so the shape of the file is visible in one place here and
    /// isn't silently coupled to the internal types — those are free to change
    /// without breaking somebody's five-year-old backup.
    static func json(name: String,
                     entries: [Entry],
                     categories: [Bucket],
                     members: [Member],
                     caps: [BudgetStore.CapRow],
                     recurring: [Recurring],
                     loans: [Loan],
                     challenges: [Challenge],
                     monthFlags: [String: MonthFlag],
                     reactions: [String: [Reaction]],
                     rolloverEnabled: Bool) -> Data? {
        let stamp = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "format": "budget-together-export",
            "version": 1,
            "exportedAt": stamp.string(from: Date()),
            "budget": [
                "name": name,
                "rolloverEnabled": rolloverEnabled,
            ],
            "people": members.map { member in
                ["id": member.id, "name": member.name, "colorIndex": member.colorIndex]
            },
            "categories": categories.map { bucket in
                [
                    "id": bucket.id,
                    "name": bucket.label,
                    "kind": bucket.kind.rawValue,
                    "cadence": bucket.cadence.rawValue,
                    "symbol": bucket.symbol,
                    "colorDark": bucket.hex,
                    "colorLight": bucket.lightHex,
                    "isHidden": bucket.isHidden,
                    "isBuiltIn": bucket.isBuiltIn,
                    "order": bucket.sortOrder,
                ]
            },
            "limits": caps.map { cap in
                [
                    "category": cap.bucket,
                    "month": cap.month,
                    "amount": cap.amount,
                    "updatedAt": cap.updatedAt.map(stamp.string(from:)) ?? "",
                ]
            },
            "transactions": entries.map { entry in
                [
                    "id": entry.id,
                    "date": entry.date,
                    "amount": entry.amount,
                    "direction": entry.kind.rawValue,
                    "category": entry.bucket,
                    "place": entry.place,
                    "memberID": entry.memberID,
                    "mood": entry.mood?.rawValue ?? "",
                    "note": entry.note,
                    "belowTheLine": entry.belowTheLine,
                    "isPrivate": entry.isPrivate,
                    "createdAt": stamp.string(from: entry.createdAt),
                    "reactions": (reactions[entry.id] ?? []).map { reaction in
                        ["memberID": reaction.memberID, "kind": reaction.kind.rawValue]
                    },
                ]
            },
            "recurring": recurring.map { item in
                [
                    "id": item.id,
                    "place": item.place,
                    "amount": item.amount,
                    "category": item.bucket,
                    "memberID": item.memberID,
                    "direction": item.kind.rawValue,
                    "dayOfMonth": item.dayOfMonth,
                    "isActive": item.isActive,
                    "lastPostedMonth": item.lastPostedMonth,
                ]
            },
            "loans": loans.map { loan in
                [
                    "id": loan.id,
                    "name": loan.name,
                    "balance": loan.balance,
                    "annualRate": loan.rate,
                    "monthlyPayment": loan.monthlyPayment,
                ]
            },
            "challenges": challenges.map { challenge in
                [
                    "id": challenge.id,
                    "title": challenge.title,
                    "kind": challenge.kind.rawValue,
                    "category": challenge.bucket ?? "",
                    "target": challenge.target,
                    "startDate": challenge.startDate,
                    "endDate": challenge.endDate,
                ]
            },
            "monthNotes": monthFlags.values.map { flag in
                ["month": flag.month, "isUnusual": flag.isUnusual, "reason": flag.reason]
            },
        ]

        return try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Files

    /// Writes to a uniquely-named temp directory and hands back the URL.
    ///
    /// A fresh subdirectory per export, rather than a fixed filename in the
    /// shared temp dir, so two exports in a row can't have the second one
    /// overwrite a file the share sheet is still reading from the first.
    static func writeTemporary(_ data: Data, named filename: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// "Together-2026-07-27.csv" — dated, so a folder of them sorts sensibly.
    static func filename(budget: String, ext: String) -> String {
        let safe = budget
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = safe.isEmpty ? "budget" : safe
        return "\(stem)-\(Fmt.isoDay(Date())).\(ext)"
    }
}
