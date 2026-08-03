import SwiftUI

// MARK: - App delegate
//
// SwiftUI's `App` has no hook for the one thing CloudKit needs from UIKit:
// registering for the silent pushes that say a sibling device wrote something.
//
// Registering is the difference between sync feeling immediate and feeling
// eventual. `NSPersistentCloudKitContainer` pulls changes when the app comes
// forward regardless, so without this the ledger is still correct — just late.
// A spend logged on the iPad wouldn't reach the phone until the next launch,
// which on a shared budget reads as the app having lost it.
//
// It's also where the scene delegate gets named, which is how invites to a
// shared budget reach the app (`userDidAcceptCloudKitShareWith` — see
// SceneDelegate).

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        // A maintenance launch, not a real one: build the CloudKit schema from
        // the model and stop there. Runs before anything else so the app isn't
        // half set up while it works, and never in a shipping build — see
        // BudgetStore.initializeCloudKitSchema for what it's for and how to
        // trigger it.
        if BudgetStore.wantsSchemaInitialization {
            BudgetStore.initializeCloudKitSchema()
            return true
        }
#endif

        // Nothing to ask for and nothing to show. These pushes are silent, so
        // they need no alert authorisation and raise no permission prompt —
        // which is why this can run unconditionally at launch. Skipped when
        // mirroring isn't running, since there'd be nothing to be told about.
        if BudgetStore.shared.isCloudSyncActive {
            application.registerForRemoteNotifications()
        }
        return true
    }

    /// SwiftUI builds the scene, but only a scene *delegate* is offered the
    /// CloudKit share metadata when someone opens an invite — and the only way
    /// to get one into a `WindowGroup` app is to name it here.
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
