import SwiftUI

// MARK: - Chrome
//
// What a screen is standing in, as opposed to what's on it. The app used to draw
// all of this for itself: its own tab bar, its own title row, its own close
// button on every sheet. Each was fine alone and together they were why it felt
// ported. None of them took part in anything the system does — a swipe back, a
// title collapsing into its bar, Liquid Glass — so all of it now comes from
// SwiftUI, and this file is the small amount of glue in between.
//
// **Where glass goes.** Apple's guidance is that Liquid Glass is the navigation
// layer floating above content, and that custom uses should be rare. So almost
// everything here gets it for free from a system bar or sheet, and cards stay
// solid. The two helpers below are for the few real controls that want it.
//
// **Older systems.** The deployment target is below iOS 26, so each glass API
// has a plain fallback beside it.

// MARK: - Page

/// One scrolling screen: its title in the navigation bar, and its content at the
/// app's margins, in a column wide enough for `AdaptiveCards` to spread out.
struct Page<Content: View>: View {
    /// Where a page sits, which decides what's behind it.
    enum Surface { case screen, sheet }

    let title: String
    var subtitle: String?
    var displayMode: NavigationBarItem.TitleDisplayMode = .large
    var surface = Surface.screen
    var maxWidth: CGFloat = 1040
    @ViewBuilder var content: Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // iOS 26 puts this in the navigation bar; see below.
                if let subtitle, !Self.barHoldsSubtitle {
                    Text(subtitle)
                        .appFont(13)
                        .foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Space.sm)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableColumn(maxWidth)
        }
        .contentMargins(.horizontal, Space.margin(for: sizeClass), for: .scrollContent)
        .contentMargins(.top, Space.xs, for: .scrollContent)
        .contentMargins(.bottom, Space.lg, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .background { if surface == .screen { Palette.screen.ignoresSafeArea() } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(displayMode)
        .barSubtitle(subtitle)
    }

    fileprivate static var barHoldsSubtitle: Bool {
        if #available(iOS 26, *) { true } else { false }
    }
}

extension View {
    @ViewBuilder
    fileprivate func barSubtitle(_ subtitle: String?) -> some View {
        if #available(iOS 26, *), let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    /// The month under a tab's title, and the arrows that change it. `detail`
    /// joins the month on that line.
    func monthControls(detail: String? = nil) -> some View {
        modifier(MonthControls(detail: detail))
    }

    /// Keeps a `List` to the same margins as a `Page`, and to a readable column
    /// on a wide display, while it still scrolls from the edges.
    func listColumn() -> some View { modifier(ListColumn()) }
}

private struct ListColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var column: CGFloat = 720
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            if sizeClass == .regular {
                // Added to the safe area rather than set as content margins: on a
                // `List`, content margins lose their trailing side beside a pinned
                // panel, and the rows ran straight into it.
                content.safeAreaPadding(.horizontal, max((width - column) / 2, 0))
            } else {
                content.contentMargins(.horizontal, Space.margin(for: sizeClass),
                                       for: .scrollContent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.screen.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

// MARK: - Modal

/// A self-contained task: adding, editing, confirming. Anything that's a place to
/// go rather than a job to finish is pushed instead, so that swiping back works
/// and there's always a way out without aiming for a button.
///
/// The bar carries the title and the close button; a form adds its own save with
/// `.toolbar { ConfirmItem(...) }` from inside `content`, where the keyboard can
/// never cover it the way it used to cover a button at the bottom of the form.
struct ModalPage<Content: View>: View {
    let title: String
    var subtitle: String?
    var detents: Set<PresentationDetent> = [.large]
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            Page(title: title, subtitle: subtitle, displayMode: .inline, surface: .sheet) {
                content
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseButton() }
            }
        }
        .presentationDetents(detents)
        .modalSurface(isGlass: detents.count > 1)
    }
}

extension View {
    /// The background and tint every sheet shares.
    ///
    /// iOS 26 draws a sheet in glass while it's below full height, and a
    /// `presentationBackground` would quietly switch that off. So only a sheet
    /// that's always full height sets one: at that height the system goes opaque
    /// anyway, and a neutral grey there sits badly with the app's navy cards.
    @ViewBuilder
    func modalSurface(isGlass: Bool = false) -> some View {
        Group {
            if #available(iOS 26, *), isGlass {
                self
            } else {
                presentationBackground(Palette.sheetBg)
            }
        }
        .foregroundStyle(Palette.text)
        .tint(Palette.teal)
    }
}

struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    /// For a panel that can be pinned, which `dismiss` can't reach.
    var action: (() -> Void)?

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close, action: close)
        } else {
            Button("Close", action: close)
        }
    }

    private func close() {
        if let action { action() } else { dismiss() }
    }
}

/// The bar's confirm action. A tinted check on iOS 26, "Save" before it.
struct ConfirmItem: ToolbarContent {
    var title = "Save"
    var isEnabled = true
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Group {
                if #available(iOS 26, *) {
                    Button(role: .confirm, action: action)
                } else {
                    Button(title, action: action).fontWeight(.semibold)
                }
            }
            .disabled(!isEnabled)
            .accessibilityLabel(title)
        }
    }
}

/// The bar's "add one of these" on a pushed screen, where it stays in reach
/// however long the list gets. It used to be a full-width button under the list.
struct AddItem: ToolbarContent {
    let label: String
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: action) { Label(label, systemImage: "plus") }
        }
    }
}

// MARK: - Month controls

