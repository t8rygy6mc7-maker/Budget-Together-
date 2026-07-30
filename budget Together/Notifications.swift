import Foundation
import UserNotifications

// MARK: - Local notifications
//
// Two jobs: warn when a category crosses its cap, and remind before a recurring
// bill lands. Everything here is local — no server, no push entitlement.

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Fractions of a limit worth interrupting someone for.
    static let thresholds: [Double] = [0.8, 1.0]

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    /// Whether the user has been asked yet. Asking on every launch is worse
    /// than not asking at all.
    private static let askedKey = "notificationsRequested"
    private static let firedPrefix = "capAlert."
    private static let billPrefix = "bill."
    private static let alertsOnKey = "limitAlertsEnabled"
    private static let mutedPrefix = "limitAlertMuted."

    private var authorized = false
    private var billReminderTask: Task<Void, Never>?

    // MARK: Preferences
    //
    // Alerts used to be on for everything, automatically, from the first
    // launch. A push that says a category is over budget is the app's loudest
    // possible voice, and it was being used for the app's least welcome
    // message, unprompted. Now it's off until asked for, and mutable per
    // category — the categories people most want to be quiet about (health,
    // say) are exactly the ones an unsolicited alert lands worst on.

    /// Master switch. Off until the user turns it on.
    var limitAlertsEnabled: Bool {
        get { defaults.bool(forKey: Self.alertsOnKey) }
        set { defaults.set(newValue, forKey: Self.alertsOnKey) }
    }

    func isMuted(_ bucketID: String) -> Bool {
        defaults.bool(forKey: Self.mutedPrefix + bucketID)
    }

    func setMuted(_ muted: Bool, for bucketID: String) {
        defaults.set(muted, forKey: Self.mutedPrefix + bucketID)
    }

    /// Refreshes `authorized`. Deliberately does **not** request permission —
    /// that now happens only when the user switches alerts on themselves, so
    /// the system prompt arrives attached to something they asked for.
    func start() {
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    private func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorized = true
        default: authorized = false
        }
    }

    /// Asks the system for permission, in response to the user turning alerts
    /// on. Returns whether it was granted, so the toggle can fall back rather
    /// than sit there claiming to be on.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            defaults.set(true, forKey: Self.askedKey)
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            await refreshAuthorization()
        }
        return authorized
    }

    // MARK: Limit alerts

    /// Fires once per bucket, per month, per threshold. Called after every
    /// reload, so spending that arrives from a partner's device counts too.
    func checkCaps(totals: [String: Double], caps: [String: Double], month: String) {
        guard authorized, limitAlertsEnabled else { return }
        for (bucketID, spent) in totals {
            guard let cap = caps[bucketID], cap > 0, !isMuted(bucketID) else { continue }
            let ratio = spent / cap
            // Highest crossed threshold only — one alert, not a burst.
            guard let crossed = Self.thresholds.filter({ ratio >= $0 }).max() else { continue }

            let key = "\(Self.firedPrefix)\(month).\(bucketID).\(Int(crossed * 100))"
            guard !defaults.bool(forKey: key) else { continue }
            defaults.set(true, forKey: key)

            let copy = Copy.limitAlert(bucket: Bucket.named(bucketID).label,
                                       spent: spent, limit: cap)
            post(id: key, title: copy.title, body: copy.body)
        }
    }

    /// Clears a month's fired flags — used when a cap is raised, so the new
    /// headroom can alert again on its own terms.
    func resetCapAlerts(bucketID: String, month: String) {
        for threshold in Self.thresholds {
            defaults.removeObject(forKey: "\(Self.firedPrefix)\(month).\(bucketID).\(Int(threshold * 100))")
        }
    }

    // MARK: Bill reminders

    /// Reschedules every reminder from scratch — simpler than diffing, and the
    /// list is small.
    func scheduleBillReminders(_ bills: [Recurring], daysBefore: Int = 2) {
        // Reading the pending requests is asynchronous. Keep clearing and
        // adding in one task so a late clear cannot remove reminders that this
        // invocation has just added; a newer request supersedes an older one.
        billReminderTask?.cancel()
        billReminderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let requests = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(Self.billPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard authorized else { return }

            for bill in bills where bill.isActive && bill.kind == .expense {
                // Fire `daysBefore` ahead, wrapping into the previous month when
                // that lands before the 1st.
                var day = bill.dayOfMonth - daysBefore
                if day < 1 { day += 28 }

                var components = DateComponents()
                components.day = min(day, 28)
                components.hour = 9

                let content = UNMutableNotificationContent()
                content.title = "\(bill.place) is due soon"
                content.body = "\(Fmt.money(bill.amount)) on day \(bill.dayOfMonth) of the month."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                try? await center.add(UNNotificationRequest(identifier: Self.billPrefix + bill.id,
                                                            content: content, trigger: trigger))
            }
        }
    }

    // MARK: Plumbing

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A tiny delay lets the triggering write settle before the banner.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Banners while the app is open too — the alert is worth seeing mid-session,
    /// which is exactly when someone is logging spending.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
