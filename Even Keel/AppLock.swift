import Combine
import LocalAuthentication
import SwiftUI

// MARK: - App lock
//
// Everything this app stores is already encrypted on disk — but with a key that
// unlocks when the *phone* does (see `BudgetStore.fileProtection`). That covers
// a phone that's been taken. It does nothing at all about a phone that's been
// handed over, and handing a phone over is the ordinary thing: to show a photo,
// to let a child play something, to pass it across a table.
//
// That gap matters more here than in most apps, because this one has private
// entries. Marking an entry private keeps it out of the shared CloudKit store,
// so it never reaches the other person's device (see `BudgetStore.assignStore`)
// — which is a real guarantee against their *phone*, and was no guarantee at
// all against them picking up *this* one and opening the app. A feature that
// exists to hide a row from somebody should not be defeated by that somebody
// having thirty seconds alone with an unlocked phone.
//
// So: an optional Face ID / passcode gate in front of the whole app.
//
// What this is not, said plainly here so that nobody later mistakes it for
// something stronger: it is a gate on the user interface, not a second layer of
// encryption. The bytes on disk are exactly as readable as they were before it
// existed. It stops a person holding an unlocked phone. It does not stop
// someone who can run code as this app, and it does not stop an unencrypted
// device backup being restored onto a computer. Both of those were true before
// and remain true; claiming otherwise on the privacy screen would be the kind
// of promise this app has been careful not to make.
//
// Off by default. Most people budgeting have nobody to hide from, and a lock
// nobody asked for in front of an app opened six times a day is a tax rather
// than a feature.
//
// Siri is deliberately unaffected. `LogSpendIntent` and `CheckBudgetIntent`
// both run with `openAppWhenRun = false`, so they write and read in the
// background without this view tree ever existing — logging a spend by voice
// keeps working on a locked app, which is the whole point of it being available
// by voice. The gate is on looking, not on writing.

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    /// How long the app can be away before the gate closes behind it.
    ///
    /// Zero is the strict reading and the wrong one. Stepping out to a banking
    /// app to check what something actually cost, and coming straight back, is
    /// the single most common interruption to logging an entry — and a scan
    /// every time teaches people to turn the lock off, which protects nobody. A
    /// minute covers that round trip comfortably and is far shorter than the
    /// case this defends against, which is a phone left on a table.
    static let grace: TimeInterval = 60

    private static let enabledKey = "appLockEnabled"

    /// Whether the user has asked for the lock at all.
    @Published private(set) var isEnabled: Bool

    /// Whether the gate is closed right now. Always false when disabled.
    @Published private(set) var isLocked: Bool

    /// Why the last attempt didn't get through, when that's worth saying out
    /// loud. `nil` after a cancel — someone who backed out of the prompt knows
    /// what they did and doesn't need telling.
    @Published private(set) var failure: String?

    /// Whether a system prompt is in flight, so a second tap can't stack a
    /// second prompt on top of the first.
    @Published private(set) var isAuthenticating = false

    private let defaults: UserDefaults

    /// When the app was last backgrounded, or `nil` if it hasn't been since the
    /// gate last opened.
    private var leftAt: Date?

    /// Whether the app has genuinely been in the background since it was last
    /// frontmost. See `didBecomeActive` for why this can't be inferred from the
    /// scene phase alone.
    private var wasBackgrounded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        // A cold launch starts closed. Seeding this `false` and closing the gate
        // a moment later would render one frame of the real UI first — and one
        // frame is both a glimpse of somebody's finances and, on a launch that
        // comes from the app switcher, exactly what iOS photographs.
        isLocked = enabled
    }

    // MARK: The gate

    /// Puts the system prompt up, and opens the gate if it's satisfied.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch await Self.evaluate(reason: "Unlock your budget.") {
        case .success:
            failure = nil
            leftAt = nil
            isLocked = false
        case .unavailable:
            // There is nothing on this device to authenticate against. Staying
            // shut would put the ledger behind a door with no key on the far
            // side, so the gate opens — and the setting turns itself off rather
            // than sitting there claiming a protection the device can't give.
            disable()
            failure = Self.noPasscodeMessage
        case .failed(let message):
            failure = message
        case .cancelled:
            failure = nil
        }
    }

    // MARK: Scene phase

    /// Called when the app leaves the foreground for real.
    ///
    /// Driven by `.background` rather than `.inactive`, and the distinction is
    /// load-bearing: presenting the Face ID prompt *makes the scene inactive*.
    /// Starting the clock there would mean every unlock attempt began by
    /// recording the app as having left. Pulling Control Center down and
    /// letting it go is the same shape, and equally not a reason to re-lock.
    func didEnterBackground() {
        guard isEnabled else { return }
        wasBackgrounded = true
        if !isLocked { leftAt = Date() }
    }

    /// Called when the app comes back to the foreground.
    func didBecomeActive() {
        guard isEnabled, wasBackgrounded else { return }
        wasBackgrounded = false

        if let leftAt, Date().timeIntervalSince(leftAt) >= Self.grace {
            isLocked = true
            failure = nil
        }
        leftAt = nil

        // Coming back to a closed gate should raise the prompt by itself rather
        // than making someone tap a button to be asked. Guarded on
        // `wasBackgrounded` above, because the prompt's own arrival takes the
        // scene inactive and its dismissal brings it back active — without that
        // guard, every prompt would end by presenting another one.
        if isLocked { Task { await unlock() } }
    }

    // MARK: The setting

    /// Turns the lock on, but only once this device has proved it can open it
    /// again.
    ///
    /// The prompt here is not ceremony. A switch that locks the app without
    /// first checking that anybody *can* authenticate is a switch that strands
    /// someone outside their own ledger, and the moment they'd discover it is
    /// the next cold launch — which is the worst possible moment.
    @discardableResult
    func enable() async -> Bool {
        guard !isEnabled, !isAuthenticating else { return isEnabled }
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch await Self.evaluate(reason: "Confirm it's you, before locking this budget.") {
        case .success:
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            failure = nil
            return true
        case .unavailable:
            failure = Self.noPasscodeMessage
            return false
        case .failed(let message):
            failure = message
            return false
        case .cancelled:
            failure = nil
            return false
        }
    }

    /// Turns it off. No prompt: the app is open and being looked at, which means
    /// the gate has already been satisfied to get this far.
    func disable() {
        isEnabled = false
        isLocked = false
        leftAt = nil
        wasBackgrounded = false
        failure = nil
        defaults.set(false, forKey: Self.enabledKey)
    }

    /// Clears a message once it's been read, so it doesn't outlive the attempt
    /// that produced it.
    func clearFailure() { failure = nil }

    // MARK: LocalAuthentication

    /// What this device calls the thing it's about to ask for.
    ///
    /// Worth asking rather than hardcoding "Face ID": on an iPhone SE that
    /// names a sensor the phone doesn't have, which reads as the app being
    /// broken. `biometryType` is only populated once a policy has been
    /// evaluated against the context, hence the discarded probe — a fresh
    /// `LAContext` reports `.none` for everything until asked.
    ///
    /// Worked out once per launch rather than on demand, and that is not
    /// premature: `canEvaluatePolicy` is a synchronous XPC round trip to
    /// `coreauthd`, and this is read from inside a SwiftUI `body`. As a
    /// computed property it fired on every re-render — a dozen round trips in a
    /// quarter of a second just to draw one settings row, all of them on the
    /// main thread. What it answers can only change when someone enrols or
    /// removes a face in iOS Settings, which they cannot do without leaving the
    /// app, so a value fixed at launch is never meaningfully stale.
    static let biometryName: String = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "your passcode"
        }
    }()

    private static let noPasscodeMessage =
        "This iPhone has no passcode, so there's nothing to unlock with. "
      + "Set one in iOS Settings and this becomes available."

    private enum Outcome {
        case success
        /// Backed out of the prompt. Not a failure anybody needs told about.
        case cancelled
        /// This device cannot authenticate anyone at all.
        case unavailable
        case failed(String)
    }

    /// A fresh `LAContext` every time, deliberately. A context caches its last
    /// successful evaluation for a few minutes, so a reused one would wave the
    /// second unlock of a session straight through without asking anybody
    /// anything — which is the one failure mode a lock cannot have.
    private static func evaluate(reason: String) async -> Outcome {
        let context = LAContext()

        // `.deviceOwnerAuthentication` rather than the biometrics-only policy,
        // which is the one most code reaches for first. That policy locks out
        // permanently after five failed scans with nowhere to go, so a phone
        // whose owner is wearing sunglasses, or a mask, or is in the dark, is a
        // door that simply doesn't open. This one offers biometry first and
        // falls back to the passcode by itself.
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else {
            return outcome(for: probe, fallback: "This iPhone can't verify it's you right now.")
        }

        do {
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                          localizedReason: reason)
            return passed ? .success : .failed("That didn't work. Try again.")
        } catch {
            return outcome(for: error as NSError, fallback: "That didn't work. Try again.")
        }
    }

    private static func outcome(for error: NSError?, fallback: String) -> Outcome {
        guard let error, error.domain == LAErrorDomain,
              let code = LAError.Code(rawValue: error.code) else { return .failed(fallback) }

        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .userFallback:
            // "Enter Passcode". The system handles that within the same
            // evaluation, so this only arrives if the keypad was then abandoned.
            return .cancelled
        case .passcodeNotSet:
            // The only genuine "this device can't authenticate anybody" case for
            // this policy, which needs a passcode and nothing more. Biometry
            // being absent, unenrolled or locked out just sends it to the keypad.
            return .unavailable
        default:
            return .failed(fallback)
        }
    }
}

