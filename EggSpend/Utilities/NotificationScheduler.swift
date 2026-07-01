import Foundation
import UserNotifications

// MARK: - Notification Center Protocol

/// Abstracts the subset of UNUserNotificationCenter used by EggSpend so business
/// logic can be tested without touching the real notification center.
protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler: (@Sendable (Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func getAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void)
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        requestAuthorization(options: options, completionHandler: completion)
    }

    func getAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        getNotificationSettings { completion($0.authorizationStatus) }
    }
}

// MARK: - Notification Scheduler

enum NotificationScheduler {

    // MARK: Identifiers

    static func billReminderIdentifier(for recurringID: UUID) -> String {
        "bill-reminder-\(recurringID.uuidString)"
    }

    static func budgetAlertIdentifier(for budgetID: UUID, threshold: BudgetAlertThreshold) -> String {
        "budget-alert-\(budgetID.uuidString)-\(threshold.rawValue)"
    }

    // MARK: Permission

    /// Requests notification permission if not already determined. Call this only
    /// from a user-initiated toggle, never proactively on launch.
    static func requestAuthorizationIfNeeded(
        center: NotificationCenterProtocol = UNUserNotificationCenter.current(),
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        center.getAuthorizationStatus { status in
            switch status {
            case .authorized, .provisional:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            default:
                completion(false)
            }
        }
    }

    // MARK: Bill Reminders

    /// The date this reminder should fire on, or nil if no reminder should be scheduled
    /// (disabled, inactive, past end date, or the computed fire date is already in the past).
    static func reminderFireDate(for item: RecurringTransaction, now: Date = .now) -> Date? {
        guard item.reminderEnabled, item.isActive else { return nil }
        if let end = item.endDate, item.nextDueDate > end { return nil }
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -item.reminderDaysBefore, to: item.nextDueDate
        ) else { return nil }
        return fireDate > now ? fireDate : nil
    }

    /// Builds the notification content + request for a bill reminder. Pure, no side effects.
    static func billReminderRequest(for item: RecurringTransaction, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming: \(item.title)"
        content.body = "\(item.amount.formatted(.currency(code: "USD"))) due \(item.nextDueDate.formatted(date: .abbreviated, time: .omitted))"
        content.sound = .default
        content.userInfo = ["recurringTransactionID": item.id.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(
            identifier: billReminderIdentifier(for: item.id),
            content: content,
            trigger: trigger
        )
    }

    /// Cancels then (if still eligible) reschedules the reminder for one RecurringTransaction.
    /// Call this after insert, edit, delete-intent, deactivation, or nextDueDate advancement.
    static func syncReminder(
        for item: RecurringTransaction,
        center: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        let id = billReminderIdentifier(for: item.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let fireDate = reminderFireDate(for: item) else { return }
        center.add(billReminderRequest(for: item, fireDate: fireDate), withCompletionHandler: nil)
    }

    /// Cancels a reminder outright (item deleted).
    static func cancelReminder(
        for itemID: UUID,
        center: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [billReminderIdentifier(for: itemID)])
    }

    // MARK: Budget Alerts

    /// Builds notification content for a budget crossing a threshold. Pure, no side effects.
    static func budgetAlertContent(for budget: Budget, threshold: BudgetAlertThreshold, progress: Double) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch threshold {
        case .nearLimit:
            content.title = "Nearing Budget Limit"
            content.body = "\(budget.name) is at \(Int(progress * 100))% of its \(budget.period.rawValue.lowercased()) limit."
        case .exceeded:
            content.title = "Budget Exceeded"
            content.body = "\(budget.name) has gone over its \(budget.period.rawValue.lowercased()) limit."
        case .none:
            break
        }
        content.sound = .default
        content.userInfo = ["budgetID": budget.id.uuidString]
        return content
    }

    /// Fires an immediate local notification for a budget crossing a threshold.
    static func fireBudgetAlert(
        for budget: Budget,
        threshold: BudgetAlertThreshold,
        progress: Double,
        center: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        guard threshold != .none else { return }
        let content = budgetAlertContent(for: budget, threshold: threshold, progress: progress)
        let request = UNNotificationRequest(
            identifier: budgetAlertIdentifier(for: budget.id, threshold: threshold),
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}

// MARK: - Foreground Presentation

/// Presents local notifications as banners even while the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
