import Combine
import DeclaredAgeRange
import OSLog
import PermissionKit
import SwiftUI

// MARK: - Age checks the law asks for
//
// Texas, Utah and Louisiana now require apps — every app, not just ones with
// something to hide from children — to learn the age category of the people
// using them from the App Store, and to get a parent's approval before a minor
// carries on past a "significant update". Apple carries most of it: the App
// Store confirms ages, takes the parent's consent at download, and refuses to
// launch an app whose consent has been withdrawn. What's left for the app is to
// ask iOS for the age range when told to, and to run the significant-update
// flow when there's an update that needs one.
//
// Everything here is conditional on iOS saying the law applies to this person.
// Everywhere else this file does nothing: no prompt, no sheet, no stored state
// beyond a build number. Where it does apply, the age range comes back as a
// range ("under 18", "18 and over" — or the bands the state sets), never a
// birthdate. It's held in memory for the length of one launch and never
// written, synced or sent; the law asks for the data to be used for this and
// nothing else, and an app with no servers was never going to do otherwise.
//
// What this deliberately doesn't do: change anything for a minor in ordinary
// use. Nothing in a budgeting app is unsuitable for a teenager, and the ones who
// most need one are the ones learning to manage money. The age matters only for
// deciding who has to agree to a significant update.
//
// Where people can't refuse: Apple's docs say that in the regions that require
// this, iOS supplies the range itself and there's no option to decline. So
// there is no "declined, so you're locked out" branch to design. If a decline
// arrives anyway, it's treated like an error — carry on, ask again next launch.

// MARK: Significant updates

/// A release that changes the app enough that, where the law asks for it, a
/// parent has to approve it before a child carries on, or an adult has to be
/// shown what changed.
///
/// What counts is a legal judgement, not a technical one: a change to the age
/// rating, to what data the app keeps or where it goes, or a feature that
/// matters for children (talking to strangers, spending money). A new chart is
/// not one. When in doubt, ask someone qualified before adding an entry.
struct SignificantUpdate: Equatable, Identifiable {
    /// Never reused or renamed. A device remembers which ids it has been
    /// through, so changing one asks everybody again.
    let id: String
    /// The build (`CFBundleVersion`) that first ships the change.
    let build: Int
    /// What changed, in words a parent can decide on. iOS shows it in its own
    /// sheet, without anything from this app around it, so it has to stand
    /// alone.
    let summary: String
}

/// Which side of 18 somebody's shared range puts them.
enum AgeBand: Equatable {
    case minor
    /// `confirmed` when the App Store checked the age (an ID, a card, a
    /// guardian) rather than taking the person's word for it.
    case adult(confirmed: Bool)

    /// `nil` when the range doesn't settle it. A state can impose its own
    /// bands, so the gate this app asks for isn't guaranteed to be the one
    /// that comes back.
    init?(lowerBound: Int?, upperBound: Int?, confirmed: Bool) {
        if let upperBound, upperBound < AgeAssurance.adulthood {
            self = .minor
        } else if let lowerBound, lowerBound >= AgeAssurance.adulthood {
            self = .adult(confirmed: confirmed)
        } else {
            return nil
        }
    }
}

/// What iOS says the law requires for this person, in the app's own terms so
/// the decisions below can be tested without Apple's types.
struct AgeRules: Equatable {
    var mustAskAge = false
    var parentsApproveUpdates = false
    var adultsAreToldOfUpdates = false

    var apply: Bool { mustAskAge || parentsApproveUpdates || adultsAreToldOfUpdates }
}

/// What to do about updates nobody on this device has been through yet.
enum UpdateStep: Equatable {
    /// Nothing the law asks for here. The updates count as seen.
    case done
    /// No usable age to route on. Leave them pending and try next launch.
    case wait
    /// A minor's copy, held until a parent or guardian approves.
    case askParent
    /// An adult who has to be shown the change before carrying on.
    case showAdult
    /// An adult who has to be shown it, but whose age iOS hasn't confirmed —
    /// which the acknowledgement needs first.
    case confirmAgeFirst
}

// MARK: - State

@MainActor
final class AgeAssurance: ObservableObject {
    static let shared = AgeAssurance()