// MARK: - The screen in front of the gate

/// What the app is while it's locked.
///
/// Built to read as the app resting rather than the app refusing. There is no
/// budget name on it, no member, no figure and no category — a lock screen that
/// says "Rent is over budget" above the unlock button has given away the thing
/// it was put there to keep, and the name of a household is enough on its own in
/// a room where the point is that somebody isn't meant to be looking.
struct LockScreen: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Palette.screen.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "lock.fill")
                    .appFont(30, weight: .semibold)
                    .foregroundStyle(Palette.tealInk)
                    .frame(width: 74, height: 74)
                    .background(Palette.tealGradient,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)

                Text("Locked")
                    .appFont(19, weight: .bold)
                    .padding(.top, 18)

                Text("This budget opens with \(AppLock.biometryName).")
                    .appFont(12.5)
                    .foregroundStyle(Palette.sub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                if let failure = lock.failure {
                    Text(failure)
                        .appFont(11.5)
                        .foregroundStyle(Palette.over)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 30)
                }

                Button {
                    Task { await lock.unlock() }
                } label: {
                    Text("Unlock")
                        .appFont(14, weight: .bold)
                        .foregroundStyle(Palette.tealInk)
                        .padding(.horizontal, 30).padding(.vertical, 13)
                        .background(Palette.tealGradient,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(lock.isAuthenticating)
                .opacity(lock.isAuthenticating ? 0.5 : 1)
                .padding(.top, 24)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        // Raises the prompt on arrival, so the ordinary path is open-and-glance
        // rather than open-tap-glance. A return from the background is handled
        // separately by `didBecomeActive` — this view is already on screen by
        // then, and `task` doesn't run twice for it.
        .task { await lock.unlock() }
    }
}

#Preview("Locked") {
    LockScreen().preferredColorScheme(.dark)
}

#Preview("Locked — light") {
    LockScreen().preferredColorScheme(.light)
}
