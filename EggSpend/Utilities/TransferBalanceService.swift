import Foundation

enum TransferBalanceService {
    /// Debits fromAccount and credits toAccount by the transfer's amount.
    /// No-ops on either side if that side's account is nil.
    static func apply(_ transfer: Transfer) {
        transfer.fromAccount?.balance -= transfer.amount
        transfer.toAccount?.balance += transfer.amount
    }

    /// Reverses a previously applied transfer's effect.
    static func reverse(_ transfer: Transfer) {
        transfer.fromAccount?.balance += transfer.amount
        transfer.toAccount?.balance -= transfer.amount
    }
}
