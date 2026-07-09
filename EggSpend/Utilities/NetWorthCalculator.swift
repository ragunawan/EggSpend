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

    /// Net worth as of `date`. If `snapshots` contains rows for `date`'s calendar day, those
    /// recorded balances are used directly (see below); otherwise falls back to reconstructing
    /// the total from `current(accounts:)` by reversing every transaction dated after `date`
    /// that is linked to a net-worth-counting account (`account?.countsTowardNetWorth == true`).
    /// Only such transactions ever moved a counted balance, so only those are reversible;
    /// unlinked transactions, or ones tied to an excluded liability, never touched the total and
    /// must not be subtracted out.
    ///
    /// Snapshot path: picks the latest-`createdAt` snapshot per `accountID` for that day (tolerates
    /// duplicate rows from cross-device CloudKit sync races — see `BalanceSnapshot`), then sums
    /// only accounts that currently exist and pass `!isArchived && countsTowardNetWorth`; a
    /// snapshot whose `accountID` no longer matches any account (the account was deleted) is
    /// silently excluded. Assets add `balance`; liabilities subtract `abs(balance)`, mirroring
    /// `current(accounts:)`.
    ///
    /// Known limitation: transfers between an included account and an excluded one aren't
    /// represented here (the excluded leg is simply dropped) — filed as a follow-up. Also, the
    /// current `isArchived`/`includeInNetWorth` toggles apply retroactively to snapshot data the
    /// same way they do to reconstruction — archiving an account or flipping `includeInNetWorth`
    /// changes historical timeline points, not just the current total. This is documented v1
    /// behavior consistent with the existing reconstruction semantics above.
    static func at(
        date: Date,
        accounts: [Account],
        transactions: [Transaction],
        snapshots: [BalanceSnapshot] = [],
        calendar: Calendar = .current
    ) -> Double {
        let daySnapshots = snapshots.filter { calendar.isDate($0.date, inSameDayAs: date) }
        if !daySnapshots.isEmpty {
            let latestByAccount = daySnapshots.reduce(into: [UUID: BalanceSnapshot]()) { result, snap in
                if let existing = result[snap.accountID], existing.createdAt >= snap.createdAt { return }
                result[snap.accountID] = snap
            }
            // Duplicate ids are possible under CloudKit sync races (Account.id has
            // no unique constraint, same as BalanceSnapshot); first wins, consistent
            // with the duplicate-tolerant reduce above.
            let accountsByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return latestByAccount.reduce(0.0) { total, entry in
                let (accountID, snap) = entry
                guard let account = accountsByID[accountID],
                      !account.isArchived, account.countsTowardNetWorth else { return total }
                return total + (account.isAsset ? snap.balance : -abs(snap.balance))
            }
        }

        let currentNetWorth = current(accounts: accounts)
        let delta = transactions
            .filter { $0.date > date && !($0.account?.isArchived ?? false) && ($0.account?.countsTowardNetWorth ?? false) }
            .reduce(0.0) { $0 + $1.signedAmount }
        return currentNetWorth - delta
    }
}
