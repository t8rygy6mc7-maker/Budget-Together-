import AppIntents
import SwiftUI
import WidgetKit

// MARK: - App Intents
//
// The whole point of a manual-entry budget app is that logging is fast. The
// fastest possible version doesn't involve opening the app at all — say it, or
// tap it on the home screen, and get on with your day.
//
// These live in the app target rather than an extension, which is the reason
// they can talk to `BudgetStore.shared` directly. That also means they may run
// with no `AppModel` in existence, so every `perform` starts by calling
// `prepareForBackgroundWrite()` — without it the category registry is empty and
// every id resolves to "Uncategorised".
//
// One intent, reused three ways: Siri phrases, the Shortcuts app, and the
// widget's tap target. Building it once is why the widget is small.

// MARK: - Category as an entity

/// Lets Siri and Shortcuts offer the household's own categories by name,
/// including any the user invented.
struct CategoryEntity: AppEntity, Identifiable {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        BudgetStore.shared.prepareForBackgroundWrite()
        return identifiers.compactMap { id in
            CategoryRegistry.bucket(id).map { CategoryEntity(id: $0.id, name: $0.label) }
        }
    }

    /// Only the visible spending categories are offered. A hidden one is one
    /// the user has said they don't file things under any more, and Siri
    /// suggesting it would undo that.
    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        BudgetStore.shared.prepareForBackgroundWrite()
        return CategoryRegistry.visible(.expense).map { CategoryEntity(id: $0.id, name: $0.label) }
    }
}

// MARK: - Log a spend

struct LogSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a spend"
    static let description = IntentDescription(
        "Adds a transaction to your budget without opening the app.",
        categoryName: "Logging"
    )

    /// Stays out of the app. The whole value is not having to go there.
    static let openAppWhenRun = false

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Where")
    var place: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) on \(\.$category)") {
            \.$place
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = BudgetStore.shared
        let snapshot = store.prepareForBackgroundWrite()

        guard !snapshot.members.isEmpty else {
            return .result(dialog: "Set your budget up in the app first.")
        }
        guard amount > 0 else {
            return .result(dialog: "That needs to be more than nothing.")
        }

        // An unnamed spend takes its category's name, exactly as it does in the
        // add sheet — "Food & Drink, $12" is a perfectly good ledger line.
        let bucket = resolvedBucket(snapshot: snapshot)
        let typed = (place ?? "").trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty ? bucket.label : typed

        store.addEntry(id: UUID().uuidString,
                       date: Fmt.isoDay(Date()),
                       place: name,
                       amount: amount,
                       bucket: bucket.id,
                       memberID: store.localMemberID ?? snapshot.members[0].id)
        store.notifyChanged()
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Logged \(Fmt.money2(amount)) to \(bucket.label).")
    }

    /// The chosen category, or the household's own best guess from the place
    /// name, or the default. Reuses `HistoryCategorizer` so a spend logged by
    /// voice lands where the same spend typed into the app would.
    @MainActor
    private func resolvedBucket(snapshot: BudgetStore.Snapshot) -> Bucket {
        if let id = category?.id, let chosen = CategoryRegistry.bucket(id) { return chosen }
        if let typed = place?.trimmingCharacters(in: .whitespaces), !typed.isEmpty {
            let guesser = HistoryCategorizer(entries: snapshot.entries)
            if let guess = guesser.suggest(place: typed, kind: .expense),
               guess.confidence >= CategoryGuess.threshold,
               let bucket = CategoryRegistry.bucket(guess.bucket), !bucket.isHidden {
                return bucket
            }
        }
        return Bucket.fallback(for: .expense)
    }
}

// MARK: - Ask what's left

/// The other half of a quick interaction: not logging something, but checking
/// before you spend it.
struct CheckBudgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Check what's left"
    static let description = IntentDescription(
        "Says how much of this month's budget is still unspent.",
        categoryName: "Logging"
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = BudgetStore.shared
        let snapshot = store.prepareForBackgroundWrite()
        let month = Fmt.isoMonth(Date())

        let spent = snapshot.entries
            .filter { $0.date.hasPrefix(month) && $0.kind == .expense }
            .reduce(0) { $0 + $1.amount }
        let plan = store.caps(for: month).values.reduce(0, +)

        guard plan > 0 else {
            return .result(dialog: "\(Fmt.money(spent)) spent this month. You haven't set any limits.")
        }
        let left = plan - spent
        return .result(dialog: left >= 0
            ? "\(Fmt.money(left)) left of \(Fmt.money(plan)) this month."
            : "You're \(Fmt.money(-left)) past the \(Fmt.money(plan)) plan this month.")
    }
}

// MARK: - Siri phrases

/// Phrases that work the moment the app is installed, with no trip to the
/// Shortcuts app. Every phrase has to contain the app name — that's the
/// system's disambiguation, not a style choice.
struct BudgetShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSpendIntent(),
            phrases: [
                "Log a spend in \(.applicationName)",
                "Add a transaction to \(.applicationName)",
                "Log an expense in \(.applicationName)",
            ],
            shortTitle: "Log a spend",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "How much is left in \(.applicationName)",
                "Check \(.applicationName)",
            ],
            shortTitle: "What's left",
            systemImageName: "chart.pie.fill"
        )
    }

    /// Tells the system the values behind `CategoryEntity` have moved.
    ///
    /// Apple's guidance is to call this whenever the options backing an intent
    /// parameter change, and in this app they change often — categories are
    /// user data now, so every rename, hide or addition invalidates what Siri
    /// thinks the choices are.
    @MainActor
    static func refresh() {
        updateAppShortcutParameters()
    }
}
