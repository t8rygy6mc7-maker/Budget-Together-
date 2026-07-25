import SwiftUI

// MARK: - Palette (from "Budget App - Midnight" design comp)

enum Palette {
    static let screen         = Color(hex: "141620")
    static let card           = Color(hex: "1D2130")
    static let cardBorder     = Color(hex: "2A3042")
    static let cardBorderSoft = Color(hex: "23283A")
    static let navBar         = Color(hex: "181B27")
    static let navBorder      = Color(hex: "262B3A")
    static let sheetBg        = Color(hex: "1A1D29")
    static let field          = Color(hex: "141620")
    static let chip           = Color(hex: "232838")

    static let text     = Color(hex: "EDEFF7")
    static let sub      = Color(hex: "7C8199")
    static let muted    = Color(hex: "565C72")
    static let label9   = Color(hex: "9AA0B6")
    static let chipText = Color(hex: "B7BDD0")

    static let teal      = Color(hex: "5EEAD4")
    static let tealInk   = Color(hex: "0C2B26")
    static let green     = Color(hex: "3FB984")
    static let purple    = Color(hex: "C69BFF")
    static let purpleInk = Color(hex: "2A1740")
    static let over      = Color(hex: "E86A4A")
    static let overText  = Color(hex: "F6A5C8")

    static let tealGradient = LinearGradient(
        colors: [teal, green], startPoint: .topLeading, endPoint: .bottomTrailing
    )
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
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
