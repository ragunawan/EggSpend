import SwiftData
import Foundation

// MARK: - Recurrence Frequency

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case daily     = "Daily"
    case weekly    = "Weekly"
    case biweekly  = "Biweekly"
    case monthly   = "Monthly"
    case yearly    = "Yearly"

    var icon: String {
        switch self {
        case .daily:    return "sun.max"
        case .weekly:   return "calendar.badge.clock"
        case .biweekly: return "calendar.badge.plus"
        case .monthly:  return "calendar"
        case .yearly:   return "calendar.badge.checkmark"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily:             return .day
        case .weekly, .biweekly: return .weekOfYear
        case .monthly:           return .month
        case .yearly:            return .year
        }
    }

    /// Number of `calendarComponent` units to advance per recurrence.
    /// Biweekly advances by 2 weeks; all others advance by 1.
    var calendarValue: Int {
        switch self {
        case .biweekly: return 2
        default:        return 1
        }
    }
}

// MARK: - RecurringTransaction Model

@Model
final class RecurringTransaction {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var typeRaw: String = TransactionType.expense.rawValue
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    var startDate: Date = Date.now
    var nextDueDate: Date = Date.now
    var endDate: Date?
    var notes: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify)
    var category: TransactionCategory?

    // MARK: Computed Wrappers

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    // MARK: Init

    init(
        title: String,
        amount: Double,
        type: TransactionType,
        frequency: RecurrenceFrequency = .monthly,
        startDate: Date = .now,
        category: TransactionCategory? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.amount = abs(amount)
        self.typeRaw = type.rawValue
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.nextDueDate = startDate
        self.endDate = nil
        self.notes = notes
        self.isActive = true
        self.createdAt = .now
        self.category = category
    }

    // MARK: Date Advancement

    /// Advances `nextDueDate` by one frequency period using the calendar.
    func advanceNextDueDate() {
        let calendar = Calendar.current
        let advanced = calendar.date(
            byAdding: frequency.calendarComponent,
            value: frequency.calendarValue,
            to: nextDueDate
        ) ?? nextDueDate
        nextDueDate = advanced
    }
}

// MARK: - Process Recurring Transactions

/// Iterates over `items`, generates a `Transaction` for every overdue due date
/// (up to today), advances `nextDueDate` accordingly, and saves the context.
///
/// - Parameters:
///   - items:   All `RecurringTransaction` instances to evaluate.
///   - context: The `ModelContext` used to insert generated transactions and save.
func processRecurringTransactions(
    _ items: [RecurringTransaction],
    context: ModelContext
) {
    let now = Date.now

    for item in items {
        // Skip inactive items or those whose end date has passed.
        guard item.isActive else { continue }
        if let end = item.endDate, end < now { continue }

        // Generate one Transaction for each overdue due date.
        while item.nextDueDate <= now {
            // Don't generate past the end date.
            if let end = item.endDate, item.nextDueDate > end { break }

            let transaction = Transaction(
                title: item.title,
                amount: item.amount,
                date: item.nextDueDate,
                type: item.type,
                category: item.category,
                notes: item.notes.isEmpty
                    ? "Auto-generated from recurring: \(item.title)"
                    : item.notes,
                isGenerated: true
            )
            context.insert(transaction)
            item.advanceNextDueDate()
        }
    }

    do {
        try context.save()
    } catch {
        // Surface the error to the console; callers can add additional
        // error-handling if required.
        print("RecurringTransaction processing failed to save: \(error)")
    }
}
