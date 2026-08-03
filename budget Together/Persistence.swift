import CoreData
import CloudKit
import OSLog

// MARK: - Programmatic Core Data model
//
// The managed object model is built in code (no .xcdatamodeld package) so the
// whole data layer lives in plain Swift files. All attributes are optional and
// all relationships are optional, which is what CloudKit requires when the
// store is mirrored by NSPersistentCloudKitContainer.

enum CDModel {
    static let household = "CDHousehold"
    static let entry     = "CDEntry"
    static let cap       = "CDCap"
    static let member    = "CDMember"
    static let recurring = "CDRecurring"
    static let loan      = "CDLoan"
    static let challenge = "CDChallenge"
    static let reaction  = "CDReaction"
    static let monthFlag = "CDMonthFlag"
    static let category  = "CDCategory"

    static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let household = entity(named: CDModel.household)
        let entry     = entity(named: CDModel.entry)
        let cap       = entity(named: CDModel.cap)
        let member    = entity(named: CDModel.member)
        let recurring = entity(named: CDModel.recurring)
        let loan      = entity(named: CDModel.loan)
        let challenge = entity(named: CDModel.challenge)
        let reaction  = entity(named: CDModel.reaction)
        let monthFlag = entity(named: CDModel.monthFlag)
        let category  = entity(named: CDModel.category)

        household.properties = [
            attr("id",        .stringAttributeType),
            secret("name",    .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            // Sample households are created by "Look around first" and are
            // wiped wholesale when the user starts their own.
            attr("isSample",  .booleanAttributeType),
            // Whether an unspent remainder carries into next month.
            attr("rolloverEnabled", .booleanAttributeType),
        ]
        entry.properties = [
            attr("id",         .stringAttributeType),
            attr("date",       .stringAttributeType),   // "yyyy-MM-dd", matches Entry.date
            secret("place",    .stringAttributeType),
            attr("bucket",     .stringAttributeType),
            secret("amount",   .doubleAttributeType),
            attr("memberID",   .stringAttributeType),   // CDMember.id of whoever spent it
            attr("memberRole", .stringAttributeType),   // legacy two-person field, migrated on first load
            attr("kind",       .stringAttributeType),   // EntryKind; nil predates income and reads as expense
            secret("mood",     .stringAttributeType),   // Mood; nil means untagged, which is normal
            secret("note",     .stringAttributeType),   // free text; nil and "" are the same thing
            attr("belowTheLine", .booleanAttributeType), // one-off, kept out of the plan
            attr("isPrivate",  .booleanAttributeType),  // kept out of the shared store
            // Entries are found by this, not by the household relationship: a
            // private entry lives in a different store from the household, and
            // Core Data forbids relationships that span stores.
            attr("householdID", .stringAttributeType),
            attr("createdAt",  .dateAttributeType),
        ]
        // Keyed by entry id rather than a relationship, for the same reason
        // entries are: a reaction to a private entry must not need to reach
        // across stores to find it.
        reaction.properties = [
            attr("id",          .stringAttributeType),
            attr("entryID",     .stringAttributeType),
            attr("memberID",    .stringAttributeType),
            attr("kind",        .stringAttributeType),   // ReactionKind
            attr("householdID", .stringAttributeType),
            attr("createdAt",   .dateAttributeType),
        ]
        monthFlag.properties = [
            attr("month",     .stringAttributeType),     // "yyyy-MM"
            attr("isUnusual", .booleanAttributeType),
            secret("reason",  .stringAttributeType),
            attr("updatedAt", .dateAttributeType),
        ]
        // The spending and income categories, which are user data rather than a
        // fixed list. `id` is permanent once written — entries, caps, recurring
        // items and challenges all refer to a category by it.
        category.properties = [
            attr("id",         .stringAttributeType),
            secret("label",    .stringAttributeType),
            attr("symbol",     .stringAttributeType),    // SF Symbol name
            attr("hex",        .stringAttributeType),    // dark-scheme fill
            attr("lightHex",   .stringAttributeType),    // light-scheme counterpart
            attr("cadence",    .stringAttributeType),    // Cadence
            attr("kind",       .stringAttributeType),    // EntryKind
            attr("sortOrder",  .integer64AttributeType),
            attr("isHidden",   .booleanAttributeType),
            attr("isBuiltIn",  .booleanAttributeType),
            attr("createdAt",  .dateAttributeType),
        ]
        cap.properties = [
            attr("bucket",    .stringAttributeType),
            secret("amount",  .doubleAttributeType),
            attr("month",     .stringAttributeType),      // "yyyy-MM"; nil is the pre-history baseline
            attr("updatedAt", .dateAttributeType),        // used to dedupe conflicting caps
        ]
        member.properties = [
            attr("id",         .stringAttributeType),
            secret("name",     .stringAttributeType),
            attr("colorIndex", .integer64AttributeType),  // index into MemberStyle.all
            attr("createdAt",  .dateAttributeType),       // also the display order
            // Which iCloud account sits in this seat, once somebody has said
            // so. Opaque and container-scoped — it is not an email address and
            // can't be turned back into one. In the clear rather than
            // encrypted because the whole point of it is to be matched against
            // in a predicate. See `BudgetStore.claimMember`.
            attr("userRecordName", .stringAttributeType),
        ]
        recurring.properties = [
            attr("id",              .stringAttributeType),
            secret("place",         .stringAttributeType),
            attr("bucket",          .stringAttributeType),
            secret("amount",        .doubleAttributeType),
            attr("memberID",        .stringAttributeType),
            attr("kind",            .stringAttributeType),
            attr("dayOfMonth",      .integer64AttributeType),
            attr("isActive",        .booleanAttributeType),
            attr("lastPostedMonth", .stringAttributeType),  // "yyyy-MM"; posts once per month
            attr("createdAt",       .dateAttributeType),
        ]
        loan.properties = [
            attr("id",             .stringAttributeType),
            secret("name",         .stringAttributeType),
            secret("balance",      .doubleAttributeType),
            secret("rate",         .doubleAttributeType),    // annual %, 0 for interest-free
            secret("monthlyPayment", .doubleAttributeType),
            attr("createdAt",      .dateAttributeType),
        ]
        challenge.properties = [
            attr("id",        .stringAttributeType),
            secret("title",   .stringAttributeType),
            attr("kind",      .stringAttributeType),   // ChallengeKind
            attr("bucket",    .stringAttributeType),   // nil means all spending
            secret("target",  .doubleAttributeType),
            attr("startDate", .stringAttributeType),   // "yyyy-MM-dd", inclusive
            attr("endDate",   .stringAttributeType),
            attr("createdAt", .dateAttributeType),
        ]

        // household <->> entries
        let (hToE, eToH) = relationship(name: "entries", inverseName: "household",
                                        from: household, to: entry, toMany: true)
        // household <->> caps
        let (hToC, cToH) = relationship(name: "caps", inverseName: "household",
                                        from: household, to: cap, toMany: true)
        // household <->> members
        let (hToM, mToH) = relationship(name: "members", inverseName: "household",
                                        from: household, to: member, toMany: true)
        // household <->> recurring
        let (hToR, rToH) = relationship(name: "recurring", inverseName: "household",
                                        from: household, to: recurring, toMany: true)
        // household <->> loans
        let (hToL, lToH) = relationship(name: "loans", inverseName: "household",
                                        from: household, to: loan, toMany: true)
        // household <->> challenges
        let (hToCh, chToH) = relationship(name: "challenges", inverseName: "household",
                                          from: household, to: challenge, toMany: true)
        // household <->> reactions
        let (hToRe, reToH) = relationship(name: "reactions", inverseName: "household",
                                          from: household, to: reaction, toMany: true)
        // household <->> monthFlags
        let (hToF, fToH) = relationship(name: "monthFlags", inverseName: "household",
                                        from: household, to: monthFlag, toMany: true)
        // household <->> categories
        let (hToCat, catToH) = relationship(name: "categories", inverseName: "household",
                                            from: household, to: category, toMany: true)

        household.properties += [hToE, hToC, hToM, hToR, hToL, hToCh, hToRe, hToF, hToCat]
        entry.properties     += [eToH]
        cap.properties       += [cToH]
        member.properties    += [mToH]
        recurring.properties += [rToH]
        loan.properties      += [lToH]
        challenge.properties += [chToH]
        reaction.properties  += [reToH]
        monthFlag.properties += [fToH]
        category.properties  += [catToH]

        model.entities = [household, entry, cap, member, recurring,
                          loan, challenge, reaction, monthFlag, category]
        return model
    }

