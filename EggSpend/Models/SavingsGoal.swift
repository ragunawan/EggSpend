import SwiftData
import Foundation
import SwiftUI

// MARK: - Savings Goal Status

enum SavingsGoalStatus: String, Codable, CaseIterable {
    case active    = "Active"
    case completed = "Completed"

    var icon: String {
        switch self {
        case .active:    return "target"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

// MARK: - Savings Goal Model

@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var targetAmount: Double = 0
    /// Manually-entered progress amount. Only meaningful when `linkedAccount`
    /// is nil — once an account is linked, `currentAmount` is derived from the
    /// account's live balance instead and this value is ignored.
    var manualCurrentAmount: Double = 0
    var targetDate: Date?
    var notes: String = ""
    var colorHex: String = "D4820A"
    var icon: String = "leaf.fill"
    var createdAt: Date = Date.now
    var statusRaw: String = SavingsGoalStatus.active.rawValue

    @Relationship(deleteRule: .nullify)
    var linkedAccount: Account?

    // MARK: Computed wrappers

    var status: SavingsGoalStatus {
        get { SavingsGoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }
    var isActive: Bool { status == .active }

    // MARK: Init

    init(
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0,
        targetDate: Date? = nil,
        linkedAccount: Account? = nil,
        notes: String = "",
        colorHex: String = "D4820A",
        icon: String = "leaf.fill",
        status: SavingsGoalStatus = .active
    ) {
        self.id = UUID()
        self.name = name
        self.targetAmount = abs(targetAmount)
        self.manualCurrentAmount = max(0, currentAmount)
        self.targetDate = targetDate
        self.linkedAccount = linkedAccount
        self.notes = notes
        self.colorHex = colorHex
        self.icon = icon
        self.createdAt = .now
        self.statusRaw = status.rawValue
    }

    // MARK: Progress

    /// Whether progress is derived from a linked account's balance rather than
    /// manual entry.
    var tracksLinkedAccount: Bool { linkedAccount != nil }

    /// Current saved amount. Derived from the linked account's balance (clamped
    /// at 0, since a savings goal can't usefully reflect a negative/debt
    /// balance) when one is linked; otherwise the manually entered amount.
    var currentAmount: Double {
        if let linkedAccount {
            return max(0, linkedAccount.balance)
        }
        return manualCurrentAmount
    }

    /// Ratio of saved to target, clamped to 0...1 for display purposes.
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(currentAmount / targetAmount, 0), 1.0)
    }

    var remainingAmount: Double {
        max(0, targetAmount - currentAmount)
    }

    var isGoalMet: Bool {
        targetAmount > 0 && currentAmount >= targetAmount
    }

    /// Days until `targetDate`; negative when the date has passed. Nil when no
    /// target date is set.
    var daysRemaining: Int? {
        guard let targetDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: targetDate)
        ).day
    }

    var isOverdue: Bool {
        guard let daysRemaining, status == .active else { return false }
        return daysRemaining < 0
    }

    var statusColor: Color {
        if isCompleted { return .nestLeafGreen }
        if isOverdue { return .red }
        switch progress {
        case ..<0.34: return .eggBlue
        case ..<0.7:  return .yolk
        default:      return .nestLeafGreen
        }
    }
}
