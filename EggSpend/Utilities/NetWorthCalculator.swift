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
            guard account.countsTowardNetWorth else { return total }
            return total + (account.isAsset ? account.balance : -abs(account.balance))
        }
    }

    /// Positive asset and liability magnitudes for summary/chart displays.
    /// `assets` sums every asset account; `liabilities` sums `abs(balance)`
    /// over liability accounts where `includeInNetWorth == true`.
    static func totals(accounts: [Account]) -> (assets: Double, liabilities: Double) {
        let assets = accounts.filter(\.isAsset).reduce(0) { $0 + $1.balance }
        let liabilities = accounts
            .filter { $0.isLiability && $0.includeInNetWorth }
            .reduce(0) { $0 + abs($1.balance) }
        return (assets, liabilities)
    }
}