    private static func entity(named name: String) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        return e
    }

    private static func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        return a
    }

    /// An attribute that carries something *about the person* rather than
    /// something the app needs to look rows up by.
    ///
    /// `allowsCloudEncryption` puts the value in the CloudKit record's
    /// `encryptedValues` rather than its plain fields, which is what makes the
    /// end-to-end claim true rather than aspirational. It is inert today —
    /// `cloudSyncEnabled` is `false` and nothing is mirrored — but it is set
    /// now because it is free now and a migration later: once records exist in
    /// iCloud with a field in the clear, moving that field into the encrypted
    /// side means rewriting every record that was ever synced.
    ///
    /// Identifiers, dates, enum tags, flags, ordering and timestamps stay in
    /// the clear so they remain usable in predicates and sort descriptors. What
    /// gets encrypted is the part that would actually tell someone reading the
    /// records something about this household: what things cost, what they were
    /// called, where they happened, and how they felt about them.
    private static func secret(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let a = attr(name, type)
        a.allowsCloudEncryption = true
        return a
    }

    /// Builds a to-many (or to-one) relationship and its inverse, wires them together.
    private static func relationship(
        name: String, inverseName: String,
        from: NSEntityDescription, to: NSEntityDescription, toMany: Bool
    ) -> (NSRelationshipDescription, NSRelationshipDescription) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = to
        forward.minCount = 0
        forward.maxCount = toMany ? 0 : 1   // 0 == unbounded (to-many)
        forward.deleteRule = .cascadeDeleteRule
        forward.isOptional = true

        let inverse = NSRelationshipDescription()
        inverse.name = inverseName
        inverse.destinationEntity = from
        inverse.minCount = 0
        inverse.maxCount = 1
        inverse.deleteRule = .nullifyDeleteRule
        inverse.isOptional = true

        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        return (forward, inverse)
    }
}

// MARK: - Store

/// Owns the Core Data + CloudKit stack and exposes value-type snapshots to the
/// UI layer. `AppModel` is the only thing that talks to it.
@MainActor
final class BudgetStore {
    static let shared = BudgetStore()

    static let containerIdentifier = "iCloud.budget.budget-Together"

    /// Whether this build asks for CloudKit mirroring at all.
    static let cloudSyncEnabled = true

    /// Whether mirroring is actually running, as opposed to merely asked for.
    ///
    /// False when `cloudSyncEnabled` is off, and also when it's on but the
    /// CloudKit-backed stores wouldn't open and the app fell back to a local
    /// one. Everything that decides *where* an object lives reads this rather
    /// than the flag above, because putting an entry in a store that isn't
    /// mirrored on the belief that it is would be a silent data-loss bug.
    private(set) var isCloudSyncActive = false

    /// Why mirroring isn't running, when it was asked for and couldn't start.
    /// `nil` when there's nothing to report — either it's working or it was
    /// never switched on.
    private(set) var cloudLoadFailure: String?

    static let log = Logger(subsystem: "budget.budget-Together", category: "store")

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    /// Called (on the main actor) whenever another context/device changes data.
    var onChange: (() -> Void)?

    private var remoteChangeObserver: NSObjectProtocol?

    /// Which member this device is. Deliberately *not* in Core Data: it's a
    /// per-device fact, and mirroring it would make everyone "you" on every
    /// phone. `nil` for in-memory stores so previews never touch defaults.
    private let defaults: UserDefaults?
    private var localMemberIDInMemory: String?
    private static let localMemberKey = "localMemberID"

    var localMemberID: String? {
        get { defaults?.string(forKey: Self.localMemberKey) ?? localMemberIDInMemory }
        set {
            if let defaults { defaults.set(newValue, forKey: Self.localMemberKey) }
            else { localMemberIDInMemory = newValue }
        }
    }

    /// Which household this device is looking at. Per-device for the same
    /// reason `localMemberID` is: once you can be invited into someone else's
    /// budget, a phone can hold more than one, and which one is on screen is a
    /// fact about the phone rather than about the data.
    private var selectedHouseholdIDInMemory: String?
    private static let selectedHouseholdKey = "selectedHouseholdID"

    var selectedHouseholdID: String? {
        get { defaults?.string(forKey: Self.selectedHouseholdKey) ?? selectedHouseholdIDInMemory }
        set {
            if let defaults { defaults.set(newValue, forKey: Self.selectedHouseholdKey) }
            else { selectedHouseholdIDInMemory = newValue }
        }
    }

    /// Who CloudKit thinks this device is, cached from the last time it
    /// answered. Used to work out which seat in a shared budget belongs to the
    /// person holding the phone — see `claimMember`.
    private var userRecordNameInMemory: String?
    private static let userRecordKey = "cloudUserRecordName"

    private(set) var cloudUserRecordName: String? {
        get { defaults?.string(forKey: Self.userRecordKey) ?? userRecordNameInMemory }
        set {
            if let defaults { defaults.set(newValue, forKey: Self.userRecordKey) }
            else { userRecordNameInMemory = newValue }
        }
    }

