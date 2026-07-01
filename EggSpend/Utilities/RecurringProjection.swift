import Foundation

struct RecurringOccurrence: Identifiable {
    let id: String
    let source: RecurringTransaction
    let dueDate: Date

    var title: String { source.title }
    var amount: Double { source.amount }
    var type: TransactionType { source.type }
    var category: TransactionCategory? { source.category }
    var account: Account? { source.account }
    var notes: String { source.notes }
    var signedAmount: Double { type == .income ? amount : -amount }
}

enum RecurringProjection {
    static func occurrences(
        from items: [RecurringTransaction],
        start: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [RecurringOccurrence] {
        let startOfWindow = calendar.startOfDay(for: start)
        guard let endOfWindow = calendar.date(byAdding: .day, value: days, to: startOfWindow) else {
            return []
        }

        var result: [RecurringOccurrence] = []

        for item in items {
            guard item.isActive else { continue }
            if let endDate = item.endDate, endDate < startOfWindow { continue }

            var cursor = item.nextDueDate
            while cursor < startOfWindow {
                guard let next = nextDate(after: cursor, for: item, calendar: calendar), next > cursor else {
                    break
                }
                cursor = next
            }

            while cursor <= endOfWindow {
                if let endDate = item.endDate, cursor > endDate { break }
                result.append(RecurringOccurrence(
                    id: "\(item.id.uuidString)-\(Int(cursor.timeIntervalSince1970))",
                    source: item,
                    dueDate: cursor
                ))

                guard let next = nextDate(after: cursor, for: item, calendar: calendar), next > cursor else {
                    break
                }
                cursor = next
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.dueDate == rhs.dueDate { return lhs.title < rhs.title }
            return lhs.dueDate < rhs.dueDate
        }
    }

    private static func nextDate(after date: Date, for item: RecurringTransaction, calendar: Calendar) -> Date? {
        calendar.date(
            byAdding: item.frequency.calendarComponent,
            value: item.frequency.calendarValue,
            to: date
        )
    }
}
