import DeclaredAgeRange
import Foundation
import Testing
@testable import Even_Keel

// MARK: - Age checks
//
// The decisions behind the age checks some states require. iOS's own sheets
// can't be driven from a test, so everything that decides whether they appear
// is kept apart from them and tested here instead — against throwaway defaults,
// never the real ones.

@Suite("Age checks")
struct AgeAssuranceTests {

    private let update = SignificantUpdate(id: "chat", build: 9, summary: "Adds chat.")
    private let later = SignificantUpdate(id: "photos", build: 12, summary: "Adds photos.")

    private func freshDefaults() -> UserDefaults {
        let name = "AgeAssuranceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Age bands

    @Test("A range that ends under 18 is a minor, whatever bands the state uses")
    func minors() {
        #expect(AgeBand(lowerBound: nil, upperBound: 17, confirmed: true) == .minor)
        #expect(AgeBand(lowerBound: 13, upperBound: 15, confirmed: false) == .minor)
        #expect(AgeBand(lowerBound: nil, upperBound: 12, confirmed: false) == .minor)
    }

    @Test("A range that starts at 18 is an adult, confirmed or not")
    func adults() {
        #expect(AgeBand(lowerBound: 18, upperBound: nil, confirmed: true) == .adult(confirmed: true))
        #expect(AgeBand(lowerBound: 18, upperBound: nil, confirmed: false) == .adult(confirmed: false))
    }

    @Test("A range that doesn't settle which side of 18 gives no band")
    func unsettled() {
        #expect(AgeBand(lowerBound: nil, upperBound: nil, confirmed: false) == nil)
        #expect(AgeBand(lowerBound: 16, upperBound: 19, confirmed: true) == nil)
    }

    @Test("iOS's rules translate one for one")
    func rulesFromFeatures() {
        guard #available(iOS 26.4, *) else { return }
        #expect(AgeRules(Set<AgeRangeService.RegulatoryFeature>()).apply == false)
        let all = AgeRules([.declaredAgeRangeRequired,
                            .significantAppChangeRequiresParentalConsent,
                            .significantAppChangeRequiresAdultNotification])
        #expect(all == AgeRules(mustAskAge: true, parentsApproveUpdates: true,
                                adultsAreToldOfUpdates: true))
    }

    // MARK: What a pending update needs

    @Test("Where no update rule applies, a pending update just counts as seen")
    func nothingRequired() {
        #expect(AgeAssurance.step(rules: AgeRules(), band: .minor) == .done)
        #expect(AgeAssurance.step(rules: AgeRules(mustAskAge: true), band: nil) == .done)
    }

    @Test("A minor waits for a parent only where parents have to approve")
    func minorsAndParents() {
        let parents = AgeRules(parentsApproveUpdates: true)
        let adultsOnly = AgeRules(adultsAreToldOfUpdates: true)
        #expect(AgeAssurance.step(rules: parents, band: .minor) == .askParent)
        #expect(AgeAssurance.step(rules: adultsOnly, band: .minor) == .done)
    }

    @Test("An adult is shown the change where that's required, after their age is confirmed")
    func adultsAreShown() {
        let both = AgeRules(parentsApproveUpdates: true, adultsAreToldOfUpdates: true)
        #expect(AgeAssurance.step(rules: both, band: .adult(confirmed: true)) == .showAdult)
        #expect(AgeAssurance.step(rules: both, band: .adult(confirmed: false)) == .confirmAgeFirst)
        let parentsOnly = AgeRules(parentsApproveUpdates: true)
        #expect(AgeAssurance.step(rules: parentsOnly, band: .adult(confirmed: false)) == .done)
    }

    @Test("Without a usable age the update stays pending rather than being waved through")
    func noAgeWaits() {
        let both = AgeRules(parentsApproveUpdates: true, adultsAreToldOfUpdates: true)
        #expect(AgeAssurance.step(rules: both, band: nil) == .wait)
    }

    // MARK: Which updates are owed

    @Test("A fresh install starts at the build it downloaded")
    func freshInstallBaseline() {
        #expect(AgeAssurance.baseline(recorded: nil, currentBuild: 12, hasBudget: false) == 12)
    }

    @Test("A device that already had a budget starts before the checks existed")
    func upgradeBaseline() {
        #expect(AgeAssurance.baseline(recorded: nil, currentBuild: 12, hasBudget: true)
                == AgeAssurance.lastBuildWithoutAgeChecks)
        #expect(AgeAssurance.baseline(recorded: 7, currentBuild: 12, hasBudget: true) == 7)
    }

    @Test("Only updates after the baseline, and not yet handled, are pending")
    func pendingFilter() {
        let all = [update, later]
        #expect(AgeAssurance.pending(all, handled: [], baseline: 5) == all)
        #expect(AgeAssurance.pending(all, handled: ["chat"], baseline: 5) == [later])
        #expect(AgeAssurance.pending(all, handled: [], baseline: 9) == [later])
        #expect(AgeAssurance.pending(all, handled: [], baseline: 12).isEmpty)
    }

    @Test("The shipping list is well formed")
    func shippingList() {
        let ids = AgeAssurance.updates.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AgeAssurance.updates.allSatisfy { $0.build > AgeAssurance.lastBuildWithoutAgeChecks })
        #expect(AgeAssurance.updates.allSatisfy { !$0.summary.isEmpty })
    }

    // MARK: Bookkeeping

    @Test("The baseline is recorded once and then kept")
    func baselineRecordedOnce() {
        let assurance = AgeAssurance(defaults: freshDefaults(), updates: [update, later])
        assurance.recordBaselineIfNeeded(currentBuild: 10, hasBudget: false)
        assurance.recordBaselineIfNeeded(currentBuild: 20, hasBudget: true)
        #expect(assurance.pending == [later])
    }

    @Test("A handled update stays handled across launches")
    func handledPersists() {
        let defaults = freshDefaults()
        let first = AgeAssurance(defaults: defaults, updates: [update, later])
        first.recordBaselineIfNeeded(currentBuild: 5, hasBudget: true)
        first.markHandled([update])
        let relaunched = AgeAssurance(defaults: defaults, updates: [update, later])
        #expect(relaunched.pending == [later])
        #expect(relaunched.pendingSummary == "Adds photos.")
    }

    @Test("A parent's approval clears the gate and everything pending")
    func parentApproves() {
        let assurance = AgeAssurance(defaults: freshDefaults(), updates: [update, later])
        assurance.hold(.parent(declined: false))
        assurance.parentAnswered(approved: true)
        #expect(assurance.gate == nil)
        #expect(assurance.pending.isEmpty)
    }

    @Test("A parent's no keeps the gate up and says so")
    func parentDeclines() {
        let assurance = AgeAssurance(defaults: freshDefaults(), updates: [update])
        assurance.hold(.parent(declined: false))
        assurance.parentAnswered(approved: false)
        #expect(assurance.gate == .parent(declined: true))
        #expect(assurance.pending == [update])
    }

    @Test("A stray no with no gate up doesn't put one up")
    func strayDecline() {
        let assurance = AgeAssurance(defaults: freshDefaults(), updates: [update])
        assurance.parentAnswered(approved: false)
        #expect(assurance.gate == nil)
    }

    @Test("The check runs once a launch, unless it didn't finish or is retried")
    func oncePerLaunch() {
        let assurance = AgeAssurance(defaults: freshDefaults(), updates: [])
        #expect(assurance.beginCheck())
        #expect(assurance.beginCheck() == false)
        assurance.checkDidNotFinish()
        #expect(assurance.beginCheck())
        assurance.hold(.confirmAge)
        assurance.retry()
        #expect(assurance.gate == nil)
        #expect(assurance.attempt == 1)
        #expect(assurance.beginCheck())
    }
}
