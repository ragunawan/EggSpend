import Foundation

/// Single source of truth for net-worth math.
///
/// Invariants:
/// - Assets ALWAYS count toward net worth; `includeInNetWorth` never excludes an
///   asset (see `Account.countsTowardNetWorth`). Only liabilities respect the
///   `includeInNetWorth` toggle.
/// - Liability balances are stored as negative values; both `current` and
///   `totals` treat them via `abs(balance)` so a debt always reduces net worth.
enum NetWorthCalculator {
    /// Net worth = included account balances, with liabilities subtracted.
    static func current(accounts: [Account]) -> Double {
        accounts.reduce(0) { total, account in
            guard !account.isArchived, account.countsTowardNetWorth else { return total }
            return total + (account.isAsset ? account.balance : -abs(account.balance))
        }
    }

    /// Positive asset and liability magnitudes for summary/chart displays.
    /// `assets` sums every asset account; `liabilities` sums `abs(balance)`
    /// over liability accounts where `includeInNetWorth == true`. Archived
    /// accounts are excluded from both.
    static func totals(accounts: [Account]) -> (assets: Double, liabilities: Double) {
        let active = accounts.filter { !$0.isArchived }
        let assets = active.filter(\.isAsset).reduce(0) { $0 + $1.balance }
        let liabilities = active
            .filter { $0.isLiability && $0.includeInNetWorth }
            .reduce(0) { $0 + abs($1.balance) }
        return (assets, liabilities)
    }

    /// Reconstructs net worth as of `date` by starting from `current(accounts:)` and reversing
    /// every transaction dated after `date` that is linked to a net-worth-counting account
    /// (`account?.countsTowardNetWorth == true`). Only such transactions ever moved a counted
    /// balance, so only those are reversible; unlinked transactions, or ones tied to an excluded
    /// liability, never touched the total and must not be subtracted out.
    ///
    /// Known limitation: transfers between an included account and an excluded one aren't
    /// represented here (the excluded leg is simply dropped) — filed as a follow-up.
    static func at(date: Date, accounts: [Account], transactions: [Transaction]) -> Double {
        let currentNetWorth = current(accounts: accounts)
        let delta = transactions
            .filter { $0.date > date && !($0.account?.isArchived ?? false) && ($0.account?.countsTowardNetWorth ?? false) }
            .reduce(0.0) { $0 + $1.signedAmount }
        return currentNetWorth - delta
    }
}
