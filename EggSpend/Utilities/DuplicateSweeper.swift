import Foundation
import SwiftData

/// Self-heals duplicate `Transaction` rows created when two devices each
/// materialize the same recurring due date locally before CloudKit sync
/// merges their stores. See `processRecurringTransactions` in
/// `RecurringTransaction.swift` for the generator side: each device runs its
/// own in-process "already generated?" guard against its *local* store only,
/// so two devices can each correctly conclude "not yet generated" and each
/// insert one row for the same `(recurringSourceID, recurringDueDate day)`
/// key — the duplicate only becomes visible once both rows land in one
/// merged store.
///
/// **Why launch-only (v1).** This codebase has no CloudKit remote-change
/// notification plumbing (no `NSPersistentStoreRemoteChange` /
/// `NSPersistentCloudKitContainerEvent` equivalent for SwiftData exists
/// anywhere in the app today), so there is no hook to run the sweep the
/// moment a duplicate arrives mid-session. Running it once at launch is an
/// intentional v1 scope: a duplicate that syncs in mid-session persists
/// until the next launch (or the next call to `processRecurringTransactions`,
/// which also runs from `TransactionsListView.onAppear` — that call
/// materializes new occurrences but does not sweep) before this function
/// runs again and cleans it up. This bound is acceptable because the
/// generator itself only ever appends rows; it never reads a stale count
/// that the sweep would need to correct sooner than "next launch" to avoid
/// compounding.
///
/// **Timezone note.** `calendar.startOfDay(for:)` is evaluated in the
/// calendar's (device) time zone, so a due date sitting near local midnight
/// can bucket differently on devices in different time zones — the exact
/// same limitation `processRecurringTransactions`'s own guard already has
/// (it also compares `recurringDueDate` via `Calendar.current`). This sweep
/// intentionally mirrors that behavior rather than introducing a UTC-based
/// notion of "same day" that would disagree with the generator's own
/// de-dupe check.
///
/// **Residual risk (accepted).** This sweep targets the *out-of-order-sync*
/// race: two devices each apply their own row's effect to the (eventually
/// shared) account balance, so the balance is genuinely double-applied once
/// both rows merge — the sweep's single `reverse` call per removed duplicate
/// corrects that back to one application, exactly. There is a second,
/// narrower race this sweep does *not* perfectly resolve: if both devices
/// happen to compute an *identical* resulting balance independently (e.g.
/// because CloudKit's own record-level merge already reconciled the balance
/// field before this sweep runs, or some other path already left the
/// balance correct despite two rows existing), the sweep still finds two
/// generated rows sharing a key, still deletes the loser, and still calls
/// `reverse` on it — which then over-corrects the balance by one occurrence's
/// amount. This is a bounded, single-occurrence, non-compounding error (it
/// cannot recur for the same duplicate pair since the sweep is idempotent
/// once the group collapses to one row), and is accepted as a known
/// trade-off rather than solved here: distinguishing "balance already
/// correct" from "balance double-applied" would require persisting an
/// explicit application ledger per transaction, which is out of scope for
/// this task. The out-of-order-sync race (balance genuinely double-applied)
/// is the case this sweep is designed to correct and the one exercised by
/// the acceptance test.
enum DuplicateSweeper {
    /// Groups generated recurring transactions by source + due-date day and
    /// removes every row in a group except the earliest-created survivor,
    /// reversing each removed row's balance effect first.
    ///
    /// - Parameters:
    ///   - context: The `ModelContext` to fetch, mutate, and save.
    ///   - calendar: Calendar used for day-granularity grouping. Defaults to
    ///     `.current` to match `processRecurringTransactions`'s own guard.
    /// - Returns: The number of duplicate rows removed.
    @discardableResult
    static func sweep(context: ModelContext, calendar: Calendar = .current) -> Int {
        // Grouping key. Two generated transactions are considered duplicates
        // only when both the recurring source and the due-date day match.
        struct Key: Hashable {
            let sourceID: UUID
            let day: Date
        }

        // Unfiltered fetch + in-memory filter (mirrors the precedent in
        // `processRecurringTransactions`, RecurringTransaction.swift:136-137).
        // Every condition here is load-bearing:
        //   - isGenerated: never touch manually-entered rows.
        //   - !isAdjustment: generated rows are never adjustments in
        //     practice (adjustments are always constructed with
        //     isGenerated: false — see AccountBalanceService.applyBalanceEdit),
        //     so this is provably-redundant defense-in-depth against ever
        //     sweeping a balance-adjustment row.
        //   - recurringSourceID != nil / recurringDueDate != nil: legacy or
        //     incomplete generated rows lacking the key are excluded from
        //     the sweep entirely — they must never be grouped into a shared
        //     "nil bucket", which would delete and reverse unrelated
        //     transactions.
        let allTransactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let candidates = allTransactions.filter {
            $0.isGenerated && !$0.isAdjustment && $0.recurringSourceID != nil && $0.recurringDueDate != nil
        }

        let groups = Dictionary(grouping: candidates) { transaction in
            Key(sourceID: transaction.recurringSourceID!, day: calendar.startOfDay(for: transaction.recurringDueDate!))
        }

        var removedCount = 0

        for (_, members) in groups where members.count > 1 {
            // Deterministic survivor selection: earliest `createdAt`, tied
            // broken by ascending `id.uuidString`. Determinism here is not
            // cosmetic — every device must independently compute the same
            // survivor from the same merged data, or the sweep itself would
            // become a source of cross-device divergence (two devices each
            // deleting the *other* row, disagreeing forever).
            let sorted = members.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let losers = sorted.dropFirst()

            for loser in losers {
                if let account = loser.account {
                    AccountBalanceService.reverse(loser, from: account)
                }
                context.delete(loser)
                removedCount += 1
            }
        }

        guard removedCount > 0 else { return 0 }

        do {
            try context.save()
        } catch {
            print("DuplicateSweeper: failed to save after removing \(removedCount) duplicate(s): \(error)")
        }

        return removedCount
    }
}
