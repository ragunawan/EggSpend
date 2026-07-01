import Foundation
import SwiftData
import UserNotifications

enum BudgetAlertCoordinator {
    /// Evaluates every active, alert-enabled budget against the current transaction set
    /// and fires notifications for any that just crossed a new threshold. Call this after
    /// any transaction mutation (insert/edit/delete) that could move a budget's spend.
    static func checkBudgets(
        _ budgets: [Budget],
        transactions: [Transaction],
        center: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        for budget in budgets where budget.alertsEnabled && budget.isActive {
            if let threshold = budget.evaluateAlert(from: transactions) {
                NotificationScheduler.fireBudgetAlert(
                    for: budget,
                    threshold: threshold,
                    progress: budget.progress(from: transactions),
                    center: center
                )
            }
        }
    }

    /// Convenience overload: fetches active, alert-enabled budgets + all transactions from
    /// `context` and checks them. Use from call sites where a [Budget]/[Transaction] array
    /// isn't already at hand.
    static func checkBudgets(
        context: ModelContext,
        center: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.isActive && $0.alertsEnabled }
        ))) ?? []
        guard !budgets.isEmpty else { return }
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        checkBudgets(budgets, transactions: transactions, center: center)
    }
}
