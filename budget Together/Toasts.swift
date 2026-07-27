import SwiftUI

// MARK: - Undo toast

/// The offer to take back whatever just happened. Sits above the tab bar,
/// dismisses itself after a few seconds, and can be swiped away.
///
/// This is doing more work than it looks like it is: nothing else in the app
/// changes how *safe* it feels to tap something, and a delete that can't be
/// taken back makes people cautious with every other control too.
struct UndoToast: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let prompt = model.undoPrompt {
            HStack(spacing: 12) {
                Text(prompt.message)
                    .appFont(13, weight: .medium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button { model.undo() } label: {
                    Text("Undo")
                        .appFont(13, weight: .bold)
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Palette.teal.opacity(0.14), in: Capsule())
                }
                .accessibilityHint("Puts it back")

                Button { model.dismissUndo() } label: {
                    Image(systemName: "xmark")
                        .appFont(11, weight: .bold)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Palette.screen)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: prompt.id)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { if $0.translation.height > 0 { model.dismissUndo() } }
            )
            // Announced rather than silently drawn — the offer is time-limited,
            // so a VoiceOver user who doesn't hear about it can't take it.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - Sample data bar

/// Persistent reminder that nothing on screen is real, with the way out.
/// Without it, "Look around first" is a trap: the numbers look like a budget,
/// and there's no obvious moment where you're invited to start your own.
struct SampleDataBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirming = false

    var body: some View {
        if model.isSampleHousehold {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .appFont(12, weight: .semibold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're looking at sample data")
                        .appFont(12.5, weight: .semibold)
                    // At accessibility sizes this bar is pinned to the top of
                    // every screen and the second line alone can cost a third
                    // of the display. The first line already says the thing.
                    if !typeSize.prefersStackedLayout {
                        Text("Nothing here is yours. Have a poke around.")
                            .appFont(11)
                            .foregroundStyle(Palette.sub)
                    }
                }
                Spacer(minLength: 4)
                Button { confirming = true } label: {
                    Text("Start mine")
                        .appFont(12, weight: .bold)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Palette.tealInk)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Palette.tealGradient, in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Palette.chip)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.cardBorder).frame(height: 1)
            }
            // Chrome pinned above every screen, like the tab bar: it has to stay
            // a bar rather than grow into a panel that owns half the display.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .confirmationDialog("Clear the sample and start your own budget?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Start my own", role: .destructive) {
                    model.discardSampleAndStartOver()
                }
                Button("Keep looking", role: .cancel) {}
            } message: {
                Text("The sample entries and people all go. Nothing of yours is affected — "
                   + "you haven't set anything up yet.")
            }
        }
    }
}