    static let adulthood = 18

    /// The newest build that shipped without these checks. A device that
    /// already had a budget when they arrived started there, so every
    /// significant update after it is still owed — even if the person skipped
    /// the versions in between.
    static let lastBuildWithoutAgeChecks = 5

    /// None yet. See `SignificantUpdate` for what belongs here; `build` must be
    /// the build that ships the change.
    static let updates: [SignificantUpdate] = []

    static let log = Logger(subsystem: "com.evenkeel.app", category: "age")

    /// What's standing in front of the app, if anything.
    enum Gate: Equatable {
        /// A minor waiting on a parent. `declined` once the parent has said no.
        case parent(declined: Bool)
        /// An adult who needs their age confirmed in Settings first.
        case confirmAge
    }

    @Published private(set) var gate: Gate?

    /// Bumped by "Try again", which re-runs the check. See `AgeCheck`.
    @Published private(set) var attempt = 0

    private let defaults: UserDefaults
    private let updates: [SignificantUpdate]

    /// Once a launch is enough. iOS caches the answer, but asking on every
    /// unlock would still be a sheet's worth of churn for no new information.
    private var checkedThisLaunch = false

    private static let handledKey = "ageAssurance.handledUpdates"
    private static let baselineKey = "ageAssurance.baselineBuild"

    /// `updates` is for tests; the app always uses the shipping list.
    init(defaults: UserDefaults = .standard, updates: [SignificantUpdate]? = nil) {
        self.defaults = defaults
        self.updates = updates ?? Self.updates
    }

    // MARK: Decisions

    /// The build this device's people are taken to have agreed to.
    ///
    /// A fresh install agreed to whatever it downloaded — the App Store took
    /// the parent's consent at that point — so it starts at the current build.
    /// A device with a budget already on it was here before these checks
    /// existed, and starts before them.
    static func baseline(recorded: Int?, currentBuild: Int, hasBudget: Bool) -> Int {
        if let recorded { return recorded }
        return hasBudget ? lastBuildWithoutAgeChecks : currentBuild
    }

    static func pending(_ updates: [SignificantUpdate], handled: Set<String>,
                        baseline: Int) -> [SignificantUpdate] {
        updates.filter { $0.build > baseline && !handled.contains($0.id) }
    }

    /// Only asked when something is pending.
    static func step(rules: AgeRules, band: AgeBand?) -> UpdateStep {
        guard rules.parentsApproveUpdates || rules.adultsAreToldOfUpdates else { return .done }
        switch band {
        case nil:
            return .wait
        case .minor:
            return rules.parentsApproveUpdates ? .askParent : .done
        case .adult(let confirmed):
            guard rules.adultsAreToldOfUpdates else { return .done }
            return confirmed ? .showAdult : .confirmAgeFirst
        }
    }

    // MARK: Bookkeeping

    private var handled: Set<String> {
        Set(defaults.stringArray(forKey: Self.handledKey) ?? [])
    }

    private var recordedBaseline: Int? {
        defaults.object(forKey: Self.baselineKey) as? Int
    }

    /// Updates nobody here has been through. Before the baseline is recorded,
    /// assumes the earliest start — over-asking once beats skipping someone.
    var pending: [SignificantUpdate] {
        Self.pending(updates, handled: handled,
                     baseline: recordedBaseline ?? Self.lastBuildWithoutAgeChecks)
    }

    /// The whole of what changed, for iOS to show.
    var pendingSummary: String {
        pending.map(\.summary).joined(separator: " ")
    }

    func recordBaselineIfNeeded(currentBuild: Int, hasBudget: Bool) {
        guard recordedBaseline == nil else { return }
        defaults.set(Self.baseline(recorded: nil, currentBuild: currentBuild, hasBudget: hasBudget),
                     forKey: Self.baselineKey)
    }

    func markHandled(_ done: [SignificantUpdate]) {
        guard !done.isEmpty else { return }
        defaults.set(Array(handled.union(done.map(\.id))).sorted(), forKey: Self.handledKey)
    }

