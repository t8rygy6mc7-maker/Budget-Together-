import CloudKit
import CoreData
import SwiftUI
import OSLog

// MARK: - Sharing a budget with another person
//
// Everything up to this point syncs a budget between *your own* devices: the
// private CloudKit database is mirrored, your iPhone and your iPad see the same
// ledger, and that's the end of it. Adding "Sam" in the People sheet wrote a
// name and an avatar colour — a label to file entries under, not an account.
// Two people each typing the other's name into their own copy got two budgets
// that looked shared and were not, which is the worst version of this feature
// because nothing on screen says so.
//
// What makes it real is a `CKShare` on the household record. The owner mints
// one, sends the link however they like, and the person who opens it gets the
// household in their *shared* database — the same rows, not a copy. Their
// entries write back through the shared store (`assign(_:toStoreOf:)` already
// routes them there), so a spend logged on their phone lands on everyone's,
// including their own iPad.
//
// Two things deliberately don't travel:
//
//   * **Private entries.** They live in a local-only store with no household
//     relationship at all (see `assignStore`), so there is nothing for the
//     share to reach. That guarantee predates this file and survives it.
//   * **Which member you are.** `localMemberID` is per-device by design. What
//     *is* shared is which iCloud account has claimed a seat, so a joiner
//     answers "which one of these is you?" once rather than on every device.

extension BudgetStore {

    static let sharingLog = Logger(subsystem: "com.evenkeel.app", category: "sharing")

    /// One person on a shared budget, as CloudKit sees them.
    ///
    /// A value type rather than the `CKShare.Participant` it came from, so the
    /// People sheet doesn't grow an import of CloudKit and can be previewed
    /// without one.
    struct ShareParticipant: Identifiable, Hashable {
        /// The participant's user record name — the same string that gets
        /// stamped on a claimed seat, which is what lets the two be matched.
        let id: String
        /// Their name as iCloud knows it, when they've accepted and it's
        /// available. Empty for an invite nobody has opened yet: CloudKit
        /// deliberately doesn't hand over a name for someone who hasn't agreed
        /// to be identified.
        let name: String
        let isOwner: Bool
        let hasAccepted: Bool
        /// Whether they can write, as opposed to only read.
        let canEdit: Bool
    }

    // MARK: Reading the current state

    /// The share on a household, if it has one. Cheap and synchronous — Core
    /// Data keeps the share record alongside the objects it covers.
    func existingShare(forHouseholdID id: String) -> CKShare? {
        guard isCloudSyncActive, let house = householdObject(id: id) else { return nil }
        return try? container.fetchShares(matching: [house.objectID])[house.objectID]
    }

    func isShared(householdID: String) -> Bool { existingShare(forHouseholdID: householdID) != nil }

    /// Everyone on the share, owner first. Empty for a budget nobody has been
    /// invited into, which is the normal state and not an error.
    func participants(forHouseholdID id: String) -> [ShareParticipant] {
        guard let share = existingShare(forHouseholdID: id) else { return [] }
        return share.participants
            .map { participant in
                let identity = participant.userIdentity
                let components = identity.nameComponents
                return ShareParticipant(
                    id: identity.userRecordID?.recordName ?? UUID().uuidString,
                    name: components.map {
                        PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                    } ?? "",
                    isOwner: participant.role == .owner,
                    hasAccepted: participant.acceptanceStatus == .accepted,
                    canEdit: participant.permission == .readWrite
                )
            }
            .sorted { $0.isOwner && !$1.isOwner }
    }

    /// Whether this device is the one that can invite people — i.e. it owns the
    /// budget rather than having been invited into it. Participants can't
    /// reshare, and offering them a button that fails would be worse than not
    /// offering it.
    func canInvite(toHouseholdID id: String) -> Bool {
        guard isCloudSyncActive, let house = householdObject(id: id) else { return false }
        guard let share = try? container.fetchShares(matching: [house.objectID])[house.objectID]
        else { return true }   // not shared yet, and it's in our private store
        return share.currentUserParticipant?.role == .owner
    }

    // MARK: Making a share

    /// Mints the share for a household, or hands back the one it already has.
    ///
    /// The title is set and persisted before the sheet is ever presented,
    /// because it's what the recipient sees in Messages — an invite that says
    /// "Untitled" is one people don't open.
    func share(householdID id: String) async throws -> (share: CKShare, container: CKContainer) {
        guard isCloudSyncActive else { throw SharingError.syncNotRunning }
        guard let house = householdObject(id: id) else { throw SharingError.noSuchBudget }

        let (_, share, ckContainer) = try await container.share([house], to: nil)
        let name = house.value(forKey: "name") as? String ?? "Together"

        guard share[CKShare.SystemFieldKey.title] as? String != name,
              let privateStore else { return (share, ckContainer) }

        share[CKShare.SystemFieldKey.title] = name
        // A share that reached the server but couldn't be renamed is still a
        // working share. Losing the invite over the label on it would be a bad
        // trade, so this failure is logged and swallowed.
        do {
            let renamed = try await container.persistUpdatedShare(share, in: privateStore)
            return (renamed, ckContainer)
        } catch {
            Self.sharingLog.error("Couldn't set the share title: \(error.localizedDescription, privacy: .public)")
            return (share, ckContainer)
        }
    }