    /// Asks CloudKit who this is. Cheap after the first call — CloudKit caches
    /// it too — but worth doing at launch rather than once ever, because
    /// signing out of iCloud and into another account changes the answer, and
    /// a stale one would hand this phone somebody else's seat.
    func refreshCloudUserRecordName() async {
        guard Self.cloudSyncEnabled else { return }
        let container = CKContainer(identifier: Self.containerIdentifier)
        guard let id = try? await container.userRecordID() else { return }
        cloudUserRecordName = id.recordName
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        defaults = inMemory ? nil : .standard
        let model = CDModel.make()
        container = NSPersistentCloudKitContainer(name: "BudgetTogether", managedObjectModel: model)
        openStores(inMemory: inMemory, cloud: Self.cloudSyncEnabled && !inMemory)

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.transactionAuthor = "app"

        if !inMemory {
            observeRemoteChanges()
        }
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    // MARK: Setup

    /// Opens the stores, dropping back to a local-only stack if the
    /// CloudKit-backed ones won't open.
    ///
    /// Three things mirroring depends on live outside this code — the
    /// entitlement, a provisioned container, and who signed the build — and any
    /// of them can be absent on a given machine. Failing closed would leave the
    /// app with no store at all: no ledger, nowhere to write, every screen
    /// blank. A phone that still records spending on its own is a much better
    /// answer to "iCloud isn't set up here" than a phone that records nothing.
    private func openStores(inMemory: Bool, cloud: Bool) {
        configureDescriptions(inMemory: inMemory, cloud: cloud)

        var failure: Error?
        // Synchronous: `shouldAddStoreAsynchronously` is left at its default of
        // false, so every description has been attempted by the time this
        // returns and `failure` can be read straight after.
        container.loadPersistentStores { [weak self] desc, error in
            if let error {
                failure = error
                return
            }
            self?.captureStore(for: desc)
            // `AppModel` performs its first reload while the persistent store
            // may still be opening. Tell it to retry once the store is ready so
            // a returning household is not left at the pairing screen.
            self?.onChange?()
        }

        guard let failure else {
            isCloudSyncActive = cloud
            if cloud {
                cloudLoadFailure = nil
                Self.log.notice("Store opened with iCloud mirroring active.")
            } else {
                Self.log.notice("Store opened local-only.")
            }
            return
        }
        guard cloud else {
            // Local failed too. Nothing left to fall back to.
            Self.log.fault("Local store failed to open: \(failure.localizedDescription, privacy: .public)")
            assertionFailure("Failed to load store: \(failure)")
            return
        }

        // Said out loud, at fault level, because the earlier version of this
        // fallback was silent — and a silent fallback is indistinguishable from
        // working sync from anywhere outside this function. Days can be lost to
        // that: the app looks healthy, the ledger is correct, and nothing ever
        // reaches iCloud.
        cloudLoadFailure = failure.localizedDescription
        // The full error, not `localizedDescription` — Core Data's localised
        // string is "A Core Data error occurred", every time, for everything.
        // What identifies the problem is the userInfo, which is where the
        // validation messages actually live.
        Self.log.fault("""
            iCloud stores failed to open, falling back to a local-only ledger: \
            \(String(describing: failure), privacy: .public)
            """)

        // Clear out whatever did open before retrying, or the coordinator would
        // be left holding a half-built stack alongside the new one.
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        privateStore = nil
        sharedStore = nil
        openStores(inMemory: inMemory, cloud: false)
    }

    private func configureDescriptions(inMemory: Bool, cloud: Bool) {
        let base = NSPersistentStoreDescription()
        if inMemory {
            base.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [base]
            return
        }

        let support = NSPersistentContainer.defaultDirectoryURL()
        base.url = support.appendingPathComponent("BudgetTogether.private.sqlite")
        Self.configureCommonOptions(base)

        guard cloud else {
            // Local-only: single on-disk store, no CloudKit.
            container.persistentStoreDescriptions = [base]
            return
        }

        // Mirror both the private and shared databases.
        //
        // Neither description names a configuration. Both stores hold the same
        // entities, so the model's default configuration — the one
        // `model.entities = […]` fills in — is the right one for each, and it
        // has no name to give. Asking for "Default" by name looks harmless and
        // is what a .xcdatamodeld-based project would use, but a model built in
        // code has no configuration by that name: `loadPersistentStores` fails
        // with "Unable to find a configuration named 'Default'", both stores
        // are refused, and the app quietly falls back to a local ledger while
        // looking entirely healthy.
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
        privateOptions.databaseScope = .private
        base.cloudKitContainerOptions = privateOptions

        let shared = NSPersistentStoreDescription(url: support.appendingPathComponent("BudgetTogether.shared.sqlite"))
        Self.configureCommonOptions(shared)
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
        sharedOptions.databaseScope = .shared
        shared.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [base, shared]
    }

    /// How the ledger is protected on disk.
    ///
    /// Stated explicitly rather than inherited: without the key, the class the
    /// file gets depends on the target's data-protection entitlement, which is
    /// a build setting somebody can change without ever opening this file. What
    /// it buys is that the sqlite file is encrypted with a key derived from the
    /// device passcode and is unreadable until the phone has been unlocked once
    /// since boot — which is the state a phone that's been taken is in.
    ///
    /// Deliberately not `.complete`, which would keep it sealed whenever the
    /// screen is off. The app logs from the lock screen: `LogSpendIntent` runs
    /// with `openAppWhenRun = false`, so Siri can launch it into the background
    /// on a locked device, and under `.complete` opening the store there would
    /// simply fail. Silently losing the spend somebody just said is a worse
    /// outcome than the narrow window this closes.
    private static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

    private static func configureCommonOptions(_ description: NSPersistentStoreDescription) {
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(fileProtection.rawValue as NSString,
                              forKey: NSPersistentStoreFileProtectionKey)
    }

    private func captureStore(for description: NSPersistentStoreDescription) {
        let coordinator = container.persistentStoreCoordinator
        guard let url = description.url,
              let store = coordinator.persistentStore(for: url) else { return }
        if description.cloudKitContainerOptions?.databaseScope == .shared {
            sharedStore = store
        } else {
            privateStore = store
        }
    }

#if DEBUG
    /// Whether this launch was asked to build the CloudKit schema rather than
    /// run the app normally. Set the `-InitializeCloudKitSchema` argument in the
    /// scheme's Run arguments, launch once, then take it back out.
    static var wantsSchemaInitialization: Bool {
        ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema")
    }

    /// Creates every record type and field the model implies, in the container's
    /// **Development** environment.
    ///
    /// Mirroring builds the schema lazily: a record type appears in CloudKit the
    /// first time an object of that entity is actually exported. So the schema
    /// reflects what happened to be created on a developer's device, not what
    /// the model describes — and an entity nobody exercised is simply absent.
    /// Promoting to Production copies that gap forward, and the resulting bug is
    /// the worst shape there is: the app works, syncs, looks healthy, and then
    /// one feature silently stops reaching the other phone for the subset of
    /// users who use it. `initializeCloudKitSchema` closes that by walking the
    /// model instead of the data.
    ///
    /// Development only, in both senses: `#if DEBUG` keeps it out of a shipping
    /// binary, and CloudKit itself refuses to run it against Production. The
    /// order is always initialise here, then promote in CloudKit Console.
    ///
    /// Expect it to take a while and to block the launch it runs on. It writes a
    /// sample record of every type and deletes them again, which is a lot of
    /// round trips; that is the method working, not hanging.
    static func initializeCloudKitSchema() {
        // A scratch stack rather than the app's own. Two reasons: the live
        // stack carries a `.shared` description, and schema can't be created in
        // a database owned by somebody else — CloudKit throws rather than
        // skipping it. And a throwaway store means a method that writes sample
        // records can't touch the real ledger even if it goes wrong.
        let model = CDModel.make()
        let container = NSPersistentCloudKitContainer(name: "BudgetTogetherSchema",
                                                      managedObjectModel: model)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaInit-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: scratch)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        // Private scope, but the schema is a property of the *container*, not of
        // a database within it. Building it here is what gives the shared
        // database its record types too.
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        container.persistentStoreDescriptions = [description]

        var loadFailure: Error?
        container.loadPersistentStores { _, error in loadFailure = error }
        if let loadFailure {
            report("Schema init couldn't open its scratch store: \(String(describing: loadFailure))",
                   isFailure: true)
            return
        }

        defer { destroyScratchStore(at: scratch, in: container) }

        report("Building the CloudKit Development schema — this takes a while.")
        do {
            try container.initializeCloudKitSchema(options: [])
            report("""
                DONE. CloudKit Development schema built from the model. \
                Promote it to Production in CloudKit Console before shipping.
                """)
        } catch {
            // Almost always one of three things, none of which are the model:
            // no iCloud account on the device, a build signed by a team that
            // doesn't own the container, or no network.
            report("FAILED. Schema init: \(String(describing: error))", isFailure: true)
        }
    }

    /// Says the same thing twice, to OSLog and to stdout.
    ///
    /// The duplication is the point. On the physical phone this app cannot have
    /// its OSLog read from this Mac at all — the `log` build here has no
    /// `--device` option, and `devicectl … process launch --console` pipes only
    /// stdout, which OSLog notices never reach. A maintenance task whose entire
    /// output is an OSLog line is therefore silent on the one device where it
    /// actually has an iCloud account to run against, which is the only place
    /// worth running it. `print` is what survives the trip.
    private static func report(_ message: String, isFailure: Bool = false) {
        if isFailure {
            log.fault("\(message, privacy: .public)")
        } else {
            log.notice("\(message, privacy: .public)")
        }
        print("[schema-init] \(message)")
    }

    /// Takes the scratch store away properly. Deleting the .sqlite by hand
    /// leaves the -wal and -shm files behind, which is how a "clean" scratch
    /// directory ends up holding the tail of a previous run.
    private static func destroyScratchStore(at url: URL,
                                            in container: NSPersistentCloudKitContainer) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        try? coordinator.destroyPersistentStore(at: url, type: .sqlite, options: nil)
    }
