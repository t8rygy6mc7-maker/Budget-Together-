import SwiftUI

// MARK: - Comfort
//
// The three things a money app owes anyone who finds it stressful: text that
// obeys the size they chose, motion that stops when they've asked for less of
// it, and a small physical acknowledgement when something lands.
//
// Every font in this app was a hardcoded `.system(size:)`, which silently
// ignores Dynamic Type. `appFont` is the drop-in replacement: same call shape,
// but the size is scaled by `@ScaledMetric` against a text style chosen to suit
// its role, so a 10pt label grows faster than a 44pt hero number and the layout
// keeps its hierarchy instead of collapsing into one size.

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// Which text style a nominal size should track. Small type scales hardest
    /// — it's the type that's actually illegible at default settings — while
    /// display numbers track `.largeTitle`, which grows most gently. Picking one
    /// style for everything would scale a 9.5pt tab label and a 52pt balance by
    /// the same factor and blow the layout apart at the top of the range.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11:  .caption2
        case ..<13:  .caption
        case ..<15:  .footnote
        case ..<17:  .subheadline
        case ..<20:  .body
        case ..<26:  .title3
        case ..<34:  .title2
        default:     .largeTitle
        }
    }
}

extension View {
    /// Dynamic-Type-aware replacement for `.font(.system(size:weight:))`.
    func appFont(_ size: CGFloat, weight: Font.Weight = .regular,
                 design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

// MARK: - Layout thresholds

extension DynamicTypeSize {
    /// Past this, horizontal rows of three or four items stop fitting and the
    /// layouts that use them switch to stacking.
    var prefersStackedLayout: Bool { self >= .accessibility1 }
}

// MARK: - Stat row

/// One labelled figure in a `StatRow`.
struct Stat: Identifiable {
    let title: String
    let value: String
    var color: Color = Palette.text
    var id: String { title }
}

/// Two or three figures side by side in a card — the "Budget left / Safe
/// daily / Days left" pattern Home uses in three places.
///
/// Three columns of text stop fitting long before Dynamic Type runs out, so past
/// the accessibility sizes the same figures stack into rows. Nothing is dropped
/// or truncated; only the axis changes.
struct StatRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let stats: [Stat]

    init(_ stats: [Stat]) { self.stats = stats }

    var body: some View {
        Group {
            if typeSize.prefersStackedLayout {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(stats) { cell($0) }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(stats) { cell($0) }
                }
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
        .card()
    }

    private func cell(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            Text(stat.value).mono(20).foregroundStyle(stat.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Motion

// Reduce Motion asks for less *movement*, not for less of everything. Apple's
// guidance names the cross-dissolve as the safe substitute for a slide, so the
// rule this file follows is:
//
//   - animates movement, a resize, or a reflow  ->  suppressed outright
//   - animates only a cross-fade                ->  left alone
//
// Hence the handful of pure-opacity overlays in the app (`JoiningOverlay`,
// `PrivacyCover`, the appearance picker's colour swap) keep their plain
// `.animation(_:value:)` — fading them is already the accommodation. The undo
// toast is the one case needing both halves: it slides, so under the setting it
// trades the slide for a fade rather than appearing with no warning at all. See
// `Toasts.swift`.

enum Motion {
    /// Whether the system has been asked for less movement.
    ///
    /// Read fresh at each call rather than captured, so a change made in iOS
    /// Settings takes hold on the next tap instead of the next launch. Views
    /// that have to *re-render* when it changes should read
    /// `\.accessibilityReduceMotion` from the environment instead — this is for
    /// the imperative sites, which have no body to invalidate.
    static var isReduced: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }
}

/// Reduce-Motion-aware replacement for `withAnimation(_:_:)`.
///
/// `withAnimation(nil)` isn't a no-op wrapper — it applies the change without
/// animating it, which is exactly what the setting asks for on a state change
/// that would otherwise move something.
func withAppAnimation<Result>(_ animation: Animation,
                              _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.isReduced ? nil : animation, body)
}

private struct ReducibleAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Reduce-Motion-aware replacement for `.animation(_:value:)`.
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducibleAnimation(animation: animation, value: value))
    }
}

extension Binding {
    /// Reduce-Motion-aware replacement for `Binding.animation(_:)`.
    ///
    /// This one reads the setting directly rather than from the environment,
    /// because a `Binding` has nowhere to read an environment from. The cost is
    /// that flipping the setting while the sheet is already open doesn't take
    /// hold until the next time the body runs — which any interaction with the
    /// sheet causes anyway.
    func appAnimation(_ animation: Animation) -> Binding<Value> {
        self.animation(Motion.isReduced ? nil : animation)
    }
}

// MARK: - Haptics

/// Small physical confirmations. Deliberately sparse — a buzz on every tap
/// stops meaning anything, so these fire only where something was committed,
/// completed, or refused.
enum Haptics {
    /// Something was written: an entry added, a cap changed.
    static func saved() { notify(.success) }

    /// Something was undone or reversed.
    static func undone() { impact(.rigid) }

    /// A gentle "that crossed a line" — over a cap, a broken challenge.
    static func warned() { notify(.warning) }

    /// A streak day, a badge, a finished challenge.
    static func celebrated() { notify(.success) }

    /// Picking one of several options.
    static func selected() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    #if canImport(UIKit)
    private static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(kind)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    #else
    private static func notify(_ kind: Int) {}
    private static func impact(_ style: Int) {}
    #endif
}
