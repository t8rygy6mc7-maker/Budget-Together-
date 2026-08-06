import SwiftUI

// MARK: - What a custom category can be made of
//
// Two curated sets: colours and glyphs. Both are closed lists rather than free
// pickers, and the colour one especially is closed for a reason.
//
// DESIGN-NOTES §1 establishes that fill encodes identity in this app — a bar is
// Housing-coral *because* it is Housing — and §4b derives each light-scheme
// counterpart by rule and then measures it against both card and screen
// surfaces to clear WCAG AA. A free colour well would let someone pick a hue
// with no verified light counterpart, which breaks in exactly one direction:
// the light scheme, on somebody else's phone, where the author never looks.
//
// So the options here are only the pairs that already have measured contrast in
// DESIGN-NOTES §4b. Thirteen is plenty to name a category by, and every one of
// them is legible in both schemes by construction rather than by hope.

struct CategoryColor: Identifiable, Hashable {
    let name: String
    /// Dark-scheme fill.
    let hex: String
    /// Light-scheme counterpart at the same hue, measured ≥4.5:1 on both
    /// `Palette.card` and `Palette.screen`.
    let light: String

    var id: String { hex }
    var color: Color { Color(dark: hex, light: light) }
}

extension CategoryColor {
    /// Every pair in DESIGN-NOTES §4b's measured table. The contrast figures in
    /// the comments are against `card` / `screen` in the light scheme, which is
    /// the stricter of the two directions.
    static let all: [CategoryColor] = [
        CategoryColor(name: "Coral",     hex: "E86A4A", light: "BC3918"),  // 5.62 / 5.16
        CategoryColor(name: "Amber",     hex: "F5C15E", light: "98670A"),  // 4.91 / 4.50
        CategoryColor(name: "Gold",      hex: "E0C05B", light: "886D1A"),  // 4.94 / 4.54
        CategoryColor(name: "Green",     hex: "3FB984", light: "2B7E5A"),  // 4.96 / 4.55
        CategoryColor(name: "Teal",      hex: "5EEAD4", light: "107F6E"),  // 4.90 / 4.50
        CategoryColor(name: "Sky",       hex: "7FB2FF", light: "0048B6"),  // 8.07 / 7.41
        CategoryColor(name: "Blue",      hex: "5B8DEF", light: "1147B0"),  // 8.23 / 7.55
        CategoryColor(name: "Violet",    hex: "C69BFF", light: "390085"),  // 13.88 / 12.74
        CategoryColor(name: "Rose",      hex: "D45C87", light: "A82C59"),  // 6.63 / 6.08
        CategoryColor(name: "Blossom",   hex: "F6A5C8", light: "790C3B"),  // 10.89 / 9.99
        CategoryColor(name: "Red",       hex: "F2555A", light: "D51017"),  // 5.36 / 4.92
        CategoryColor(name: "Clay",      hex: "E0846A", light: "BB4827"),  // 5.16 / 4.74
        CategoryColor(name: "Slate",     hex: "8892B0", light: "626E93"),  // 5.03 / 4.62
    ]

    static func named(_ hex: String) -> CategoryColor {
        all.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame } ?? all[0]
    }

    /// The colour least used by the current set, so a new category doesn't
    /// arrive wearing the same coral as Housing when eleven others are free.
    static func leastUsed(among existing: [Bucket]) -> CategoryColor {
        let taken = existing.reduce(into: [String: Int]()) { counts, bucket in
            counts[bucket.hex.uppercased(), default: 0] += 1
        }
        return all.min { (taken[$0.hex.uppercased()] ?? 0) < (taken[$1.hex.uppercased()] ?? 0) }
            ?? all[0]
    }
}

// MARK: - Glyphs

/// SF Symbols worth offering, grouped so the picker can be scanned rather than
/// scrolled. Every one of these ships with iOS 17 and earlier, so nothing here
/// renders as a blank square on a device the user hasn't updated.
struct SymbolGroup: Identifiable {
    let name: String
    let symbols: [String]
    var id: String { name }
}

extension SymbolGroup {
    static let all: [SymbolGroup] = [
        SymbolGroup(name: "Home", symbols: [
            "house.fill", "bed.double.fill", "sofa.fill", "lightbulb.fill",
            "drop.fill", "flame.fill", "wrench.and.screwdriver.fill", "shippingbox.fill",
        ]),
        SymbolGroup(name: "Food", symbols: [
            "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
            "carrot.fill", "birthday.cake.fill", "wineglass.fill", "mug.fill", "basket.fill",
        ]),
        SymbolGroup(name: "Getting about", symbols: [
            "car.fill", "bus.fill", "tram.fill", "bicycle", "airplane",
            "fuelpump.fill", "parkingsign", "figure.walk",
        ]),
        SymbolGroup(name: "Life", symbols: [
            "heart.fill", "cross.case.fill", "pills.fill", "figure.run",
            "pawprint.fill", "graduationcap.fill", "book.fill", "stethoscope",
        ]),
        SymbolGroup(name: "Things", symbols: [
            "bag.fill", "cart.fill", "tshirt.fill", "gift.fill",
            "sparkles", "scissors", "hammer.fill", "leaf.fill",
        ]),
        SymbolGroup(name: "Fun", symbols: [
            "party.popper.fill", "gamecontroller.fill", "music.note", "film.fill",
            "ticket.fill", "beach.umbrella.fill", "camera.fill", "guitars.fill",
        ]),
        SymbolGroup(name: "Money", symbols: [
            "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "repeat",
            "briefcase.fill", "building.columns.fill", "arrow.uturn.backward", "percent",
        ]),
        SymbolGroup(name: "People", symbols: [
            "person.2.fill", "figure.2.and.child.holdinghands", "phone.fill",
            "envelope.fill", "globe", "hands.clap.fill", "star.fill", "questionmark.circle.fill",
        ]),
    ]

    static let flattened: [String] = all.flatMap(\.symbols)
}
