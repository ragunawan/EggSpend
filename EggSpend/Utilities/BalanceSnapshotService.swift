import Foundation
import SwiftData

/// Captures one `BalanceSnapshot` per account per calendar day. Called once on
/// launch (and on scene-phase reactivation) after account balances for that
/// session have settled, so the historical timeline in `NetWorthCalculator.at`
/// can read exact recorded balances instead of reconstructing them.
enum BalanceSnapshotService {
    /// Writes a snapshot row for every account for `date`'s calendar day, unless
    /// one already exists and is unchanged.
    ///
    /// - If a row already exists for an account/day: updates its `balance` in
    ///   place if it differs (self-healing — the last capture each day wins).
    /// - Otherwise: inserts a new row dated to the start of that day.
    ///
    /// - Parameters:
    ///   - accounts: All accounts to capture a balance for.
    ///   - context:  The `ModelContext` used to fetch existing rows, insert new
    ///     ones, and save.
    ///   - date:     Injectable "now" so day rollover is testable without
    ///     waiting for midnight.
    ///   - calendar: Injectable calendar for the same reason.
    /// - Returns: The number of snapshot rows written (created or updated).
    @discardableResult
    static func captureIfNeeded(
        accounts: [Account],
        context: ModelContext,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let day = calendar.startOfDay(for: date)

        let allSnapshots = (try? context.fetch(FetchDescriptor<BalanceSnapshot>())) ?? []
        let todaysSnapshots = allSnapshots.filter { calendar.isDate($0.date, inSameDayAs: day) }
        // Uniquing keeps the first row per account for today; duplicate rows from
        // cross-device sync races are a tolerated read-time condition (see
        // BalanceSnapshot's doc comment), not something this write path sweeps.
        let existingByAccount = Dictionary(
            todaysSnapshots.map { ($0.accountID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var written = 0
        for account in accounts {
            if let existing = existingByAccount[account.id] {
                if existing.balance != account.balance {
                    existing.balance = account.balance
                    written += 1
                }
            } else {
                let snapshot = BalanceSnapshot(accountID: account.id, date: day, balance: account.balance)
                context.insert(snapshot)
                written += 1
            }
        }

        if written > 0 {
            do {
                try context.save()
            } catch {
                print("BalanceSnapshotService: failed to save snapshots: \(error)")
            }
        }
        return written
    }
}
