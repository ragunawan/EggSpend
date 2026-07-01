import Foundation

/// Criteria for the advanced transaction filter sheet. Kept separate from the
/// free-text search field in `TransactionsListView` so search behavior is unaffected.
struct TransactionFilter: Equatable {
    var type: TransactionType? = nil
    var categoryIDs: Set<UUID> = []
    var accountIDs: Set<UUID> = []
    var startDate: Date? = nil
    var endDate: Date? = nil
    var minAmount: Double? = nil
    var maxAmount: Double? = nil
    var generatedOnly: Bool = false

    /// Whether any criteria beyond the defaults are set.
    var isActive: Bool {
        type != nil
            || !categoryIDs.isEmpty
            || !accountIDs.isEmpty
            || startDate != nil
            || endDate != nil
            || minAmount != nil
            || maxAmount != nil
            || generatedOnly
    }

    /// Number of distinct filter groups currently applied, for a compact badge/summary.
    var activeCount: Int {
        var count = 0
        if type != nil { count += 1 }
        if !categoryIDs.isEmpty { count += 1 }
        if !accountIDs.isEmpty { count += 1 }
        if startDate != nil || endDate != nil { count += 1 }
        if minAmount != nil || maxAmount != nil { count += 1 }
        if generatedOnly { count += 1 }
        return count
    }

    mutating func reset() {
        self = TransactionFilter()
    }

    func matches(_ transaction: Transaction) -> Bool {
        if let type, transaction.type != type {
            return false
        }
        if !categoryIDs.isEmpty {
            guard let categoryID = transaction.category?.id, categoryIDs.contains(categoryID) else {
                return false
            }
        }
        if !accountIDs.isEmpty {
            guard let accountID = transaction.account?.id, accountIDs.contains(accountID) else {
                return false
            }
        }
        if let startDate, transaction.date < Calendar.current.startOfDay(for: startDate) {
            return false
        }
        if let endDate, transaction.date > Calendar.current.endOfDay(for: endDate) {
            return false
        }
        if let minAmount, transaction.amount < minAmount {
            return false
        }
        if let maxAmount, transaction.amount > maxAmount {
            return false
        }
        if generatedOnly && !transaction.isGenerated {
            return false
        }
        return true
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
