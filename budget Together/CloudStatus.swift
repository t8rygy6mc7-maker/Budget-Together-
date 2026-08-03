import CloudKit
import SwiftUI

// MARK: - What iCloud is actually doing
//
// Mirroring can be switched on in the build, the entitlement can be correct, the
// container can exist — and nothing whatsoever can be syncing, because nobody is
// signed in to iCloud on this phone. Core Data doesn't treat that as an error,
// and it shouldn't: the app carries on writing to a local ledger and every
// screen looks exactly the same.
//
// Which is the problem. "Your budget is being backed up and shared with the
// household" and "your budget exists on precisely one phone and will die with
// it" are very different promises, and an app that can't tell the user which one
// it's currently keeping is asking to be trusted on faith.

enum CloudStatus: Equatable {
    /// Still asking. The account check is a round trip to iCloud.
    case checking
    /// This build doesn't mirror at all.
    case off
    /// Mirroring is running against a signed-in account.
    case on
    /// Configured, but no iCloud account on the device. Nothing syncs.
    case noAccount
    /// An account exists but iCloud is off-limits — Screen Time, MDM, a managed
    /// device.
    case restricted
    /// iCloud didn't answer. Usually offline, sometimes Apple having a bad day.
    case unreachable
    /// The stores wouldn't open and the app fell back to a local ledger.
    case failed(String)

    var title: String {
        switch self {
        case .checking:   "Checking iCloud…"
        case .off:        "Syncing is off"
        case .on:         "Syncing with iCloud"
        case .noAccount:  "Not signed in to iCloud"
        case .restricted: "iCloud isn't available on this device"
        case .unreachable:"Can't reach iCloud"
        case .failed:     "Syncing isn't running"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            "Asking iCloud whether it can take this budget."
        case .off:
            "Everything stays on this phone. Nothing is sent anywhere."
        case .on:
            "Your budget is mirrored to your iCloud account, so it survives this "
          + "phone and reaches your other devices."
        case .noAccount:
            "Everything still works and stays on this phone — but none of it is "
          + "backed up, and it won't reach any other device. Sign in to iCloud in "
          + "Settings to turn syncing on."
        case .restricted:
            "Something on this device blocks apps from using iCloud. Your budget "
          + "is being kept locally instead."
        case .unreachable:
            "No answer from iCloud, usually because the phone is offline. Your "
          + "budget is safe on this device and will catch up later."
        case let .failed(why):
            "Your budget is being kept on this phone instead. \(why)"
        }
    }

    var symbol: String {
        switch self {
        // Not `arrow.trianglehead.…`, which is SF Symbols 6 and draws nothing
        // at all on iOS 16 — a missing glyph raises no error and fails only on
        // the screen of whoever has the oldest phone.
        case .checking:                    "arrow.triangle.2.circlepath"
        case .off:                         "iphone.gen3"
        case .on:                          "checkmark.icloud.fill"
        case .noAccount, .restricted:      "person.crop.circle.badge.exclamationmark"
        case .unreachable:                 "icloud.slash"
        case .failed:                      "exclamationmark.icloud.fill"
        }
    }

    /// Red is reserved for the states where the user would otherwise believe
    /// their budget is safe when it isn't. Being offline for a minute is not
    /// one of those; having no iCloud account at all very much is.
    var tint: Color {
        switch self {
        case .on:                       Palette.green
        case .checking, .off:           Palette.teal
        case .unreachable:              Palette.sub
        case .noAccount, .restricted,
             .failed:                   Palette.over
        }
    }

    /// Whether the household's data is leaving this device. Drives the copy on
    /// the data screen, which otherwise promises local-only storage in an app
    /// that may well be mirroring to iCloud.
    var isLeavingTheDevice: Bool { self == .on }

    /// Asks iCloud whether there's an account behind the mirroring.
    ///
    /// Kept here rather than in the view so the answer is a value, not a side
    /// effect of something being on screen.
    static func account(in containerID: String) async -> CloudStatus {
        do {
            switch try await CKContainer(identifier: containerID).accountStatus() {
            case .available:              return .on
            case .noAccount:              return .noAccount
            case .restricted:             return .restricted
            case .couldNotDetermine:      return .unreachable
            case .temporarilyUnavailable: return .unreachable
            @unknown default:             return .unreachable
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
