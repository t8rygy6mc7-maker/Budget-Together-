import Foundation

// MARK: - Zero-click categorization
//
// There's no bank feed, so nothing arrives needing to be sorted — the user
// types a place name. The work this saves is the tap that follows: guess the
// category from the name and have it already selected.
//
// The guess comes from the household's own history first, because "Joe's" means
// whatever it meant last time in *this* ledger, and that beats any general
// model. A small keyword table covers the cold start before there's history.

struct CategoryGuess {
    let bucket: String
    /// Roughly, how much to trust it. Drives whether the UI says anything.
    let confidence: Double
    /// Why we think so, so the UI can explain itself.
    let reason: String

    /// Below this, say nothing and leave the default selected.
    static let threshold = 0.5
}

protocol CategorySuggesting {
    func suggest(place: String, kind: EntryKind) -> CategoryGuess?
}

/// Learned from past entries, with a keyword fallback. Deterministic, instant,
/// and never leaves the device.
struct HistoryCategorizer: CategorySuggesting {
    /// normalised place → bucket id → how often, most recent first on ties.
    private let index: [String: [String: Int]]

    init(entries: [Entry]) {
        var index: [String: [String: Int]] = [:]
        for entry in entries where entry.kind == .expense {
            let key = Self.normalise(entry.place)
            guard !key.isEmpty else { continue }
            index[key, default: [:]][entry.bucket, default: 0] += 1
        }
        self.index = index
    }

    func suggest(place: String, kind: EntryKind) -> CategoryGuess? {
        // Income sources are a short, closed list — guessing adds nothing.
        guard kind == .expense else { return nil }
        let key = Self.normalise(place)
        guard key.count >= 3 else { return nil }

        if let exact = best(for: key) {
            // Seen this exact place before: as certain as this gets.
            return CategoryGuess(bucket: exact.bucket,
                                 confidence: exact.count >= 2 ? 0.95 : 0.8,
                                 reason: exact.count >= 2
                                    ? "You've filed \(place) here \(exact.count) times"
                                    : "Last time you filed \(place) here")
        }

        // Then a place that starts the same way — "trader joe" as they type.
        if let partial = index.keys
            .filter({ $0.hasPrefix(key) || key.hasPrefix($0) })
            .compactMap({ best(for: $0) })
            .max(by: { $0.count < $1.count }) {
            return CategoryGuess(bucket: partial.bucket, confidence: 0.7,
                                 reason: "Matches somewhere you've logged before")
        }

        // Finally the built-in table, for a household with no history yet.
        if let keyword = Self.keywords.first(where: { key.contains($0.key) }) {
            return CategoryGuess(bucket: keyword.value, confidence: 0.6,
                                 reason: "Usually a \(Bucket.named(keyword.value).short) sort of place")
        }
        return nil
    }

    private func best(for key: String) -> (bucket: String, count: Int)? {
        guard let counts = index[key],
              let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, top.value)
    }

    static func normalise(_ place: String) -> String {
        place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Deliberately small. It exists to cover the first few entries, not to be a
    /// merchant database the app pretends to maintain.
    private static let keywords: [String: String] = [
        "coffee": "food", "cafe": "food", "starbucks": "food", "grocer": "food",
        "market": "food", "restaurant": "food", "pizza": "food", "bar": "food",
        "uber": "transport", "lyft": "transport", "gas": "transport",
        "shell": "transport", "parking": "transport", "train": "transport",
        "netflix": "subs", "spotify": "subs", "subscription": "subs",
        "rent": "housing", "mortgage": "housing", "electric": "housing",
        "pharmacy": "personal", "gym": "personal", "doctor": "personal",
        "amazon": "shopping", "target": "shopping", "store": "shopping",
    ]
}
