import SwiftUI

// MARK: - Running on iOS 16
//
// The app is built against a recent SDK but deploys back to iOS 16.6, which
// means a handful of things it reaches for don't exist on the oldest phones it
// runs on. Rather than sprinkle `if #available` through view bodies — where it
// reads as a design decision and quietly changes view identity — the two that
// come up repeatedly live here, named for what the call site wants.
//
// Both wrap an API pair where the older member is annotated
// `deprecated: 100000.0`, Apple's marker for "superseded but not yet
// deprecated in any shipping OS". That's deliberate: it means the fallback
// compiles without a warning, so these shims don't trade an error for noise.

extension View {
    /// `onChange(of:)` with a value in the closure.
    ///
    /// iOS 17 replaced the one-parameter closure with a two-parameter one
    /// carrying the old value as well. Every call site in this app wants only
    /// the new value — nothing here compares against what a thing used to be —
    /// so this offers exactly that and picks whichever form the OS has.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V,
                                     perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value) { _, new in action(new) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

extension Text {
    /// Colours a `Text` and hands back a `Text`.
    ///
    /// The distinction matters in exactly one place and is easy to miss:
    /// `.foregroundStyle` used as a view modifier has been available since iOS
    /// 15 and is fine anywhere in a view body. The overload that returns `Text`
    /// — the one a `TextField`'s `prompt:` needs, because that parameter takes
    /// a `Text` and not a view — arrived in iOS 17. Every placeholder in the
    /// app hits the second one.
    func tinted(_ color: Color) -> Text {
        if #available(iOS 17, *) {
            return foregroundStyle(color)
        }
        return foregroundColor(color)
    }
}
