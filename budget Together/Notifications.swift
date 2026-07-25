import Foundation
import UserNotifications

// MARK: - Local notifications
//
// Two jobs: warn when a category crosses its cap, and remind before a recurring
// bill lands. Everything here is local — no server, no push entitlement.

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Fractions of a cap worth interrupting someone for.
    static let thresholds: [Double] = [0.8, 1.0]

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    /// Whether the user has been asked yet. Asking on every launch is worse
    /// than not asking at all.
    private static let askedKey = "notificationsRequested"
    private static let firedPrefix = "capAlert."
    private static let billPrefix = "bill."

    private var authorized = false

    /// Requests permission the first time, and refreshes `authorized` after.
    func start() {
        center.delegate = self
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                guard !defaults.bool(forKey: Self.askedKey) else { return }
                defaults.set(true, forKey: Self.askedKey)
                authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            case .authorized, .provisional, .ephemeral:
                authorized = true
            default:
                authorized = false
            }
        }
    }

    // MARK: Cap alerts

    /// Fires once per bucket, per month, per threshold. Called after every
    /// reload, so spending that arrives from a partner's device counts too.
    func checkCaps(totals: [String: Double], caps: [String: Double], month: String) {
        guard authorized else { return }
        for (bucketID, spent) in totals {
            guard let cap = caps[bucketID], cap > 0 else { continue }
            let ratio = spent / cap
            // Highest crossed threshold only — one alert, not a burst.
            guard let crossed = Self.thresholds.filter({ ratio >= $0 }).max() else { continue }

            let key = "\(Self.firedPrefix)\(month).\(bucketID).\(Int(crossed * 100))"
            guard !defaults.bool(forKey: key) else { continue }
            defaults.set(true, forKey: key)

            let bucket = Bucket.named(bucketID)
            let title = crossed >= 1 ? "\(bucket.label) is over budget"
                                     : "\(bucket.label) is at \(Int(ratio * 100))%"
            let body = crossed >= 1
                ? "\(Fmt.money(spent)) spent of a \(Fmt.money(cap)) cap — over by \(Fmt.money(spent - cap))."
                : "\(Fmt.money(spent)) of \(Fmt.money(cap)) used, \(Fmt.money(cap - spent)) left."
            post(id: key, title: title, body: body)
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
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(Self.billPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)
        }
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
            center.add(UNNotificationRequest(identifier: Self.billPrefix + bill.id,
                                             content: content, trigger: trigger))
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
