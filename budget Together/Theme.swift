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
    static let cardBorder     = Color(dark: "2A3042", light: "D6DBE9")
    static let cardBorderSoft = Color(dark: "23283A", light: "E5E9F3")
    static let navBar         = Color(dark: "181B27", light: "FFFFFF")
    static let navBorder      = Color(dark: "262B3A", light: "DDE2EE")
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
    static let purpleInk = Color(dark: "2A1740", light: "FFFFFF")
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

    /// Glow under the floating add button. A coloured bloom only reads as light
    /// on a dark surface; on white the same shadow looks like a smudge, so the
    /// light scheme uses a plain neutral drop shadow instead. Opacity is baked
    /// into the colour because `.opacity()` at the call site cannot vary by
    /// scheme.
    static let addGlow = Color(dark: "5EEAD4", darkAlpha: 0.55,
                               light: "0F1729", lightAlpha: 0.18)
}

// MARK: - Reusable styling

private struct CardBackground: ViewModifier {
    let border: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }
}

extension View {
    func card(border: Color = Palette.cardBorder, radius: CGFloat = 18) -> some View {
        modifier(CardBackground(border: border, radius: radius))
    }

    func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
    }

    /// Rounded field/chip background with a hairline border — used by text
    /// fields and the pickers in `AddSheet`.
    func fieldBackground(
        _ fill: some ShapeStyle = Palette.field,
        border: Color = Palette.cardBorder,
        radius: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
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
