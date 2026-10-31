import SwiftUI

// MARK: - Undo toast

/// The offer to take back whatever just happened, for systems without the bar
/// accessory: see `BarAccessory`. Sits above the tab bar, dismisses itself after
/// a few seconds, and can be swiped away.
///
/// This is doing more work than it looks like it is: nothing else in the app
/// changes how *safe* it feels to tap something, and a delete that can't be
/// taken back makes people cautious with every other control too.
struct UndoToast: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            .padding(.horizontal, Space.md)
            .padding(.bottom, Space.xs)
            .readableColumn()
            // The one place Reduce Motion can't just remove the animation. This
            // offer expires on its own, so it has to be noticed to be taken —
            // appearing from nowhere with no change to catch the eye is worse
            // for the person the setting exists for, not better. So the slide
            // becomes a cross-fade, and the spring — which overshoots, and
            // overshoot is the motion being objected to — becomes a plain ease.
            .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            .animation(reduceMotion
                       ? .easeInOut(duration: 0.2)
                       : .spring(response: 0.34, dampingFraction: 0.86),
                       value: prompt.id)
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

// MARK: - Bar accessory

/// The undo offer and the sample-data reminder, in the glass bar iOS keeps above
/// the tab bar. Both are about the whole app rather than one screen, which is
/// what that bar is for, and the undo offer outranks the reminder while it lasts.
///
/// Before iOS 26.1 it can't be switched off when there's nothing to say, so
/// `UndoToast` and `SampleDataBar` do these jobs from inside each tab instead.
@available(iOS 26.1, *)
struct BarAccessory: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false

    var body: some View {
        Group {
            if let prompt = model.undoPrompt {
                row(Text(prompt.message), action: "Undo", hint: "Puts it back") { model.undo() }
                    // Announced rather than silently drawn — the offer is
                    // time-limited, so a VoiceOver user who doesn't hear about
                    // it can't take it.
                    .accessibilityAddTraits(.isModal)
            } else {
                // How much room this gets varies more than it looks: the row shrinks
                // when the tab bar does, and again beside a bar on its end.
                row(ViewThatFits(in: .horizontal) {
                    Text("You're looking at sample data")
                    Text("Sample data")
                }, action: "Start mine", hint: nil) { confirming = true }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .sampleDataConfirmation(isPresented: $confirming)
    }

    private func row(_ message: some View, action: String, hint: String?,
                     perform: @escaping () -> Void) -> some View {
        HStack(spacing: Space.xs) {
            message
                .appFont(13, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: Space.xxs)
            Button(action, action: perform)
                .appFont(13, weight: .semibold)
                .foregroundStyle(Palette.teal)
                .accessibilityHint(hint ?? "")
        }
        .padding(.horizontal, Space.md)
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
                        .appFont(12, weight: .semibold)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Palette.tealInk)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.xs)
            .readableColumn()
            .background(Palette.chip)
            // Chrome pinned above every screen, like the tab bar: it has to stay
            // a bar rather than grow into a panel that owns half the display.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .sampleDataConfirmation(isPresented: $confirming)
        }
    }
}

extension View {
    /// The one question before the sample goes.
    fileprivate func sampleDataConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(SampleDataConfirmation(isPresented: isPresented))
    }
}

private struct SampleDataConfirmation: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Clear the sample and start your own budget?",
                                   isPresented: $isPresented, titleVisibility: .visible) {
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
