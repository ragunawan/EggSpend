import Foundation

/// Applies a transfer's amount toward the manually-tracked progress of the
/// savings goal it's tagged with, mirroring `TransferBalanceService`'s
/// apply/reverse pairing.
///
/// No-ops when the transfer isn't tagged with a goal, or when that goal
/// tracks a linked account instead of manual entry — that goal's progress
/// already comes live from the account balance, so crediting it again here
/// would double-count.
enum SavingsGoalContributionService {
    static func apply(_ transfer: Transfer) {
        guard let goal = transfer.savingsGoal, !goal.tracksLinkedAccount else { return }
        goal.manualCurrentAmount += transfer.amount
    }

    static func reverse(_ transfer: Transfer) {
        guard let goal = transfer.savingsGoal, !goal.tracksLinkedAccount else { return }
        goal.manualCurrentAmount = max(0, goal.manualCurrentAmount - transfer.amount)
    }
}
