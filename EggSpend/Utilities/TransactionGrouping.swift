import Foundation

/// Groups ledger rows by calendar day for section-header display.
enum TransactionGrouping {
    /// Buckets `rows` by `Calendar.startOfDay`, sorted with the most recent day first.
    ///
    /// Replaces the old string-keyed grouping path (formatted-date dictionary keys plus
    /// a linear `rows.first` re-scan per sort comparison) with a single `Dictionary(grouping:)`
    /// pass over `rows` followed by a direct key sort: O(n + d log d) where `d` is the number
    /// of distinct days, versus the old approach's effectively O(n·k·log k) behavior.
    ///
    /// `Dictionary(grouping:)` preserves each bucket's rows in their original relative order,
    /// so callers that pass rows pre-sorted descending by exact timestamp keep that
    /// within-day ordering in the output.
    ///
    /// Days are sorted descending (newest first) to match the ledger's newest-first
    /// convention (the inverse of `RecurringNext30DaysView`'s ascending "upcoming" sort).
    static func groupByDay(
        _ rows: [LedgerRow],
        calendar: Calendar = .current
    ) -> [(day: Date, rows: [LedgerRow])] {
        Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, rows: $0.value) }
    }
}
