import SwiftUI

// MARK: - Empty states
//
// An empty screen is the first thing most people see, and for a while it's the
// only thing. Every one of these used to be a single grey sentence that named
// the absence and stopped there ("Nothing logged this month yet."). They now
// name the absence, say what it's for, and offer the tap that fills it.

/// The shape every empty state in the app takes: an icon, a line, a softer
/// second line, and — where there's something useful to do — one button.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .appFont(20, weight: .semibold)
                .foregroundStyle(Palette.teal)
                .frame(width: 52, height: 52)
                .background(Palette.teal.opacity(0.14), in: Circle())
                .padding(.bottom, 2)

            Text(title)
                .appFont(15, weight: .semibold)
                .multilineTextAlignment(.center)

            Text(message)
                .appFont(12.5)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .appFont(13.5, weight: .bold)
                        .foregroundStyle(Palette.tealInk)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Palette.tealGradient,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 28)
    }
}

/// Home, before anything has been logged. The one place in the app where a
/// first-time user is guaranteed to land, so it carries the invitation rather
/// than a statement of absence.
struct EmptySpendPrompt: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        EmptyState(
            symbol: "sparkles",
            title: model.members.count > 1 ? "Nothing logged yet" : "Let's start with one thing",
            message: "Add anything you spent today — a coffee counts. "
                   + "Once there are a few, this fills in with where the money actually went.",
            actionTitle: "Add the first one",
            action: { model.isAddingEntry = true }
        )
        .card(border: Palette.cardBorderSoft, radius: 18)
        .padding(.top, 12).padding(.bottom, 4)
    }
}