private struct MonthControls: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let detail: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !model.isCurrentMonth {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("This month") { step { model.goToCurrentMonth() } }
                    }
                }
                // Kept out of the overflow menu when a pinned panel leaves the
                // bar short of room: a month you can't change is a dead end.
                if #available(iOS 27, *) {
                    arrows.visibilityPriority(.high)
                } else {
                    arrows
                }
            }
            .modifier(MonthTitle(title: [model.monthTitle, detail].compactMap { $0 }
                .joined(separator: " · ")))
            // Figures roll to their new values rather than being swapped. See
            // `mono`. Only ever a change of month: this is the one thing that
            // rewrites a whole screen's numbers at once.
            .appAnimation(.snappy(duration: 0.3), value: model.selectedMonth)
    }

    private var arrows: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { step { model.stepMonth(-1) } } label: {
                Label("Previous month", systemImage: "chevron.left")
            }
            Button { step { model.stepMonth(1) } } label: {
                Label("Next month", systemImage: "chevron.right")
            }
            .disabled(!model.canGoForward)
        }
    }

    private func step(_ change: () -> Void) {
        Haptics.selected()
        change()
    }
}

/// iOS 26 sets the month under the large title. Before it there's no such line,
/// and the month sits in the middle of the bar.
private struct MonthTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationSubtitle(title)
        } else {
            content.toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).appFont(13, weight: .semibold).foregroundStyle(Palette.sub)
                }
            }
        }
    }
}

// MARK: - Buttons

extension View {
    /// The one thing a screen most wants pressed. Glass where it's a floating
    /// control; the same shape in a solid fill before iOS 26.
    @ViewBuilder
    func primaryButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// A companion to `primaryButtonStyle`.
    @ViewBuilder
    func secondaryButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// Grows a sheet out of the control that opened it, where the system can.
    @ViewBuilder
    func morphs(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// A small action sitting in content, like "Move money here". Tinted rather
    /// than glass: cards are the content layer, and glass on glass is what
    /// Apple asks apps to avoid.
    func inlineActionStyle() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
    }
}

/// A full-width primary button, for a form's single action where the bar can't
/// carry it: "Add a goal", "Don't count this month".
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .appFont(15, weight: .semibold)
            .foregroundStyle(isEnabled ? Palette.tealInk : Palette.muted)
            .frame(maxWidth: .infinity)
        }
        .primaryButtonStyle()
        .disabled(!isEnabled)
    }
}

/// A full-width quieter button, for the alternative beside a `PrimaryButton`.
struct SecondaryButton: View {
    let title: String
    var color: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(15, weight: .semibold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
        }
        .secondaryButtonStyle()
    }
}

// MARK: - Grouped rows

/// Rows sharing one rounded surface with hairlines between, the shape of every
/// settings list on iOS. Five separate outlined cards in a stack was the largest
/// single thing that made Home look like a web dashboard.
///
/// Each row draws its own separator along its bottom. The last one is pulled just
/// past the clip so it never shows, which saves every caller from working out
/// which of its conditional rows happens to come last.
struct RowGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title { SectionTitle(title) }
            VStack(spacing: 0) { content }
                .padding(.bottom, -1)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .card()
            if let footer {
                Text(footer)
                    .appFont(11.5)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.md)
            }
        }
    }
}

/// A section's heading. Title case, sitting at the row inset as `List` headers do.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .appFont(13, weight: .semibold)
            .foregroundStyle(Palette.sub)
            .padding(.horizontal, Space.md)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The inset and hairline every row in a `RowGroup` shares, for rows that aren't
/// a `RowLabel`.
struct GroupedRow<Content: View>: View {
    /// Where the separator starts: past the icon when there is one.
    var separatorInset: CGFloat = Space.md
    @ViewBuilder var content: Content
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.cardBorderSoft)
                    .frame(height: 1 / displayScale)
                    .padding(.leading, separatorInset)
            }
    }
}

/// The small tinted square that fronts most rows.
struct IconTile: View {
    let symbol: String
    let color: Color
    /// Categories carry their own tint. Everything else takes a wash of `color`.
    var fill: Color?
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .appFont(13, weight: .semibold)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(fill ?? color.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// Icon, title, a line under it, and something at the trailing edge. Most rows in
/// the app are this, and it had been written out by hand two dozen times.
struct RowLabel<Trailing: View>: View {
    let symbol: String
    var color: Color = Palette.teal
    var fill: Color?
    let title: Text
    var subtitle: Text?
    var subtitleColor: Color = Palette.sub
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GroupedRow(separatorInset: Space.md + 32 + Space.sm) {
            HStack(spacing: Space.sm) {
                IconTile(symbol: symbol, color: color, fill: fill)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .appFont(14, weight: .medium)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        subtitle
                            .appFont(11.5)
                            .foregroundStyle(subtitleColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.xxs)
                trailing
            }
            .foregroundStyle(Palette.text)
        }
    }
}

extension RowLabel where Trailing == Disclosure {
    /// A row that goes somewhere, with the chevron that says so.
    init(symbol: String, color: Color = Palette.teal, fill: Color? = nil,
         title: Text, subtitle: Text? = nil, subtitleColor: Color = Palette.sub) {
        self.init(symbol: symbol, color: color, fill: fill, title: title,
                  subtitle: subtitle, subtitleColor: subtitleColor) { Disclosure() }
    }
}

struct Disclosure: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .appFont(11, weight: .semibold)
            .foregroundStyle(Palette.muted)
            .accessibilityHidden(true)
    }
}

/// The highlight a list row gives on touch, for rows that aren't in a `List`.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Palette.chip : .clear)
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
}
