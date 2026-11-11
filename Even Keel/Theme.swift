import SwiftUI

// MARK: - Appearance

/// What the user picked in People → Appearance. `system` defers to iOS.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "iphone"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }

    /// `nil` hands the decision back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

// MARK: - Palette
//
// Every token is a *dynamic* colour holding both schemes, resolved by UIKit
// against the view's trait collection. Call sites stay scheme-agnostic — there
// is deliberately no `if colorScheme == .dark` anywhere in the view code.
//
// The dark values are the original "Budget App - Midnight" comp, except for
// `sub` and `muted`, which were lifted to clear WCAG AA — see DESIGN-NOTES §4c.
// The light values are derived from them: hue and saturation are preserved so a
// bucket keeps its identity across schemes, and lightness is inverted into a
// light-surface band and then darkened until it clears WCAG AA (4.5:1) against
// both `card` and `screen`. See DESIGN-NOTES.md §4 for the measured table.

enum Palette {
    // Surfaces. In both schemes `card` lifts off `screen` and `field` recedes
    // into it — the direction of the lift flips, the relationship does not.
    static let screen         = Color(dark: "141620", light: "F4F5F9")
    static let card           = Color(dark: "1D2130", light: "FFFFFF")
    static let cardBorderSoft = Color(dark: "23283A", light: "E5E9F3")
    static let sheetBg        = Color(dark: "1A1D29", light: "FBFCFE")
    static let field          = Color(dark: "141620", light: "EFF1F7")
    static let chip           = Color(dark: "232838", light: "EAEDF5")

    // The neutral type ladder, listed least-prominent first. Every rung clears
    // 4.5:1 for active text on the surface that governs it — `card` in dark,
    // `screen` in light. `muted` sits right on that floor in dark, so it has no
    // headroom left: a lighter surface, or a lighter `chip`, breaks it first.
    // In dark the L* order matches the order below; in light `sub` and `label9`
    // are swapped. See DESIGN-NOTES §4c.
    static let text     = Color(dark: "EDEFF7", light: "1B1F2B")
    static let sub      = Color(dark: "8F94AC", light: "5A6076")
    static let muted    = Color(dark: "82889F", light: "686F84")
    static let label9   = Color(dark: "9AA0B6", light: "646B82")
    static let chipText = Color(dark: "B7BDD0", light: "474D61")

    static let teal      = Color(dark: "5EEAD4", light: "107F6E")
    static let tealInk   = Color(dark: "0C2B26", light: "FFFFFF")
    static let green     = Color(dark: "3FB984", light: "2B7E5A")
    static let purple    = Color(dark: "C69BFF", light: "390085")
    static let over      = Color(dark: "E86A4A", light: "BC3918")
    static let overText  = Color(dark: "F6A5C8", light: "790C3B")

    // Mood palette. Deliberately desaturated against the bucket hues — a mood
    // is context on a row, never the thing being measured.
    static let moodJoy     = Color(dark: "F5C15E", light: "98670A")
    static let moodStress  = Color(dark: "F2555A", light: "D51017")
    static let moodBoredom = Color(dark: "8892B0", light: "626E93")
    static let moodRoutine = Color(dark: "7FB2FF", light: "0048B6")
    static let moodSocial  = Color(dark: "C69BFF", light: "390085")
    static let moodRegret  = Color(dark: "E0846A", light: "BB4827")

    static let tealGradient = LinearGradient(
        colors: [teal, green], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// What lifts a card off the screen in light, where white on near-white has
    /// next to no contrast of its own. Nothing in dark: the surfaces already
    /// step in lightness, and a shadow on navy reads as a smudge. Opacity is
    /// baked into the colour because `.opacity()` at the call site cannot vary
    /// by scheme.
    static let cardShadow = Color(dark: "000000", darkAlpha: 0,
                                  light: "1B1F2B", lightAlpha: 0.05)
}

// MARK: - Spacing and shape
//
// Twenty different horizontal paddings and as many corner radii had built up,
// each one locally reasonable and together the reason the screens never quite
// lined up. Everything now comes off two short scales. A value that isn't on
// them is a decision somebody should be able to defend.

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40

    /// The distance from a screen's edge to its content. This is where the large
    /// title sits at either size, so cards and headings share one edge.
    static func margin(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? lg : md
    }
}

enum Radius {
    /// A card or group of rows. Matches the rounder sections iOS 26 gave `List`.
    static let card: CGFloat = 22
    /// Something inside a card: a field, a chip. Card radius less its inset,
    /// which is what keeps nested corners looking concentric.
    static let control: CGFloat = 14
    /// The small tinted square behind an icon.
    static let tile: CGFloat = 9
}

// MARK: - Reusable styling

private struct CardBackground: ViewModifier {
    let border: Color?
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                shape.fill(Palette.card)
                    .shadow(color: Palette.cardShadow, radius: 14, y: 5)
            }
            .overlay {
                if let border { shape.strokeBorder(border, lineWidth: 1) }
            }
    }
}

extension View {
    /// A raised surface. Separation comes from the fill, the way a grouped list
    /// does it; the outline every card used to wear was what made the app read
    /// as a web page. Pass `border` only when it means something, like
    /// "this one needs an answer".
    func card(border: Color? = nil, radius: CGFloat = Radius.card) -> some View {
        modifier(CardBackground(border: border, radius: radius))
    }

    /// Figures that line up in a column. Scales with Dynamic Type like every
    /// other size in the app — see `Comfort.swift`.
    ///
    /// SF's tabular digits, not SF Mono: only the digits need to be fixed-width,
    /// and in the mono face the comma took a full cell, so "$1,992" read as
    /// "$1, 992". Hero figures use the rounded design, the way Fitness and
    /// Wallet set theirs.
    ///
    /// Never wraps. At large text sizes an unconstrained "$1,965" breaks after
    /// the comma and renders as "$1,96" above a lone "5", which is not a
    /// degraded reading of the number — it's a different number. Shrinking to
    /// fit is the only acceptable failure mode for a figure.
    func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        appFont(size, weight: weight, design: size >= 28 ? .rounded : .default)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // Inert until something animates: stepping a month rolls the
            // figures to their new values rather than swapping them.
            .contentTransition(.numericText())
    }

    /// Rounded fill for text fields and the pickers in `AddSheet`. The outline
    /// is for selection, so an unselected chip passes none.
    func fieldBackground(
        _ fill: some ShapeStyle = Palette.field,
        border: Color? = nil,
        radius: CGFloat = Radius.control
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill, in: shape)
            .overlay {
                if let border { shape.strokeBorder(border, lineWidth: 1.5) }
            }
    }
}

// MARK: - Color hex

extension Color {
    /// Accepts "RRGGBB" with an optional leading "#". Unparseable input yields black.
    init(hex: String) {
        let (r, g, b) = Color.rgbComponents(hex)
        self.init(red: r, green: g, blue: b)
    }

    /// A colour that resolves per colour scheme. Built once, at static-init
    /// time — resolving it afterwards is a trait lookup, not a `Scanner` parse.
    init(dark: String, darkAlpha: Double = 1, light: String, lightAlpha: Double = 1) {
        #if canImport(UIKit)
        let darkColor = UIColor(hex: dark, alpha: darkAlpha)
        let lightColor = UIColor(hex: light, alpha: lightAlpha)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
        #else
        self.init(hex: dark)
        #endif
    }

    static func rgbComponents(_ hex: String) -> (Double, Double, Double) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }
}

#if canImport(UIKit)
extension UIColor {
    fileprivate convenience init(hex: String, alpha: Double = 1) {
        let (r, g, b) = Color.rgbComponents(hex)
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
#endif
