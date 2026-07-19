import Foundation
import UserNotifications

protocol NotificationScheduling {
    func requestAuthorization()

    /// Schedules a local notification for `date`, replacing any previously scheduled
    /// phase-transition notification. No-ops if `date` is not in the future.
    func schedulePhaseTransition(at date: Date, title: String, body: String)

    func cancelPendingPhaseTransition()
}

final class UNUserNotificationScheduler: NotificationScheduling {
    static let phaseTransitionIdentifier = "focusrhythm.phase-transition"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func schedulePhaseTransition(at date: Date, title: String, body: String) {
        cancelPendingPhaseTransition()
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.phaseTransitionIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelPendingPhaseTransition() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.phaseTransitionIdentifier])
    }
}
