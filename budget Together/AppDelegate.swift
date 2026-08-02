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
// This is also where accepting a household invite will live when sharing lands
// (`userDidAcceptCloudKitShareWith`), which is why it's a file of its own
// rather than a few lines hidden in the app entry point.

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Nothing to ask for and nothing to show. These pushes are silent, so
        // they need no alert authorisation and raise no permission prompt —
        // which is why this can run unconditionally at launch. Skipped when
        // mirroring isn't running, since there'd be nothing to be told about.
        if BudgetStore.shared.isCloudSyncActive {
            application.registerForRemoteNotifications()
        }
        return true
    }
}