    /// False if the check has already run this launch.
    func beginCheck() -> Bool {
        guard !checkedThisLaunch else { return false }
        checkedThisLaunch = true
        return true
    }

    /// Lets the next appearance try again, after something went wrong.
    func checkDidNotFinish() { checkedThisLaunch = false }

    func hold(_ gate: Gate) { self.gate = gate }

    func retry() {
        checkedThisLaunch = false
        gate = nil
        attempt += 1
    }

    /// A parent's answer, which can arrive at any time — including on a later
    /// launch, before the check has run. An approval covers everything
    /// pending, as it would if they'd been asked about it all at once.
    func parentAnswered(approved: Bool) {
        if approved {
            markHandled(pending)
            gate = nil
        } else if gate != nil {
            gate = .parent(declined: true)
        }
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
}

// MARK: - Asking iOS

@available(iOS 26.4, *)
extension AgeRules {
    init(_ features: Set<AgeRangeService.RegulatoryFeature>) {
        self.init(mustAskAge: features.contains(.declaredAgeRangeRequired),
                  parentsApproveUpdates: features.contains(.significantAppChangeRequiresParentalConsent),
                  adultsAreToldOfUpdates: features.contains(.significantAppChangeRequiresAdultNotification))
    }
}

@available(iOS 26.4, *)
extension AgeBand {
    init?(_ response: AgeRangeService.Response) {
        guard case let .sharing(range) = response else { return nil }
        // Anything but the person's or a guardian's say-so was checked by the
        // App Store. Named this way round so the cases Apple has deprecated in
        // favour of `.confirmed` never have to be spelled out.
        let declaration = range.ageRangeDeclaration
        let confirmed = declaration != nil
            && declaration != .selfDeclared && declaration != .guardianDeclared
        self.init(lowerBound: range.lowerBound, upperBound: range.upperBound,
                  confirmed: confirmed)
    }
}

/// Runs the check and stands the gate up. Lives on the unlocked side of the app
/// lock, so iOS's sheets never appear over the lock screen.
@available(iOS 26.4, *)
private struct AgeCheck: ViewModifier {
    @ObservedObject var assurance: AgeAssurance
    let hasBudget: Bool
    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(\.showSignificantUpdateAcknowledgment) private var showAdult

    func body(content: Content) -> some View {
        Group {
            switch assurance.gate {
            case nil:
                content
            case .parent(let declined):
                ParentApprovalGate(summary: assurance.pendingSummary, declined: declined)
            case .confirmAge:
                ConfirmAgeGate(summary: assurance.pendingSummary) { assurance.retry() }
            }
        }
        .task(id: assurance.attempt) { await check() }
        .task { await listenForParents() }
    }

    private func check() async {
        guard assurance.beginCheck() else { return }

        let rules: AgeRules
        do {
            rules = AgeRules(try await AgeRangeService.shared.requiredRegulatoryFeatures)
        } catch {
            AgeAssurance.log.notice("Couldn't learn the age rules: \(error.localizedDescription, privacy: .public)")
            assurance.checkDidNotFinish()
            return
        }

        // Debug level, and private by default: which rules apply says roughly
        // where somebody is, which is nobody's business in a shipping log.
        AgeAssurance.log.debug("Age rules: \(String(describing: rules))")

        assurance.recordBaselineIfNeeded(currentBuild: AgeAssurance.currentBuild, hasBudget: hasBudget)
        let pending = assurance.pending
        guard rules.apply else {
            // Nobody here has to agree to anything, so nothing is owed later.
            assurance.markHandled(pending)
            return
        }
        guard rules.mustAskAge || !pending.isEmpty else { return }

        var band: AgeBand?
        do {
            band = AgeBand(try await requestAgeRange(ageGates: AgeAssurance.adulthood))
        } catch {
            AgeAssurance.log.notice("Couldn't get an age range: \(error.localizedDescription, privacy: .public)")
        }

        guard !pending.isEmpty else { return }
        switch AgeAssurance.step(rules: rules, band: band) {
        case .done:
            assurance.markHandled(pending)
        case .wait:
            assurance.checkDidNotFinish()
        case .askParent:
            assurance.hold(.parent(declined: false))
        case .showAdult:
            do {
                try await showAdult(updateDescription: assurance.pendingSummary)
                assurance.markHandled(pending)
            } catch {
                AgeAssurance.log.notice("Update acknowledgement didn't complete: \(error.localizedDescription, privacy: .public)")
                assurance.checkDidNotFinish()
            }
        case .confirmAgeFirst:
            assurance.hold(.confirmAge)
        }
    }

