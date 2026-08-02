import Foundation
import UserNotifications

struct TransitionNotification: Equatable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
}

protocol NotificationScheduling {
    func requestAuthorization()

    /// Replaces the pending Focus Rhythm transition set with `notifications`.
    /// Implementations must leave notifications not owned by Focus Rhythm untouched.
    func reconcileTransitionNotifications(_ notifications: [TransitionNotification])
    func cancelTransitionNotifications()
}

final class UNUserNotificationScheduler: NotificationScheduling {
    static let transitionIdentifierPrefix = "focusrhythm.transition."

    private let center: UNUserNotificationCenter
    private let reconciliationLock = NSLock()
    private var reconciliationGeneration = 0

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func reconcileTransitionNotifications(_ notifications: [TransitionNotification]) {
        let futureNotifications = notifications.filter { $0.date.timeIntervalSinceNow > 0 }
        let desiredIdentifiers = Set(futureNotifications.map(\.identifier))
        let generation = nextReconciliationGeneration()

        center.getPendingNotificationRequests { [weak self, center] pendingRequests in
            guard self?.isCurrentReconciliation(generation) == true else { return }
            let staleIdentifiers = pendingRequests
                .map(\.identifier)
                .filter { identifier in
                    identifier.hasPrefix(Self.transitionIdentifierPrefix)
                        && !desiredIdentifiers.contains(identifier)
                }
            if !staleIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
            }

            for notification in futureNotifications {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default

                let interval = notification.date.timeIntervalSinceNow
                guard interval > 0 else { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                center.add(
                    UNNotificationRequest(
                        identifier: notification.identifier,
                        content: content,
                        trigger: trigger
                    )
                )
            }
        }
    }

    func cancelTransitionNotifications() {
        let generation = nextReconciliationGeneration()
        center.getPendingNotificationRequests { [weak self, center] pendingRequests in
            guard self?.isCurrentReconciliation(generation) == true else { return }
            let ownedIdentifiers = pendingRequests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.transitionIdentifierPrefix) }
            guard !ownedIdentifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)
        }
    }

    private func nextReconciliationGeneration() -> Int {
        reconciliationLock.lock()
        defer { reconciliationLock.unlock() }
        reconciliationGeneration += 1
        return reconciliationGeneration
    }

    private func isCurrentReconciliation(_ generation: Int) -> Bool {
        reconciliationLock.lock()
        defer { reconciliationLock.unlock() }
        return reconciliationGeneration == generation
    }
}
