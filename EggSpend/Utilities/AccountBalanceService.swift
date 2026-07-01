import Foundation

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
}