#endif

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees we're on the main thread here.
            MainActor.assumeIsolated {
                self?.viewContext.refreshAllObjects()
                self?.onChange?()
            }
        }
    }

    // MARK: Household

    /// One budget this device can open, for the switcher.
    struct HouseholdSummary: Identifiable, Hashable {
        let id: String
        let name: String
        /// Whether this device's account created it, as opposed to being
        /// invited into it. Everything is owned in local-only mode.
        let isOwned: Bool
        let isSample: Bool
        let createdAt: Date
    }

    /// The household this device reads and writes.
    ///
    /// This used to be "whichever row comes back first, oldest wins", which was
    /// true enough while a device could only ever hold one. Accepting an invite
    /// breaks that: someone who already has their own budget and then joins a
    /// partner's has two, in two different stores, and picking by age would
    /// silently show them the wrong one — with no clue on screen that another
    /// existed, and every write landing in it.
    ///
    /// So the choice is made once, deliberately, and remembered. A stale id —
    /// a budget that was deleted, or a share the owner has since stopped —
    /// falls through to a fresh choice rather than leaving the app with
    /// nothing, and the new choice is written back.
    func currentHousehold() -> NSManagedObject? {
        if let id = selectedHouseholdID, let house = householdObject(id: id) { return house }
        guard let fallback = defaultHousehold() else { return nil }
        selectedHouseholdID = fallback.value(forKey: "id") as? String
        return fallback
    }

    var hasHousehold: Bool { currentHousehold() != nil }

    /// Which budget to open when nobody has said. Real budgets beat the
    /// worked example, budgets you own beat ones you were invited into, and
    /// the oldest breaks the tie — which is the previous behaviour, and the
    /// right answer for the overwhelmingly common case of exactly one.
    private func defaultHousehold() -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        let all = (try? viewContext.fetch(request)) ?? []
        return all.min { a, b in
            let sampleA = a.value(forKey: "isSample") as? Bool ?? false
            let sampleB = b.value(forKey: "isSample") as? Bool ?? false
            if sampleA != sampleB { return !sampleA }
            let ownedA = isOwned(a), ownedB = isOwned(b)
            if ownedA != ownedB { return ownedA }
            let dateA = a.value(forKey: "createdAt") as? Date ?? .distantPast
            let dateB = b.value(forKey: "createdAt") as? Date ?? .distantPast
            return dateA < dateB
        }
    }

    /// Every budget on this device, in the order the switcher shows them.
    func households() -> [HouseholdSummary] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? viewContext.fetch(request)) ?? []).compactMap { house in
            guard let id = house.value(forKey: "id") as? String else { return nil }
            return HouseholdSummary(
                id: id,
                name: house.value(forKey: "name") as? String ?? "Together",
                isOwned: isOwned(house),
                isSample: house.value(forKey: "isSample") as? Bool ?? false,
                createdAt: house.value(forKey: "createdAt") as? Date ?? .distantPast
            )
        }
    }

    /// Whether this device's account owns the household, rather than having
    /// been invited into it. A joined household lives in the shared store.
    private func isOwned(_ house: NSManagedObject) -> Bool {
        guard isCloudSyncActive, let sharedStore else { return true }
        return house.objectID.persistentStore !== sharedStore
    }

    /// Points the device at a different budget. Which member this device is, is
    /// a fact about *a* household, so it can't survive the move — the joiner
    /// claims a seat in the new one (see `claimMember`).
    func switchHousehold(to id: String) {
        guard id != selectedHouseholdID, householdObject(id: id) != nil else { return }
        selectedHouseholdID = id
        localMemberID = matchingMemberID(in: id)
    }

    func householdObject(id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    /// Ensures a household exists with the default caps seeded. Used in local
    /// mode so the app is immediately usable; the explicit pairing flow (Step 2)
    /// will drive this instead.
    @discardableResult
    func bootstrapHouseholdIfNeeded(name: String = "Together",
                                    defaultCaps: [String: Double]) -> NSManagedObject {
        if let existing = currentHousehold() { return existing }
        return createHousehold(name: name, defaultCaps: defaultCaps)
    }

    /// `defaultCaps` may be empty, and usually is: the app no longer demands a
    /// budget before it will open. A household with no caps runs in
    /// "just logging" mode until there's enough spending to suggest real ones.
    @discardableResult
    func createHousehold(name: String, ownerName: String = "You",
                         defaultCaps: [String: Double],
                         isSample: Bool = false) -> NSManagedObject {
        let house = NSManagedObject(entity: entity(CDModel.household), insertInto: viewContext)
        house.setValue(UUID().uuidString, forKey: "id")
        house.setValue(name, forKey: "name")
        house.setValue(Date(), forKey: "createdAt")
        house.setValue(isSample, forKey: "isSample")

        for (bucket, amount) in defaultCaps {
            let cap = NSManagedObject(entity: entity(CDModel.cap), insertInto: viewContext)
            cap.setValue(bucket, forKey: "bucket")
            cap.setValue(amount, forKey: "amount")
            cap.setValue(Date(), forKey: "updatedAt")
            cap.setValue(house, forKey: "household")
        }

        assignToOwnerStore(house)
        // Whoever creates the household is the first member, and is this device.
        let owner = insertMember(name: ownerName, colorIndex: 0, in: house)
        localMemberID = owner.id
        // Opened here rather than left to `defaultHousehold` to work out: a
        // brand-new budget is unambiguously the one the user means, even on a
        // phone that already holds one they were invited into.
        selectedHouseholdID = house.value(forKey: "id") as? String
        save()
        if let me = cloudUserRecordName, !me.isEmpty {
            claimMember(id: owner.id)
        }
        return house
    }

    // MARK: Reads

    struct Snapshot {
        var entries: [Entry] = []
        var caps: [String: Double] = [:]
        /// Oldest first, which is the order the UI shows people in.
        var members: [Member] = []
        var recurring: [Recurring] = []
        var loans: [Loan] = []
        var challenges: [Challenge] = []
        /// Every category including hidden ones, spending first, in user order.
        var categories: [Bucket] = []
        /// Entry id → everyone's reactions to it.
        var reactions: [String: [Reaction]] = [:]
        /// "yyyy-MM" → flag, for months marked unrepresentative.
        var monthFlags: [String: MonthFlag] = [:]
        /// Whether this is the throwaway household behind "Look around first".
        var isSample = false
        var rolloverEnabled = false
    }

    /// Value-type snapshot for the UI, newest entry first. `capsFor` selects
    /// which month's limits come back; entries are always the full history, so
    /// the caller can digest any month and chart across them.
    func loadSnapshot(capsFor month: String? = nil) -> Snapshot {
        guard let house = currentHousehold() else { return Snapshot() }
        let capsMonth = month ?? Fmt.isoMonth(Date())

        backfillHouseholdIDs(for: house)
        let rows = fetchEntryObjects(for: house)
        migrateLegacyMembersIfNeeded(in: house, entries: rows)

        let entries: [Entry] = rows.compactMap { obj in
            guard let id = obj.value(forKey: "id") as? String else { return nil }
            return Entry(
                id: id,
                date: obj.value(forKey: "date") as? String ?? "",
                place: obj.value(forKey: "place") as? String ?? "",
                bucket: obj.value(forKey: "bucket") as? String ?? "",
                amount: obj.value(forKey: "amount") as? Double ?? 0,
                memberID: obj.value(forKey: "memberID") as? String ?? "",
                kind: EntryKind(rawValue: obj.value(forKey: "kind") as? String ?? "") ?? .expense,
                mood: (obj.value(forKey: "mood") as? String).flatMap(Mood.init(rawValue:)),
                note: obj.value(forKey: "note") as? String ?? "",
                belowTheLine: obj.value(forKey: "belowTheLine") as? Bool ?? false,
                isPrivate: obj.value(forKey: "isPrivate") as? Bool ?? false,
                createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
            )
        }
        return Snapshot(entries: entries,
                        caps: loadCaps(for: house, month: capsMonth),
                        members: loadMembers(for: house),
                        recurring: loadRecurring(for: house),
                        loans: loadLoans(for: house),
                        challenges: loadChallenges(for: house),
                        categories: loadCategories(for: house),
                        reactions: loadReactions(for: house),
                        monthFlags: loadMonthFlags(for: house),
                        isSample: house.value(forKey: "isSample") as? Bool ?? false,
                        rolloverEnabled: house.value(forKey: "rolloverEnabled") as? Bool ?? false)
    }

    // MARK: Out-of-app writes

    /// Loads just enough for a write that didn't come from the UI — a Siri
    /// phrase, a Shortcut, a widget tap — and returns the snapshot behind it.
    ///
    /// These can all run with no `AppModel` in existence, so nothing has
    /// populated `CategoryRegistry` and `Bucket.named(_:)` would answer
    /// "Uncategorised" for every id. This is the one-line prelude that makes an
    /// intent see the same categories the app does.
    @discardableResult
    func prepareForBackgroundWrite() -> Snapshot {
        let snapshot = loadSnapshot()
        CategoryRegistry.replace(with: snapshot.categories)
        return snapshot
    }

    /// Tells whoever is observing that data changed. Remote-change
    /// notifications cover other devices; a local write from an intent while
    /// the app happens to be running needs saying explicitly, or the UI keeps
    /// showing yesterday's totals.
    func notifyChanged() { onChange?() }

    // MARK: Export

    /// One stored limit, for the full export. The UI only ever wants the caps
    /// in force for a given month; a backup wants every row that ever existed.
    struct CapRow {
        let bucket: String
        /// "yyyy-MM", or "" for the pre-months baseline.
        let month: String
        let amount: Double
        let updatedAt: Date?
    }

    func allCaps() -> [CapRow] {
        guard let house = currentHousehold() else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.cap)
        request.predicate = NSPredicate(format: "household == %@", house)
        return ((try? viewContext.fetch(request)) ?? []).compactMap { obj in
            guard let bucket = obj.value(forKey: "bucket") as? String else { return nil }
            return CapRow(bucket: bucket,
                          month: obj.value(forKey: "month") as? String ?? "",
                          amount: obj.value(forKey: "amount") as? Double ?? 0,
                          updatedAt: obj.value(forKey: "updatedAt") as? Date)
        }
        .sorted { $0.month == $1.month ? $0.bucket < $1.bucket : $0.month < $1.month }
    }

    var householdName: String {
        currentHousehold()?.value(forKey: "name") as? String ?? "Together"
    }

    // MARK: Erase

    /// Deletes everything this app has ever stored on the device, including the
    /// per-device preferences that live outside Core Data.
    ///
    /// Deliberately blunt: it walks every entity rather than relying on the
    /// household cascade, because entries and reactions are matched by id and
    /// a private entry has no household relationship at all — a cascade would
    /// leave exactly the most sensitive rows behind.
    ///
    /// Returns whether the on-disk files were actually confirmed gone. The
    /// rows are deleted from the live context either way — the app is empty
    /// from here regardless — but the caller needs to know if the bytes
    /// behind them might not be, because "delete everything" that quietly
    /// isn't is worse than one that says so.
    @discardableResult
    func eraseEverything() -> Bool {
        let entities = [CDModel.entry, CDModel.reaction, CDModel.cap, CDModel.member,
                        CDModel.recurring, CDModel.loan, CDModel.challenge,
                        CDModel.monthFlag, CDModel.category, CDModel.household]
        for name in entities {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            for obj in (try? viewContext.fetch(request)) ?? [] { viewContext.delete(obj) }
        }
        save()
        let destroyed = rebuildStores()

        // Anything the app kept in UserDefaults is data about the user too.
        if let defaults {
            for key in defaults.dictionaryRepresentation().keys
            where Self.ownedDefaultsKeys.contains(key)
                || key.hasPrefix("capAlert.") || key.hasPrefix("limitAlertMuted.") {
                defaults.removeObject(forKey: key)
            }
        }
        localMemberIDInMemory = nil
        return destroyed
    }

    /// Keys this app owns. Listed rather than wildcarded so a wipe can never
    /// reach into another framework's preferences.
    private static let ownedDefaultsKeys: Set<String> = [
        localMemberKey, selectedHouseholdKey, userRecordKey,
        "antiBudgetMode", "appearance",
        "notificationsRequested", "limitAlertsEnabled",
    ]

    /// Destroys the store file and opens a fresh empty one in its place.
    ///
    /// Deleting the rows is not the same as deleting the data, and for this app
    /// the difference is the whole promise. Persistent history tracking is on,
    /// so alongside the rows the store keeps a transaction log of every change
    /// the app has ever made — the values included — and deleting the objects
    /// doesn't touch it. Freed sqlite pages hold their old contents too, until
    /// something happens to overwrite them. "There is no copy on a server to
    /// restore from" is only true if there isn't one on the phone either.
    ///
    /// Returns whether every on-disk file was actually confirmed gone
    /// afterward — not whether Core Data reported success, which is a
    /// different question. `destroyPersistentStore` and `remove` can each
    /// fail (a locked file, a storage glitch) without leaving the store any
    /// less present on disk, and reporting "erased" on their say-so alone
    /// would be trusting the one part of this that's allowed to be wrong.
    /// So every removal is attempted directly and unconditionally — not only
    /// as a fallback when the calls above throw — and checked with
    /// `fileExists` rather than assumed from a lack of a thrown error.
    ///
    /// Failure here still leaves the app usable: the rows are already gone
    /// from the live context by the time this runs, so the worst case is
    /// residue in a file the caller now knows to tell the user about, rather
    /// than residue nobody was ever told existed.
    @discardableResult
    private func rebuildStores() -> Bool {
        let coordinator = container.persistentStoreCoordinator
        viewContext.reset()

        var allDestroyed = true

        // Snapshotted, because removing a store mutates the coordinator's list.
        for store in Array(coordinator.persistentStores) {
            // The in-memory store used by previews has nothing on disk to take.
            guard let url = store.url, url.isFileURL, url.path != "/dev/null" else { continue }

            do {
                try coordinator.remove(store)
            } catch {
                assertionFailure("Failed to detach store: \(error)")
            }
            do {
                try coordinator.destroyPersistentStore(at: url, type: .sqlite)
            } catch {
                assertionFailure("Failed to destroy store: \(error)")
            }

            // `destroyPersistentStore` is documented as leaving the file in
            // place, truncated. The write-ahead log and shared-memory files
            // beside it are where the most recent transactions live, so those
            // go as well rather than being left to be recovered from. This
            // runs regardless of whether the calls above threw — it's the
            // actual guarantee, Core Data's cooperation is not — and each
            // removal is verified rather than trusted.
            for suffix in ["", "-wal", "-shm"] {
                let path = url.path + suffix
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                if FileManager.default.fileExists(atPath: path) {
                    assertionFailure("Store file still present after erase: \(path)")
                    allDestroyed = false
                }
            }
        }

        privateStore = nil
        sharedStore = nil
        container.loadPersistentStores { [weak self] desc, error in
            if let error {
                assertionFailure("Failed to reopen store after erase: \(error)")
                return
            }
            self?.captureStore(for: desc)
        }
        return allDestroyed
    }

    // MARK: Categories

    /// Every category, spending first then income, each in its own sort order.
    /// Seeds the built-ins on first read, which doubles as the migration for
    /// budgets created before categories were user data — their entries already
    /// use the built-in ids, so seeding is all that's needed to make them
    /// resolve again.
    func loadCategories(for house: NSManagedObject) -> [Bucket] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.category)
        request.predicate = NSPredicate(format: "household == %@", house)
        var rows = (try? viewContext.fetch(request)) ?? []

        if rows.isEmpty {
            seedBuiltInCategories(in: house)
            rows = (try? viewContext.fetch(request)) ?? []
        }

        return rows.compactMap(category(from:)).sorted {
            $0.kind == $1.kind ? $0.sortOrder < $1.sortOrder : $0.kind == .expense
        }
    }

    private func category(from obj: NSManagedObject) -> Bucket? {
        guard let id = obj.value(forKey: "id") as? String, !id.isEmpty else { return nil }
        return Bucket(
            id: id,
            label: obj.value(forKey: "label") as? String ?? id,
            hex: obj.value(forKey: "hex") as? String ?? "8892B0",
            light: obj.value(forKey: "lightHex") as? String ?? "626E93",
            symbol: obj.value(forKey: "symbol") as? String ?? "questionmark.circle.fill",
            cadence: Cadence(rawValue: obj.value(forKey: "cadence") as? String ?? "") ?? .variable,
            kind: EntryKind(rawValue: obj.value(forKey: "kind") as? String ?? "") ?? .expense,
            isHidden: obj.value(forKey: "isHidden") as? Bool ?? false,
            isBuiltIn: obj.value(forKey: "isBuiltIn") as? Bool ?? false,
            sortOrder: Int(obj.value(forKey: "sortOrder") as? Int64 ?? 0)
        )
    }

    private func seedBuiltInCategories(in house: NSManagedObject) {
        for seed in Bucket.builtInAll { insertCategory(seed, in: house) }
        save()
    }

    @discardableResult
    private func insertCategory(_ bucket: Bucket, in house: NSManagedObject) -> NSManagedObject {
        let obj = NSManagedObject(entity: entity(CDModel.category), insertInto: viewContext)
        obj.setValue(bucket.id, forKey: "id")
        obj.setValue(Date(), forKey: "createdAt")
        obj.setValue(house, forKey: "household")
        assign(obj, toStoreOf: house)
        write(bucket, to: obj)
        return obj
    }

    private func write(_ bucket: Bucket, to obj: NSManagedObject) {
        obj.setValue(bucket.label, forKey: "label")
        obj.setValue(bucket.symbol, forKey: "symbol")
        obj.setValue(bucket.hex, forKey: "hex")
        obj.setValue(bucket.lightHex, forKey: "lightHex")
        obj.setValue(bucket.cadence.rawValue, forKey: "cadence")
        obj.setValue(bucket.kind.rawValue, forKey: "kind")
        obj.setValue(Int64(bucket.sortOrder), forKey: "sortOrder")
        obj.setValue(bucket.isHidden, forKey: "isHidden")
        obj.setValue(bucket.isBuiltIn, forKey: "isBuiltIn")
    }

    /// Inserts or updates by id.
    func saveCategory(_ bucket: Bucket) {
        guard let house = currentHousehold() else { return }
        if let existing = categoryObject(id: bucket.id) {
            write(bucket, to: existing)
        } else {
            insertCategory(bucket, in: house)
        }
        save()
    }

    /// Writes a whole reordering in one transaction.
    func saveCategoryOrder(_ buckets: [Bucket]) {
        for bucket in buckets {
            categoryObject(id: bucket.id)?
                .setValue(Int64(bucket.sortOrder), forKey: "sortOrder")
        }
        save()
    }

    func deleteCategory(id: String) {
        guard let obj = categoryObject(id: id) else { return }
        viewContext.delete(obj)
        save()
    }

    /// How many stored things point at a category. Deletion is only offered
    /// when this is zero everywhere — a category with history behind it gets
    /// hidden instead, so the ledger never develops holes.
    func references(categoryID id: String) -> (entries: Int, caps: Int,
                                               recurring: Int, challenges: Int) {
        func count(_ entityName: String, _ predicate: NSPredicate) -> Int {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = predicate
            return (try? viewContext.count(for: request)) ?? 0
        }
        return (
            entries: count(CDModel.entry, NSPredicate(format: "bucket == %@", id)),
            caps: count(CDModel.cap, NSPredicate(format: "bucket == %@ AND amount > 0", id)),
            recurring: count(CDModel.recurring, NSPredicate(format: "bucket == %@", id)),
            challenges: count(CDModel.challenge, NSPredicate(format: "bucket == %@", id))
        )
    }

    private func categoryObject(id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.category)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    // MARK: Reactions

    private func loadReactions(for house: NSManagedObject) -> [String: [Reaction]] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.reaction)
        let id = house.value(forKey: "id") as? String ?? ""
        request.predicate = NSPredicate(format: "householdID == %@ OR household == %@", id, house)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        var byEntry: [String: [Reaction]] = [:]
        for obj in (try? viewContext.fetch(request)) ?? [] {
            guard let id = obj.value(forKey: "id") as? String,
                  let entryID = obj.value(forKey: "entryID") as? String,
                  let kind = (obj.value(forKey: "kind") as? String)
                      .flatMap(ReactionKind.init(rawValue:)) else { continue }
            byEntry[entryID, default: []].append(Reaction(
                id: id,
                entryID: entryID,
                memberID: obj.value(forKey: "memberID") as? String ?? "",
                kind: kind,
                createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
            ))
        }
        return byEntry
    }

    /// One reaction per person per entry. Reacting again with the same kind
    /// clears it (so the button toggles); a different kind replaces it.
    func toggleReaction(entryID: String, memberID: String, kind: ReactionKind) {
        guard let house = currentHousehold() else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.reaction)
        request.predicate = NSPredicate(format: "entryID == %@ AND memberID == %@",
                                        entryID, memberID)
        let existing = (try? viewContext.fetch(request)) ?? []

        let sameKind = existing.first {
            ($0.value(forKey: "kind") as? String) == kind.rawValue
        }
        existing.forEach(viewContext.delete)
        if sameKind == nil {
            let obj = NSManagedObject(entity: entity(CDModel.reaction), insertInto: viewContext)
            obj.setValue(UUID().uuidString, forKey: "id")
            obj.setValue(entryID, forKey: "entryID")
            obj.setValue(memberID, forKey: "memberID")
            obj.setValue(kind.rawValue, forKey: "kind")
            obj.setValue(house.value(forKey: "id"), forKey: "householdID")
            obj.setValue(Date(), forKey: "createdAt")
            obj.setValue(house, forKey: "household")
            assign(obj, toStoreOf: house)
        }
        save()
    }

    /// Reactions are meaningless once the entry they point at is gone.
    private func deleteReactions(entryID: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.reaction)
        request.predicate = NSPredicate(format: "entryID == %@", entryID)
        for obj in (try? viewContext.fetch(request)) ?? [] { viewContext.delete(obj) }
    }

    // MARK: Month flags

    private func loadMonthFlags(for house: NSManagedObject) -> [String: MonthFlag] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.monthFlag)
        request.predicate = NSPredicate(format: "household == %@", house)
        var flags: [String: MonthFlag] = [:]
        for obj in (try? viewContext.fetch(request)) ?? [] {
            guard let month = obj.value(forKey: "month") as? String else { continue }
            flags[month] = MonthFlag(
                month: month,
                isUnusual: obj.value(forKey: "isUnusual") as? Bool ?? false,
                reason: obj.value(forKey: "reason") as? String ?? ""
            )
        }
        return flags
    }

    func setMonthFlag(month: String, isUnusual: Bool, reason: String) {
        guard let house = currentHousehold() else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.monthFlag)
        request.predicate = NSPredicate(format: "month == %@ AND household == %@", month, house)
        request.fetchLimit = 1
        let obj = (try? viewContext.fetch(request))?.first ?? {
            let new = NSManagedObject(entity: entity(CDModel.monthFlag), insertInto: viewContext)
            new.setValue(month, forKey: "month")
            new.setValue(house, forKey: "household")
            assign(new, toStoreOf: house)
            return new
        }()
        obj.setValue(isUnusual, forKey: "isUnusual")
        obj.setValue(reason, forKey: "reason")
        obj.setValue(Date(), forKey: "updatedAt")
        save()
    }

    // MARK: Household settings

    func setRollover(_ enabled: Bool) {
        guard let house = currentHousehold() else { return }
        house.setValue(enabled, forKey: "rolloverEnabled")
        save()
    }

    /// Tears down the sample household and everything hanging off it, so
    /// "Start my own" begins from genuinely nothing rather than from demo data
    /// with the user's first real entry mixed into it.
    func deleteSampleHousehold() {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        request.predicate = NSPredicate(format: "isSample == YES")
        for house in (try? viewContext.fetch(request)) ?? [] {
            let id = house.value(forKey: "id") as? String ?? ""
            // Entries and reactions are matched by id, not by relationship, so
            // the cascade rule doesn't reach them.
            for name in [CDModel.entry, CDModel.reaction] {
                let orphans = NSFetchRequest<NSManagedObject>(entityName: name)
                orphans.predicate = NSPredicate(format: "householdID == %@", id)
                for obj in (try? viewContext.fetch(orphans)) ?? [] { viewContext.delete(obj) }
            }
            viewContext.delete(house)
            if selectedHouseholdID == id { selectedHouseholdID = nil }
        }
        localMemberID = nil
        save()
    }

    private func fetchEntryObjects(for house: NSManagedObject) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        // Matched by id, not by relationship — private entries deliberately have
        // no household relationship, because they live in another store.
        let id = house.value(forKey: "id") as? String ?? ""
        request.predicate = NSPredicate(format: "householdID == %@ OR household == %@", id, house)
        // Sorting in the store beats sorting in Swift, and `createdAt` breaks
        // ties within a day deterministically (entry ids are random UUIDs).
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
        return (try? viewContext.fetch(request)) ?? []
    }

    /// Caps in force for an arbitrary month, without reloading everything else.
    /// The alert check needs the live month's limits even while the user is
    /// browsing an earlier one.
    func caps(for month: String) -> [String: Double] {
        guard let house = currentHousehold() else { return [:] }
        return loadCaps(for: house, month: month)
    }

    func loadMembers(for house: NSManagedObject) -> [Member] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.member)
        request.predicate = NSPredicate(format: "household == %@", house)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? viewContext.fetch(request)) ?? []).compactMap(member(from:))
    }

    private func member(from obj: NSManagedObject) -> Member? {
        guard let id = obj.value(forKey: "id") as? String else { return nil }
        return Member(
            id: id,
            name: obj.value(forKey: "name") as? String ?? "",
            colorIndex: Int(obj.value(forKey: "colorIndex") as? Int64 ?? 0),
            createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast,
            userRecordName: obj.value(forKey: "userRecordName") as? String
        )
    }

    /// Entries written before privacy existed are found only by relationship.
    /// Stamp the id on them once so the new predicate keeps seeing them.
    private func backfillHouseholdIDs(for house: NSManagedObject) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        request.predicate = NSPredicate(format: "household == %@ AND householdID == nil", house)
        let rows = (try? viewContext.fetch(request)) ?? []
        guard !rows.isEmpty else { return }
        let id = house.value(forKey: "id")
        for row in rows { row.setValue(id, forKey: "householdID") }
        save()
    }

    /// Households created before people were first-class stored the spender as a
    /// `"you"`/`"friend"` role on each entry. Turn every distinct role into a real
    /// member row, once, and point the entries at it.
    private func migrateLegacyMembersIfNeeded(in house: NSManagedObject, entries: [NSManagedObject]) {
        guard loadMembers(for: house).isEmpty else { return }

        // Oldest first, so "you" (created at setup) tends to take colour 0.
        var order: [String] = []
        for obj in entries.reversed() {
            guard let role = obj.value(forKey: "memberRole") as? String, !role.isEmpty,
                  !order.contains(role) else { continue }
            order.append(role)
        }
        if order.isEmpty { order = ["you"] }
        else if let you = order.firstIndex(of: "you"), you != 0 {
            order.insert(order.remove(at: you), at: 0)
        }

        var idForRole: [String: String] = [:]
        for (index, role) in order.enumerated() {
            let name = role == "you" ? "You" : role.prefix(1).uppercased() + role.dropFirst()
            idForRole[role] = insertMember(name: name, colorIndex: index, in: house).id
        }

        for obj in entries {
            let role = obj.value(forKey: "memberRole") as? String ?? "you"
            obj.setValue(idForRole[role] ?? idForRole["you"], forKey: "memberID")
        }
        if localMemberID == nil { localMemberID = idForRole["you"] ?? idForRole[order[0]] }
        save()
    }

    /// Caps in force for `month`: the most recent row at or before it, per
    /// bucket. A month with no rows of its own therefore inherits the last set
    /// of limits rather than reading as zero, and editing this month's cap
    /// leaves earlier months measured against what they were actually given.
    private func loadCaps(for house: NSManagedObject, month: String) -> [String: Double] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.cap)
        request.predicate = NSPredicate(format: "household == %@", house)
        let rows = (try? viewContext.fetch(request)) ?? []

        // Dedupe: if the same bucket-month has several rows (e.g. both people
        // set one while offline), keep the most recently updated and delete the
        // rest so the graph converges.
        var best: [String: NSManagedObject] = [:]      // "bucket|month" → row
        var stale: [NSManagedObject] = []
        for row in rows {
            guard let bucket = row.value(forKey: "bucket") as? String else { continue }
            let key = bucket + "|" + (row.value(forKey: "month") as? String ?? "")
            if let current = best[key] {
                let a = current.value(forKey: "updatedAt") as? Date ?? .distantPast
                let b = row.value(forKey: "updatedAt") as? Date ?? .distantPast
                if b > a { stale.append(current); best[key] = row }
                else { stale.append(row) }
            } else {
                best[key] = row
            }
        }
        if !stale.isEmpty {
            stale.forEach(viewContext.delete)
            save()
        }

        // Latest applicable row wins. "" (a pre-months baseline) sorts below
        // every real month key, which is exactly the fallback we want.
        var effective: [String: (month: String, amount: Double)] = [:]
        for row in best.values {
            guard let bucket = row.value(forKey: "bucket") as? String else { continue }
            let rowMonth = row.value(forKey: "month") as? String ?? ""
            guard rowMonth <= month else { continue }
            if let current = effective[bucket], current.month > rowMonth { continue }
            effective[bucket] = (rowMonth, row.value(forKey: "amount") as? Double ?? 0)
        }
        return effective.mapValues(\.amount)
    }

    // MARK: Writes

    /// `createdAt` is normally stamped now, but an undo passes the original back
    /// so a restored entry lands in the same place in its day rather than
    /// jumping to the top of it.
    func addEntry(id: String, date: String, place: String, amount: Double,
                  bucket: String, memberID: String, kind: EntryKind = .expense,
                  mood: Mood? = nil, note: String = "", belowTheLine: Bool = false,
                  isPrivate: Bool = false, createdAt: Date = Date()) {
        guard let house = currentHousehold() else { return }
        let entry = NSManagedObject(entity: entity(CDModel.entry), insertInto: viewContext)
        entry.setValue(id, forKey: "id")
        entry.setValue(date, forKey: "date")
        entry.setValue(place, forKey: "place")
        entry.setValue(bucket, forKey: "bucket")
        entry.setValue(amount, forKey: "amount")
        entry.setValue(memberID, forKey: "memberID")
        entry.setValue(kind.rawValue, forKey: "kind")
        entry.setValue(mood?.rawValue, forKey: "mood")
        entry.setValue(note, forKey: "note")
        entry.setValue(belowTheLine, forKey: "belowTheLine")
        entry.setValue(isPrivate, forKey: "isPrivate")
        entry.setValue(house.value(forKey: "id"), forKey: "householdID")
        entry.setValue(createdAt, forKey: "createdAt")
        assignStore(entry, isPrivate: isPrivate, household: house)
        save()
    }

    /// Decides which store an entry lands in — the whole privacy guarantee.
    ///
    /// A private entry goes to the local private store and gets **no** household
    /// relationship, because a relationship can't cross stores and the household
    /// may live in the shared one. Everything else follows its household, so a
    /// participant's shared entries still sync back to the owner.
    private func assignStore(_ entry: NSManagedObject, isPrivate: Bool,
                             household house: NSManagedObject) {
        guard isCloudSyncActive else {
            // Local-only mode: one store, so the relationship is safe and
            // nothing leaves the device either way.
            entry.setValue(house, forKey: "household")
            return
        }
        guard isPrivate, let privateStore else {
            entry.setValue(house, forKey: "household")
            assign(entry, toStoreOf: house)
            return
        }
        viewContext.assign(entry, to: privateStore)
    }

    /// Edits an existing entry in place. `createdAt` is deliberately untouched
    /// so an edit doesn't reshuffle the day's ordering under the user.
    func updateEntry(id: String, date: String, place: String, amount: Double,
                     bucket: String, memberID: String, kind: EntryKind, mood: Mood?,
                     note: String, belowTheLine: Bool, isPrivate: Bool) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        guard let entry = (try? viewContext.fetch(request))?.first else { return }

        // Changing privacy means changing which store the row belongs in, and
        // an object can't be reassigned once saved. Recreate it instead, so a
        // shared entry turned private genuinely leaves the shared store.
        if (entry.value(forKey: "isPrivate") as? Bool ?? false) != isPrivate {
            let created = entry.value(forKey: "createdAt") as? Date ?? Date()
            viewContext.delete(entry)
            save()
            addEntry(id: id, date: date, place: place, amount: amount, bucket: bucket,
                     memberID: memberID, kind: kind, mood: mood, note: note,
                     belowTheLine: belowTheLine, isPrivate: isPrivate, createdAt: created)
            return
        }

        entry.setValue(date, forKey: "date")
        entry.setValue(place, forKey: "place")
        entry.setValue(bucket, forKey: "bucket")
        entry.setValue(amount, forKey: "amount")
        entry.setValue(memberID, forKey: "memberID")
        entry.setValue(kind.rawValue, forKey: "kind")
        entry.setValue(mood?.rawValue, forKey: "mood")
        entry.setValue(note, forKey: "note")
        entry.setValue(belowTheLine, forKey: "belowTheLine")
        save()
    }

    private func entryObject(id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    // MARK: Members

    @discardableResult
    func addMember(name: String, colorIndex: Int) -> Member? {
        guard let house = currentHousehold() else { return nil }
        let member = insertMember(name: name, colorIndex: colorIndex, in: house)
        save()
        return member
    }

    /// Inserts the row without saving, so household creation can commit the
    /// household and its first member in one go.
    @discardableResult
    private func insertMember(name: String, colorIndex: Int,
                              in house: NSManagedObject) -> Member {
        let obj = NSManagedObject(entity: entity(CDModel.member), insertInto: viewContext)
        let member = Member(id: UUID().uuidString, name: name,
                            colorIndex: colorIndex, createdAt: Date())
        obj.setValue(member.id, forKey: "id")
        obj.setValue(member.name, forKey: "name")
        obj.setValue(Int64(member.colorIndex), forKey: "colorIndex")
        obj.setValue(member.createdAt, forKey: "createdAt")
        obj.setValue(house, forKey: "household")
        assign(obj, toStoreOf: house)
        return member
    }

    /// Puts a removed member back with their original id, so the entries being
    /// restored alongside them still resolve. `insertMember` can't be reused —
    /// it mints a fresh id, which would orphan every one of those entries.
    func restoreMember(_ member: Member) {
        guard let house = currentHousehold(), memberObject(id: member.id) == nil else { return }
        let obj = NSManagedObject(entity: entity(CDModel.member), insertInto: viewContext)
        obj.setValue(member.id, forKey: "id")
        obj.setValue(member.name, forKey: "name")
        obj.setValue(Int64(member.colorIndex), forKey: "colorIndex")
        obj.setValue(member.createdAt, forKey: "createdAt")
        obj.setValue(house, forKey: "household")
        assign(obj, toStoreOf: house)
        save()
    }

    func updateMember(id: String, name: String? = nil, colorIndex: Int? = nil) {
        guard let obj = memberObject(id: id) else { return }
        if let name { obj.setValue(name, forKey: "name") }
        if let colorIndex { obj.setValue(Int64(colorIndex), forKey: "colorIndex") }
        save()
    }

    /// Removes a member along with everything they logged — the entries are
    /// meaningless once there's nobody to attribute them to.
    func deleteMember(id: String) {
        guard let obj = memberObject(id: id) else { return }
        for entry in entryObjects(memberID: id) { viewContext.delete(entry) }
        viewContext.delete(obj)
        if localMemberID == id { localMemberID = nil }
        save()
    }

    /// How much of the log would go with this member, for the delete warning.
    func entryCount(memberID: String) -> Int { entryObjects(memberID: memberID).count }

    // MARK: Seats

    /// Ties a seat to the iCloud account holding this phone, and makes it the
    /// member this device logs as.
    ///
    /// Two things happen here on purpose. "This is me" has always been a
    /// per-device preference (`localMemberID`), and stays one. Stamping the
    /// account onto the row is the shared half, and it buys two things worth
    /// having on a budget more than one person is in: the same seat can't be
    /// claimed by two different people, and somebody's second device
    /// recognises its own seat without being asked again.
    ///
    /// Returns false if the seat is already somebody else's, which the UI
    /// shouldn't offer but shouldn't be the only thing preventing either.
    @discardableResult
    func claimMember(id: String) -> Bool {
        guard let obj = memberObject(id: id) else { return false }
        let occupant = obj.value(forKey: "userRecordName") as? String ?? ""
        guard let me = cloudUserRecordName, !me.isEmpty else {
            // No iCloud identity to stamp — local-only, or iCloud not signed
            // in. The per-device half still works, which is all this app did
            // before sharing existed.
            localMemberID = id
            return true
        }
        guard occupant.isEmpty || occupant == me else { return false }

        // One account, one seat per budget. Leaving the old stamp behind would
        // make `matchingMemberID` ambiguous the moment someone corrects a
        // mis-tap.
        if let house = obj.value(forKey: "household") as? NSManagedObject {
            for seat in members(in: house, claimedBy: me) where seat != obj {
                seat.setValue(nil, forKey: "userRecordName")
            }
        }
        obj.setValue(me, forKey: "userRecordName")
        localMemberID = id
        save()
        return true
    }

    /// Lines this device up with its seat, in whichever direction is missing.
    ///
    /// Two halves can each be present without the other, and both happen in
    /// ordinary use:
    ///
    ///   * The person who created the budget picked their seat by typing their
    ///     name into the pairing screen, long before there was a share or an
    ///     account to stamp on it. Their row needs the stamp.
    ///   * Their iPad syncs that row down through the private database and has
    ///     no idea which seat is its own — `localMemberID` is per-device and
    ///     deliberately never mirrors. It needs the seat.
    ///
    /// Without the second half a second device is left at "which one of these
    /// is you?" forever, being offered a seat it already owns.
    func reconcileLocalMember() {
        guard let me = cloudUserRecordName, !me.isEmpty,
              let house = currentHousehold() else { return }

        if let id = localMemberID, let obj = memberObject(id: id) {
            guard (obj.value(forKey: "userRecordName") as? String ?? "").isEmpty else { return }
            obj.setValue(me, forKey: "userRecordName")
            save()
            return
        }
        if let id = members(in: house, claimedBy: me).first?.value(forKey: "id") as? String {
            localMemberID = id
        }
    }

    /// The seat in `householdID` this device's account already sits in, if any.
    func matchingMemberID(in householdID: String) -> String? {
        guard let me = cloudUserRecordName, !me.isEmpty,
              let house = householdObject(id: householdID) else { return nil }
        return members(in: house, claimedBy: me).first?.value(forKey: "id") as? String
    }

    private func members(in house: NSManagedObject, claimedBy record: String) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.member)
        request.predicate = NSPredicate(format: "household == %@ AND userRecordName == %@",
                                        house, record)
        return (try? viewContext.fetch(request)) ?? []
    }

    // MARK: Recurring

    func loadRecurring(for house: NSManagedObject) -> [Recurring] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.recurring)
        request.predicate = NSPredicate(format: "household == %@", house)
        request.sortDescriptors = [NSSortDescriptor(key: "dayOfMonth", ascending: true)]
        return ((try? viewContext.fetch(request)) ?? []).compactMap { obj in
            guard let id = obj.value(forKey: "id") as? String else { return nil }
            return Recurring(
                id: id,
                place: obj.value(forKey: "place") as? String ?? "",
                amount: obj.value(forKey: "amount") as? Double ?? 0,
                bucket: obj.value(forKey: "bucket") as? String ?? "",
                memberID: obj.value(forKey: "memberID") as? String ?? "",
                kind: EntryKind(rawValue: obj.value(forKey: "kind") as? String ?? "") ?? .expense,
                dayOfMonth: Int(obj.value(forKey: "dayOfMonth") as? Int64 ?? 1),
                isActive: obj.value(forKey: "isActive") as? Bool ?? true,
                lastPostedMonth: obj.value(forKey: "lastPostedMonth") as? String ?? ""
            )
        }
    }

    /// Convenience for the auto-poster, which runs before a full snapshot load.
    func loadRecurringForCurrentHousehold() -> [Recurring] {
        guard let house = currentHousehold() else { return [] }
        return loadRecurring(for: house)
    }

    func saveRecurring(_ item: Recurring) {
        guard let house = currentHousehold() else { return }
        let obj = recurringObject(id: item.id) ?? {
            let new = NSManagedObject(entity: entity(CDModel.recurring), insertInto: viewContext)
            new.setValue(item.id, forKey: "id")
            new.setValue(Date(), forKey: "createdAt")
            new.setValue(house, forKey: "household")
            assign(new, toStoreOf: house)
            return new
        }()
        obj.setValue(item.place, forKey: "place")
        obj.setValue(item.amount, forKey: "amount")
        obj.setValue(item.bucket, forKey: "bucket")
        obj.setValue(item.memberID, forKey: "memberID")
        obj.setValue(item.kind.rawValue, forKey: "kind")
        obj.setValue(Int64(item.dayOfMonth), forKey: "dayOfMonth")
        obj.setValue(item.isActive, forKey: "isActive")
        obj.setValue(item.lastPostedMonth, forKey: "lastPostedMonth")
        save()
    }

    func deleteRecurring(id: String) {
        guard let obj = recurringObject(id: id) else { return }
        viewContext.delete(obj)
        save()
    }

    // MARK: Challenges

    func loadChallenges(for house: NSManagedObject) -> [Challenge] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.challenge)
        request.predicate = NSPredicate(format: "household == %@", house)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return ((try? viewContext.fetch(request)) ?? []).compactMap { obj in
            guard let id = obj.value(forKey: "id") as? String else { return nil }
            return Challenge(
                id: id,
                title: obj.value(forKey: "title") as? String ?? "",
                kind: ChallengeKind(rawValue: obj.value(forKey: "kind") as? String ?? "")
                    ?? .noSpend,
                bucket: obj.value(forKey: "bucket") as? String,
                target: obj.value(forKey: "target") as? Double ?? 0,
                startDate: obj.value(forKey: "startDate") as? String ?? "",
                endDate: obj.value(forKey: "endDate") as? String ?? "",
                createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
            )
        }
    }

    func saveChallenge(_ challenge: Challenge) {
        guard let house = currentHousehold() else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.challenge)
        request.predicate = NSPredicate(format: "id == %@", challenge.id)
        request.fetchLimit = 1
        let obj = (try? viewContext.fetch(request))?.first ?? {
            let new = NSManagedObject(entity: entity(CDModel.challenge), insertInto: viewContext)
            new.setValue(challenge.id, forKey: "id")
            new.setValue(challenge.createdAt, forKey: "createdAt")
            new.setValue(house, forKey: "household")
            assign(new, toStoreOf: house)
            return new
        }()
        obj.setValue(challenge.title, forKey: "title")
        obj.setValue(challenge.kind.rawValue, forKey: "kind")
        obj.setValue(challenge.bucket, forKey: "bucket")
        obj.setValue(challenge.target, forKey: "target")
        obj.setValue(challenge.startDate, forKey: "startDate")
        obj.setValue(challenge.endDate, forKey: "endDate")
        save()
    }

    func deleteChallenge(id: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.challenge)
        request.predicate = NSPredicate(format: "id == %@", id)
        for obj in (try? viewContext.fetch(request)) ?? [] { viewContext.delete(obj) }
        save()
    }

    // MARK: Loans

    func loadLoans(for house: NSManagedObject) -> [Loan] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.loan)
        request.predicate = NSPredicate(format: "household == %@", house)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? viewContext.fetch(request)) ?? []).compactMap { obj in
            guard let id = obj.value(forKey: "id") as? String else { return nil }
            return Loan(
                id: id,
                name: obj.value(forKey: "name") as? String ?? "",
                balance: obj.value(forKey: "balance") as? Double ?? 0,
                rate: obj.value(forKey: "rate") as? Double ?? 0,
                monthlyPayment: obj.value(forKey: "monthlyPayment") as? Double ?? 0,
                createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
            )
        }
    }

    func saveLoan(_ loan: Loan) {
        guard let house = currentHousehold() else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.loan)
        request.predicate = NSPredicate(format: "id == %@", loan.id)
        request.fetchLimit = 1
        let obj = (try? viewContext.fetch(request))?.first ?? {
            let new = NSManagedObject(entity: entity(CDModel.loan), insertInto: viewContext)
            new.setValue(loan.id, forKey: "id")
            new.setValue(loan.createdAt, forKey: "createdAt")
            new.setValue(house, forKey: "household")
            assign(new, toStoreOf: house)
            return new
        }()
        obj.setValue(loan.name, forKey: "name")
        obj.setValue(loan.balance, forKey: "balance")
        obj.setValue(loan.rate, forKey: "rate")
        obj.setValue(loan.monthlyPayment, forKey: "monthlyPayment")
        save()
    }

    func deleteLoan(id: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.loan)
        request.predicate = NSPredicate(format: "id == %@", id)
        for obj in (try? viewContext.fetch(request)) ?? [] { viewContext.delete(obj) }
        save()
    }

    private func recurringObject(id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.recurring)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    private func memberObject(id: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.member)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }

    private func entryObjects(memberID: String) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        request.predicate = NSPredicate(format: "memberID == %@", memberID)
        return (try? viewContext.fetch(request)) ?? []
    }

    func delete(id: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.entry)
        request.predicate = NSPredicate(format: "id == %@", id)
        for obj in (try? viewContext.fetch(request)) ?? [] {
            viewContext.delete(obj)
        }
        deleteReactions(entryID: id)
        save()
    }

    /// Sets a cap for one month only. Earlier months keep whatever they were
    /// given; later months inherit this until they're changed themselves.
    func setCap(bucket: String, month: String, amount: Double) {
        guard let house = currentHousehold() else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.cap)
        request.predicate = NSPredicate(format: "bucket == %@ AND month == %@ AND household == %@",
                                        bucket, month, house)
        request.fetchLimit = 1

        let cap = (try? viewContext.fetch(request))?.first ?? {
            let new = NSManagedObject(entity: entity(CDModel.cap), insertInto: viewContext)
            new.setValue(bucket, forKey: "bucket")
            new.setValue(month, forKey: "month")
            new.setValue(house, forKey: "household")
            assign(new, toStoreOf: house)
            return new
        }()

        cap.setValue(amount, forKey: "amount")
        cap.setValue(Date(), forKey: "updatedAt")
        save()
    }

    // MARK: Helpers

    private func entity(_ name: String) -> NSEntityDescription {
        container.managedObjectModel.entitiesByName[name]!
    }

    /// New objects created by the owner land in the private store; a participant's
    /// objects must land in the shared store so they sync back to the owner.
    private func assignToOwnerStore(_ object: NSManagedObject) {
        guard isCloudSyncActive, let privateStore else { return }
        viewContext.assign(object, to: privateStore)
    }

    /// Places a new object in the same store as its household (private for the
    /// owner, shared for a participant). No-op in local mode.
    private func assign(_ object: NSManagedObject, toStoreOf house: NSManagedObject) {
        guard isCloudSyncActive,
              let store = house.objectID.persistentStore else { return }
        viewContext.assign(object, to: store)
    }

    private func save() {
        guard viewContext.hasChanges else { return }
        do { try viewContext.save() }
        catch { assertionFailure("Save failed: \(error)") }
    }
}
