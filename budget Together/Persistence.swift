import CoreData
import CloudKit

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
            attr("name",      .stringAttributeType),
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
            attr("place",      .stringAttributeType),
            attr("bucket",     .stringAttributeType),
            attr("amount",     .doubleAttributeType),
            attr("memberID",   .stringAttributeType),   // CDMember.id of whoever spent it
            attr("memberRole", .stringAttributeType),   // legacy two-person field, migrated on first load
            attr("kind",       .stringAttributeType),   // EntryKind; nil predates income and reads as expense
            attr("mood",       .stringAttributeType),   // Mood; nil means untagged, which is normal
            attr("note",       .stringAttributeType),   // free text; nil and "" are the same thing
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
            attr("reason",    .stringAttributeType),
            attr("updatedAt", .dateAttributeType),
        ]
        // The spending and income categories, which are user data rather than a
        // fixed list. `id` is permanent once written — entries, caps, recurring
        // items and challenges all refer to a category by it.
        category.properties = [
            attr("id",         .stringAttributeType),
            attr("label",      .stringAttributeType),
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
            attr("amount",    .doubleAttributeType),
            attr("month",     .stringAttributeType),      // "yyyy-MM"; nil is the pre-history baseline
            attr("updatedAt", .dateAttributeType),        // used to dedupe conflicting caps
        ]
        member.properties = [
            attr("id",         .stringAttributeType),
            attr("name",       .stringAttributeType),
            attr("colorIndex", .integer64AttributeType),  // index into MemberStyle.all
            attr("createdAt",  .dateAttributeType),       // also the display order
        ]
        recurring.properties = [
            attr("id",              .stringAttributeType),
            attr("place",           .stringAttributeType),
            attr("bucket",          .stringAttributeType),
            attr("amount",          .doubleAttributeType),
            attr("memberID",        .stringAttributeType),
            attr("kind",            .stringAttributeType),
            attr("dayOfMonth",      .integer64AttributeType),
            attr("isActive",        .booleanAttributeType),
            attr("lastPostedMonth", .stringAttributeType),  // "yyyy-MM"; posts once per month
            attr("createdAt",       .dateAttributeType),
        ]
        loan.properties = [
            attr("id",             .stringAttributeType),
            attr("name",           .stringAttributeType),
            attr("balance",        .doubleAttributeType),
            attr("rate",           .doubleAttributeType),    // annual %, 0 for interest-free
            attr("monthlyPayment", .doubleAttributeType),
            attr("createdAt",      .dateAttributeType),
        ]
        challenge.properties = [
            attr("id",        .stringAttributeType),
            attr("title",     .stringAttributeType),
            attr("kind",      .stringAttributeType),   // ChallengeKind
            attr("bucket",    .stringAttributeType),   // nil means all spending
            attr("target",    .doubleAttributeType),
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

    /// Flipped to `true` in Step 3, once the iCloud/CloudKit entitlement and a
    /// provisioned container exist. Until then the app runs on a purely local
    /// store so it works in the simulator without a paid developer account.
    static let cloudSyncEnabled = false

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

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        defaults = inMemory ? nil : .standard
        let model = CDModel.make()
        container = NSPersistentCloudKitContainer(name: "BudgetTogether", managedObjectModel: model)
        configureDescriptions(inMemory: inMemory)

        container.loadPersistentStores { [weak self] desc, error in
            if let error {
                assertionFailure("Failed to load store: \(error)")
                return
            }
            self?.captureStore(for: desc)
        }

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

    private func configureDescriptions(inMemory: Bool) {
        let base = NSPersistentStoreDescription()
        if inMemory {
            base.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [base]
            return
        }

        let support = NSPersistentContainer.defaultDirectoryURL()
        base.url = support.appendingPathComponent("BudgetTogether.private.sqlite")
        base.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        base.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        guard Self.cloudSyncEnabled else {
            // Local-only mode (Step 1/2): single on-disk store, no CloudKit.
            container.persistentStoreDescriptions = [base]
            return
        }

        // CloudKit mode (Step 3+): mirror both the private and shared databases.
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
        privateOptions.databaseScope = .private
        base.cloudKitContainerOptions = privateOptions
        base.configuration = "Default"

        let shared = NSPersistentStoreDescription(url: support.appendingPathComponent("BudgetTogether.shared.sqlite"))
        shared.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        shared.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
        sharedOptions.databaseScope = .shared
        shared.cloudKitContainerOptions = sharedOptions
        shared.configuration = "Default"

        container.persistentStoreDescriptions = [base, shared]
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

    /// The household this device reads/writes. In local mode there is exactly one.
    func currentHousehold() -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: CDModel.household)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? viewContext.fetch(request))?.first
    }

    var hasHousehold: Bool { currentHousehold() != nil }

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
        save()
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
    func loadSnapshot(capsFor month: String = Fmt.isoMonth(Date())) -> Snapshot {
        guard let house = currentHousehold() else { return Snapshot() }

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
                isPrivate: obj.value(forKey: "isPrivate") as? Bool ?? false,
                createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
            )
        }
        return Snapshot(entries: entries,
                        caps: loadCaps(for: house, month: month),
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
            createdAt: obj.value(forKey: "createdAt") as? Date ?? .distantPast
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
                  mood: Mood? = nil, note: String = "", isPrivate: Bool = false,
                  createdAt: Date = Date()) {
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
        guard Self.cloudSyncEnabled else {
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
                     note: String, isPrivate: Bool) {
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
                     isPrivate: isPrivate, createdAt: created)
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
        guard Self.cloudSyncEnabled, let privateStore else { return }
        viewContext.assign(object, to: privateStore)
    }

    /// Places a new object in the same store as its household (private for the
    /// owner, shared for a participant). No-op in local mode.
    private func assign(_ object: NSManagedObject, toStoreOf house: NSManagedObject) {
        guard Self.cloudSyncEnabled,
              let store = house.objectID.persistentStore else { return }
        viewContext.assign(object, to: store)
    }

    private func save() {
        guard viewContext.hasChanges else { return }
        do { try viewContext.save() }
        catch { assertionFailure("Save failed: \(error)") }
    }
}
