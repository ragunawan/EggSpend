import Foundation
import SwiftData

enum AccountBalanceService {
    /// Applies the signed effect of a transaction to an account's balance.
    /// Income increases balance; expense decreases it — for both asset and liability types.
    /// No-ops if account is nil.
    static func apply(_ transaction: Transaction, to account: Account?) {
        guard let account else { return }
        account.balance += transaction.signedAmount
    }

    /// Reverses a previously applied transaction's effect from an account's balance.
    /// No-ops if account is nil.
    static func reverse(_ transaction: Transaction, from account: Account?) {
        guard let account else { return }
        account.balance -= transaction.signedAmount
    }

    /// Creates and applies a "Balance adjustment" transaction if newBalance differs from
    /// oldBalance; no-ops (returns nil, no mutation) if equal within a half-cent epsilon.
    /// Callers must pass oldBalance captured BEFORE any balance mutation this save cycle.
    @discardableResult
    static func applyBalanceEdit(oldBalance: Double, newBalance: Double, to account: Account, context: ModelContext) -> Transaction? {
        let delta = newBalance - oldBalance
        guard abs(delta) >= 0.005 else { return nil }
        let tx = Transaction(
            title: "Balance adjustment",
            amount: abs(delta),
            type: delta > 0 ? .income : .expense,
            category: nil,
            account: account,
            isGenerated: false,
            isAdjustment: true
        )
        context.insert(tx)
        apply(tx, to: account)
        return tx
    }
}