    /// Ends the share. Everyone who joined loses the budget from their phone;
    /// the owner keeps every row of it.
    ///
    /// Deleting the `CKShare` record is what un-shares a household. Pointedly
    /// *not* `purgeObjectsAndRecordsInZone`, which is the call for a
    /// participant leaving — run by the owner it deletes the zone, and the
    /// budget goes with it. The two operations read as synonyms and differ by
    /// everything the user owns.
    func stopSharing(householdID id: String) async throws {
        guard let share = existingShare(forHouseholdID: id) else { return }
        let ckContainer = CKContainer(identifier: Self.containerIdentifier)
        try await ckContainer.privateCloudDatabase.deleteRecord(withID: share.recordID)
    }

    /// Leaves somebody else's budget. The opposite end of `stopSharing`, and
    /// the one call where purging the zone is right: the rows being dropped are
    /// a mirror of the owner's, and they keep theirs.
    func leaveShare(householdID id: String) async throws {
        guard let share = existingShare(forHouseholdID: id), let sharedStore else { return }
        try await container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID,
                                                         in: sharedStore)
        if selectedHouseholdID == id { selectedHouseholdID = nil }
        localMemberID = nil
    }

    // MARK: Accepting one

    /// Takes an invite the user has just opened and pulls the budget into the
    /// shared store.
    ///
    /// Returns the id of the household that arrived, so the caller can open it
    /// — which is what accepting an invite means, and is not something
    /// `defaultHousehold()` would work out on its own for someone who already
    /// had a budget of their own.
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> String? {
        guard let sharedStore else { throw SharingError.syncNotRunning }
        try await container.acceptShareInvitations(from: [metadata], into: sharedStore)

        // The accept and the mirror-down are separate: CloudKit has taken the
        // invite by the time the call returns, but the rows arrive with the
        // next sync. Poll briefly rather than reporting a budget that isn't
        // there yet — this is the one moment the user is definitely watching.
        let zone = metadata.share.recordID.zoneID.zoneName
        for _ in 0..<20 {
            viewContext.refreshAllObjects()
            if let id = joinedHouseholdID(inZone: zone) { return id }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return joinedHouseholdID(inZone: zone)
    }

    /// The household that arrived in the zone this invite named.
    ///
    /// Matched on the zone rather than taken as "the newest shared one",
    /// because somebody who is already in one shared budget and joins a second
    /// would otherwise be handed whichever mirrored down last — which on a
    /// slow connection is a coin toss between the budget they just accepted and
    /// one they joined last week.
    private func joinedHouseholdID(inZone zone: String) -> String? {
        guard let sharedStore else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        request.affectedStores = [sharedStore]
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let rows = (try? viewContext.fetch(request)) ?? []
        let inZone = rows.first {
            container.record(for: $0.objectID)?.recordID.zoneID.zoneName == zone
        }
        // The record isn't always cached the instant the object appears. One
        // budget in the shared store makes the fallback exact anyway, and it
        // beats reporting that nothing arrived.
        return (inZone ?? rows.first)?.value(forKey: "id") as? String
    }

    enum SharingError: LocalizedError {
        case syncNotRunning
        case noSuchBudget

        var errorDescription: String? {
            switch self {
            case .syncNotRunning:
                "This budget isn't syncing with iCloud, so there's nothing to share yet."
            case .noSuchBudget:
                "That budget isn't on this phone any more."
            }
        }
    }
}

// MARK: - The system share sheet

/// Thin wrapper over `UICloudSharingController`, which is the only supported
/// way to put a `CKShare` in front of somebody.
///
/// The share is minted *before* this is presented rather than in a
/// `preparationHandler`, so a failure to create it surfaces as an error message
/// in the app's own voice instead of a spinner inside a system sheet that then
/// dismisses itself with nothing to show for it.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String
    /// Called when the user removes the last participant, or otherwise ends the
    /// share from inside the system UI.
    var onStopSharing: () -> Void = {}
    /// Called after the sheet saves, so the People sheet can re-read the
    /// participant list rather than showing the state from before the invite.
    var onSaved: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        // Two deliberate restrictions.
        //
        // `.allowPrivate` without `.allowPublic`: a public share is "anyone
        // with this link", and a link to a household's finances is one
        // forward away from being a link anybody has. Every recipient here has
        // to be an iCloud account the owner named.
        //
        // `.allowReadWrite` without `.allowReadOnly`: someone who can't log
        // anything is a spectator on a budget, which isn't what this app
        // offers anyone.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudSharingSheet

        init(_ parent: CloudSharingSheet) { self.parent = parent }

        func itemTitle(for controller: UICloudSharingController) -> String? { parent.title }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            parent.onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            parent.onStopSharing()
        }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            BudgetStore.sharingLog.error("""
                The share sheet couldn't save: \(error.localizedDescription, privacy: .public)
                """)
        }
    }
}
