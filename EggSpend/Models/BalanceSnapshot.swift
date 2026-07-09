import SwiftData
import Foundation

/// A once-per-account-per-day record of `Account.balance`, captured on launch by
/// `BalanceSnapshotService`. This is the source of truth for historical net-worth
/// timeline points going forward — it replaces the `NetWorthCalculator.at(date:)`
/// transaction-reversal reconstruction for any day that has a snapshot, so the
/// timeline stays correct even when balances move via unlinked transactions,
/// manual edits, or any path that doesn't leave a reversible transaction trail.
///
/// Design notes (all stored properties are defaulted/optional for CloudKit):
/// - No `@Attribute(.unique)` on `accountID`/`date` — CloudKit does not support
///   unique constraints, so day-uniqueness is enforced in code
///   (`BalanceSnapshotService`), not the schema.
/// - `accountID` is a plain `UUID` copy of `Account.id`, not a `@Relationship`.
///   A relationship with a nullify/cascade delete rule would erase which account
///   a row belonged to (or delete it) when an account is truly deleted (see T7),
///   destroying the historical record. Keeping a detached UUID lets snapshots for
///   deleted accounts persist and simply be excluded on read.
/// - Cross-device CloudKit sync can race and produce more than one row for the
///   same `accountID` + day (e.g. two devices both capture on launch before
///   syncing). This is expected and tolerated on read, not swept/deduplicated on
///   write: readers pick the row with the latest `createdAt` per account/day.
@Model
final class BalanceSnapshot {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var date: Date = Date.now       // normalized to startOfDay at write time
    var balance: Double = 0
    var createdAt: Date = Date.now

    init(accountID: UUID = UUID(), date: Date = .now, balance: Double = 0) {
        self.id = UUID()
        self.accountID = accountID
        self.date = date
        self.balance = balance
        self.createdAt = .now
    }
}
