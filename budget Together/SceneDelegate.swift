import CloudKit
import Combine
import SwiftUI

// MARK: - Taking an invite
//
// When somebody taps a share link, iOS hands the app a `CKShare.Metadata` and
// expects it to be accepted. There is no SwiftUI hook for this — it arrives on
// the scene delegate, whether the app was already running or was launched by
// the tap — so the app grows a scene delegate for exactly this one message.
//
// The metadata doesn't go straight to CloudKit from here. It goes in an inbox
// the app's model watches, because accepting is the easy half: the hard half is
// that the rows then have to arrive, the device has to be pointed at the budget
// that just landed, and somebody has to say which seat is theirs. That sequence
// belongs with the rest of the app's state, not in a delegate callback.

/// Where an invite waits between iOS handing it over and the app being ready to
/// deal with it.
///
/// A shared box rather than a callback because the two ends have unrelated
/// lifetimes: a cold launch delivers the invite before `RootView` has been
/// built, and a warm one delivers it to a view that's been on screen for days.
@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()

    /// Set by the scene delegate, cleared by whoever acts on it.
    @Published var pending: CKShare.Metadata?

    private init() {}

    func deliver(_ metadata: CKShare.Metadata) { pending = metadata }

    func take() -> CKShare.Metadata? {
        defer { pending = nil }
        return pending
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// A tap that launched the app. `willConnectTo` is the only place a cold
    /// launch surfaces the invite; the method below never fires for it.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in ShareInbox.shared.deliver(metadata) }
    }

    /// A tap while the app was already running.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in ShareInbox.shared.deliver(metadata) }
    }
}
