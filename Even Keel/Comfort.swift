import SwiftUI

// MARK: - Comfort
//
// The three things a money app owes anyone who finds it stressful: text that
// obeys the size they chose, motion that stops when they've asked for less of
// it, and a small physical acknowledgement when something lands.
//
// Every font in this app was a hardcoded `.system(size:)`, which silently
// ignores Dynamic Type. `appFont` is the drop-in replacement, and it has become
// the type scale as well. Twenty-seven nominal sizes had accumulated, most of
// them a point or two under anything iOS uses — 11.5 and 12.5 and 13.5 — which is
// a large part of why the app read as small and foreign beside the system. Each
// one now lands on Apple's nearest text style, a step up, so a 10pt label still
// grows faster than a 44pt hero number and the layout keeps its hierarchy.

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var displaySize: CGFloat
    private let style: Font.TextStyle?
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        // Only reads for display sizes, which have no text style of their own.
        _displaySize = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.style = Self.style(for: size)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        if let style {
            content.font(.system(style, design: design, weight: weight))
        } else {
            content.font(.system(size: displaySize, weight: weight, design: design))
        }
    }

    /// The text style a nominal size lands on, or nil for display figures
    /// larger than any of them. Small type scales hardest — it's the type that's
    /// actually illegible at default settings — while display numbers grow most
    /// gently. Picking one style for everything would scale a tab label and a
    /// 52pt balance by the same factor and blow the layout apart.
    static func style(for size: CGFloat) -> Font.TextStyle? {
        switch size {
        case ..<10.5: .caption2     // 11
        case ..<11.5: .caption      // 12
        case ..<13:   .footnote     // 13
        case ..<14:   .subheadline  // 15
        case ..<15:   .callout      // 16
        case ..<19:   .body         // 17
        case ..<21:   .title3       // 20
        case ..<26:   .title2       // 22
        case ..<32:   .title        // 28
        default:      nil
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

// MARK: - Readable width
//
// Every screen was laid out for a phone held upright, and never had to fill
// anything wider than about 440 points. iOS 27 ends that: an app built against
// its SDK resizes with its window, and on iPhone Duo's inner display — or in a
// resized iPhone Mirroring window — it gets an iPad's width whatever
// orientation it asked for. Left to stretch, a category's name and its figures
// end up a hand-span apart and every progress bar runs the width of the display.
//
// So content keeps to a centred column of comfortable reading width, and only
// backgrounds and bars run edge to edge. The cap scales with Dynamic Type, so
// larger text gets a wider column rather than more wrapping; at the
// accessibility sizes it stops binding at all.

private struct ReadableColumn: ViewModifier {
    @ScaledMetric private var width: CGFloat

    init(width: CGFloat) {
        _width = ScaledMetric(wrappedValue: width, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Caps content at a readable width and centres it in whatever is left.
    /// Takes the full width itself, so a background applied after it still
    /// reaches both edges.
    func readableColumn(_ width: CGFloat = 640) -> some View {
        modifier(ReadableColumn(width: width))
    }
}

// MARK: - Card flow
//
// A column of one on a phone, and as many as fit on anything wider. It measures
// the width it was actually given rather than asking for a size class, because
// the two disagree often: a sidebar, a pinned panel or a resized window can leave
// a "regular" scene with a phone's width of content, and the other way round on
// iPhone Duo's inner display.
//
// Each card goes in whichever column is currently shortest, so cards of
// different heights pack together instead of leaving the holes a grid's rows
// would. With one column that's plain reading order, identical to a `VStack`.

struct CardFlow: Layout {
    var minimumColumnWidth: CGFloat
    var maximumColumns = 2
    var spacing: CGFloat

    private func columnCount(in width: CGFloat) -> Int {
        let fitting = Int((width + spacing) / (minimumColumnWidth + spacing))
        return min(max(fitting, 1), maximumColumns)
    }

    /// Where each subview goes, and how tall the result is.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let columns = columnCount(in: width)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var heights = [CGFloat](repeating: 0, count: columns)
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            // An empty card — a conditional that came out false — takes no
            // gap, or a phone would show it as a double space.
            guard size.height > 0 else {
                frames.append(.zero)
                continue
            }
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let y = heights[column]
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: y,
                                 width: columnWidth, height: size.height))
            heights[column] = y + size.height + spacing
        }
        return (frames, max((heights.max() ?? 0) - spacing, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            // The height stays open. Proposing the exact figure that was just
            // measured turns it into a constraint, and `minimumScaleFactor` reads
            // height as well as width: figures shrank to half size to "fit".
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: nil))
        }
    }
}

/// `CardFlow` with its column width scaled to the text, so larger type gets
/// fewer, wider columns rather than cramped ones.
struct AdaptiveCards<Content: View>: View {
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 340
    var spacing: CGFloat = Space.md
    @ViewBuilder var content: Content

    var body: some View {
        CardFlow(minimumColumnWidth: minimumColumnWidth, spacing: spacing) { content }
    }
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
        .padding(Space.md)
        .card()
    }

    private func cell(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(stat.title).appFont(12, weight: .medium).foregroundStyle(Palette.sub)
            Text(stat.value).mono(19).foregroundStyle(stat.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Name-and-figures row

/// A name on the left and figures on the right — the shape of most rows in the
/// app — or, past the accessibility sizes, the figures on a line of their own
/// under the name.
///
/// Side by side at those sizes, the figures won and the name lost: "Housing"
/// broke into "Housi" and "ng", and a share column 38pt wide wrapped "62%"
/// into "62" over "%". Same rule as `StatRow`: nothing dropped, only the axis
/// changes.
struct AdaptiveRow<Name: View, Figures: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = 10
    @ViewBuilder var name: Name
    @ViewBuilder var figures: Figures

    var body: some View {
        if typeSize.prefersStackedLayout {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: spacing) { name }
                HStack(spacing: spacing) {
                    Spacer(minLength: 0)
                    figures
                }
            }
        } else {
            HStack(spacing: spacing) {
                name
                Spacer(minLength: 4)
                // First claim on the width. Nested in their own stack, the
                // figures were being offered an even share with the name and
                // the spacer, and gave way from the cheapest end — the currency
                // symbol in front of a limit box shrank to nothing. A name can
                // truncate; a figure can't.
                HStack(spacing: spacing) { figures }
                    .layoutPriority(1)
            }
        }
    }
}

extension View {
    /// A right-aligned column of short figures — shares, counts — that keeps its
    /// width at the default sizes so the rows line up, and grows past it rather
    /// than wrapping when the text does.
    func figureColumn(width: CGFloat) -> some View {
        lineLimit(1)
            .fixedSize()
            .frame(minWidth: width, alignment: .trailing)
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