    /// The parent answers on their own device, so the reply comes back through
    /// iOS whenever it's given — minutes later, or on a later launch.
    private func listenForParents() async {
        for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
            assurance.parentAnswered(approved: response.choice.answer == .approval)
        }
    }
}

extension View {
    /// The age checks some places require. See `AgeAssurance`.
    ///
    /// Does nothing before iOS 26.4, the first release that can say whether the
    /// law applies to the person at all.
    @ViewBuilder
    func ageChecks(hasBudget: Bool) -> some View {
        if #available(iOS 26.4, *) {
            modifier(AgeCheck(assurance: .shared, hasBudget: hasBudget))
        } else {
            self
        }
    }
}

// MARK: - Gates

/// Stands in front of a minor's app until a parent approves the update.
///
/// Says plainly that nothing has been lost. A teenager locked out of the app
/// they keep their money in will otherwise assume the worst about the money.
@available(iOS 26.4, *)
private struct ParentApprovalGate: View {
    let summary: String
    let declined: Bool
    @State private var question: PermissionQuestion<SignificantAppUpdateTopic>

    init(summary: String, declined: Bool) {
        self.summary = summary
        self.declined = declined
        _question = State(initialValue: PermissionQuestion(
            significantAppUpdateTopic: SignificantAppUpdateTopic(description: summary)))
    }

    var body: some View {
        AgeGateLayout(symbol: "person.2.fill",
                      title: declined ? "Not approved yet" : "This update needs a parent's OK",
                      message: declined
                        ? "Your parent or guardian said no to this update for now. You can ask "
                          + "again. Your budget is still here and nothing has been deleted."
                        : "Even Keel has changed: \(summary) Where you live, the law asks a "
                          + "parent or guardian to approve changes like this before you carry "
                          + "on. Your budget is still here and nothing has been deleted.") {
            PermissionButton(question: question) {
                AgeGateButtonLabel(text: declined ? "Ask again" : "Ask a parent")
            }
        }
    }
}

/// Stands in front of an adult's app when the law needs them shown an update
/// and iOS can't show it until their age is confirmed.
@available(iOS 26.4, *)
private struct ConfirmAgeGate: View {
    let summary: String
    let retry: () -> Void

    var body: some View {
        AgeGateLayout(symbol: "checkmark.shield.fill",
                      title: "Confirm your age to carry on",
                      message: "Even Keel has changed: \(summary) Where you live, the law asks "
                        + "apps to show adults changes like this, and iOS needs your age "
                        + "confirmed first. In Settings, tap your name, then Personal "
                        + "Information, then Age Range for Apps.") {
            Button(action: retry) { AgeGateButtonLabel(text: "Try again") }
                .buttonStyle(.plain)
        }
    }
}

/// The lock screen's shape, so a gate reads as the app pausing rather than
/// the app breaking. Scrolls only when the text is too big to fit.
private struct AgeGateLayout<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        ZStack {
            Palette.screen.ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                VStack(spacing: 0) {
                    Spacer()
                    column
                    Spacer()
                    Spacer()
                }
                ScrollView { column.padding(.vertical, 32) }
            }
        }
    }

    private var column: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .appFont(30, weight: .semibold)
                // Decoration in a fixed tile; past this size the glyph
                // outgrows it, and the text below is what carries the meaning.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Palette.tealInk)
                .frame(width: 74, height: 74)
                .background(Palette.tealGradient,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .appFont(19, weight: .bold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 18)

            Text(message)
                .appFont(12.5)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            action().padding(.top, 24)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct AgeGateButtonLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(14, weight: .bold)
            .foregroundStyle(Palette.tealInk)
            .padding(.horizontal, 30).padding(.vertical, 13)
            .background(Palette.tealGradient,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
