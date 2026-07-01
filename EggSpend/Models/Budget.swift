import SwiftData
import Foundation
import SwiftUI

// MARK: - Budget Period

enum BudgetPeriod: String, Codable, CaseIterable {
    case weekly  = "Weekly"
    case monthly = "Monthly"
    case yearly  = "Yearly"

    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly:  return .weekOfYear
        case .monthly: return .month
        case .yearly:  return .year
        }
    }

    var icon: String {
        switch self {
        case .weekly:  return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .yearly:  return "calendar.badge.checkmark"
        }
    }
}

// MARK: - Budget Alert Threshold

enum BudgetAlertThreshold: Int, Comparable {
    case none = 0
    case nearLimit = 80
    case exceeded = 100

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Budget Model

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var limitAmount: Double = 0
    var periodRaw: String = BudgetPeriod.monthly.rawValue
    var isActive: Bool = true
    /// Hex color used when no category is assigned (e.g. "D4820A").
    var colorHex: String = "D4820A"
    var createdAt: Date = Date.now
    var alertsEnabled: Bool = false
    /// Highest BudgetAlertThreshold already notified for `lastAlertedPeriodStart`.
    var lastAlertedThresholdRaw: Int = BudgetAlertThreshold.none.rawValue
    var lastAlertedPeriodStart: Date?

    @Relationship(deleteRule: .nullify)
    var category: TransactionCategory?

    // MARK: Computed wrappers

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    var lastAlertedThreshold: BudgetAlertThreshold {
        get { BudgetAlertThreshold(rawValue: lastAlertedThresholdRaw) ?? .none }
        set { lastAlertedThresholdRaw = newValue.rawValue }
    }

    // MARK: Init

    init(
        name: String,
        limitAmount: Double,
        period: BudgetPeriod = .monthly,
        category: TransactionCategory? = nil,
        colorHex: String = "D4820A"
    ) {
        self.id = UUID()
        self.name = name
        self.limitAmount = abs(limitAmount)
        self.periodRaw = period.rawValue
        self.isActive = true
        self.colorHex = colorHex
        self.createdAt = .now
        self.category = category
    }

    // MARK: Period Helpers

    /// Returns the start and end dates for the current calendar period.
    func currentPeriodRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date.now
        let component = period.calendarComponent

        let start: Date
        let end: Date

        switch period {
        case .weekly:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            end   = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        case .monthly:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            end   = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        case .yearly:
            start = calendar.dateInterval(of: .year, for: now)?.start ?? now
            end   = calendar.date(byAdding: .year, value: 1, to: start) ?? now
        }

        _ = component  // suppress unused-variable warning; component used via switch above
        return (start, end)
    }

    // MARK: Spending Calculations

    /// Total amount spent (expenses only) from `transactions` that fall within
    /// the current period and match this budget's category (if set).
    func spent(from transactions: [Transaction]) -> Double {
        let (start, end) = currentPeriodRange()

        return transactions
            .filter { tx in
                // Must be an expense
                guard tx.type == .expense else { return false }
                // Must fall within the current period
                guard tx.date >= start && tx.date < end else { return false }
                // Category filter: if this budget has a category, match it;
                // if no category is set, this budget covers uncategorised spend.
                if let budgetCategory = category {
                    return tx.category?.id == budgetCategory.id
                } else {
                    return tx.category == nil
                }
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Ratio of spent to limit, clamped to 0 on the lower end (no upper clamp
    /// so callers can detect over-budget scenarios).
    func progress(from transactions: [Transaction]) -> Double {
        guard limitAmount > 0 else { return 0 }
        return max(0, spent(from: transactions) / limitAmount)
    }

    /// Amount remaining (negative when over budget).
    func remaining(from transactions: [Transaction]) -> Double {
        limitAmount - spent(from: transactions)
    }

    /// Days remaining in the current period, counting today. Floored at 1 so
    /// a daily-allowance division on the period's last day stays well-defined.
    func daysRemainingInCurrentPeriod() -> Int {
        let (_, end) = currentPeriodRange()
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: end)
        ).day ?? 1
        return max(days, 1)
    }

    // MARK: Status Color

    /// Returns a semantic color based on a pre-computed progress value (0…∞).
    ///
    /// - 0.0 – 0.7  → `.nestLeafGreen`  (safe)
    /// - 0.7 – 0.9  → `.yolk`           (warning)
    /// - 0.9 – 1.0  → `.twig`           (danger)
    /// - > 1.0      → `.red`            (exceeded)
    func statusColor(progress: Double) -> Color {
        switch progress {
        case ..<0.7:  return .nestLeafGreen
        case ..<0.9:  return .yolk
        case ..<1.0:  return .twig
        default:      return .red
        }
    }

    // MARK: Alert Evaluation

    /// Determines whether a budget-alert notification should fire given `transactions`,
    /// updating `lastAlertedThreshold`/`lastAlertedPeriodStart` to prevent re-firing the
    /// same threshold within the same period. Returns nil if no new alert is warranted.
    /// Callers are responsible for actually presenting/scheduling the notification.
    @discardableResult
    func evaluateAlert(from transactions: [Transaction]) -> BudgetAlertThreshold? {
        guard alertsEnabled, isActive else { return nil }
        let period = currentPeriodRange()

        // Reset alert state if we've rolled into a new period.
        if lastAlertedPeriodStart != period.start {
            lastAlertedThreshold = .none
            lastAlertedPeriodStart = period.start
        }

        let p = progress(from: transactions)
        let crossed: BudgetAlertThreshold = p >= 1.0 ? .exceeded : (p >= 0.8 ? .nearLimit : .none)

        guard crossed != .none, crossed > lastAlertedThreshold else { return nil }
        lastAlertedThreshold = crossed
        return crossed
    }
}
