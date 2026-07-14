import Foundation

struct MerchantSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let type: TransactionType
    let category: TransactionCategory?
    let account: Account?
    let frequency: Int
    let mostRecentDate: Date

    static func build(
        from transactions: [Transaction],
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 6
    ) -> [MerchantSuggestion] {
        guard limit > 0 else { return [] }

        let windowStart = calendar.date(byAdding: .day, value: -90, to: referenceDate) ?? referenceDate
        var buckets: [String: [Transaction]] = [:]

        for transaction in transactions {
            guard !transaction.isAdjustment else { continue }
            guard transaction.date >= windowStart, transaction.date <= referenceDate else { continue }
            let key = CSVParser.normalizedTitle(transaction.title)
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(transaction)
        }

        return buckets.compactMap { key, grouped -> MerchantSuggestion? in
            guard let latest = grouped.max(by: { $0.date < $1.date }) else { return nil }
            return MerchantSuggestion(
                id: key,
                title: latest.title.trimmingCharacters(in: .whitespacesAndNewlines),
                type: latest.type,
                category: latest.category,
                account: latest.account,
                frequency: grouped.count,
                mostRecentDate: latest.date
            )
        }
        .sorted {
            if $0.frequency != $1.frequency {
                return $0.frequency > $1.frequency
            }
            return $0.mostRecentDate > $1.mostRecentDate
        }
        .prefix(limit)
        .map { $0 }
    }

    static func matching(
        _ query: String,
        in transactions: [Transaction],
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 6
    ) -> [MerchantSuggestion] {
        let normalizedQuery = CSVParser.normalizedTitle(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return build(
            from: transactions,
            referenceDate: referenceDate,
            calendar: calendar,
            limit: transactions.count
        )
        .filter { $0.id.contains(normalizedQuery) }
        .prefix(limit)
        .map { $0 }
    }
}
