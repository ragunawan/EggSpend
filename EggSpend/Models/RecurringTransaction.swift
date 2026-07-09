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
    var reminderEnabled: Bool = false
    var reminderDaysBefore: Int = 1

    @Relationship(deleteRule: .nullify)
    var category: TransactionCategory?

    @Relationship(deleteRule: .nullify)
    var account: Account?

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
        account: Account? = nil,
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
        self.account = account
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
/// - Returns: `true` if the generated transactions (if any) were saved successfully,
///   `false` if the save failed. Launch-time failures currently surface via a console
///   log only; a user-facing banner is a future enhancement.
@discardableResult
func processRecurringTransactions(
    _ items: [RecurringTransaction],
    context: ModelContext
) -> Bool {
    let now = Date.now
    let existingGenerated = (try? context.fetch(FetchDescriptor<Transaction>()))?
        .filter { $0.isGenerated && $0.recurringSourceID != nil && $0.recurringDueDate != nil } ?? []

    for item in items {
        // Skip inactive items. Items whose end date has passed are still
        // processed below so any final un-generated occurrence on/before the
        // end date is still materialized; the per-occurrence check below
        // stops the loop once nextDueDate exceeds the end date.
        guard item.isActive else { continue }

        // Generate one Transaction for each overdue due date.
        while item.nextDueDate <= now {
            // Don't generate past the end date.
            if let end = item.endDate, item.nextDueDate > end { break }

            let dueDate = item.nextDueDate
            let alreadyGenerated = existingGenerated.contains { transaction in
                transaction.recurringSourceID == item.id
                    && transaction.recurringDueDate.map { Calendar.current.isDate($0, inSameDayAs: dueDate) } == true
            }

            if !alreadyGenerated {
                let transaction = Transaction(
                    title: item.title,
                    amount: item.amount,
                    date: dueDate,
                    type: item.type,
                    category: item.category,
                    account: item.account,
                    notes: item.notes.isEmpty
                        ? "Auto-generated from recurring: \(item.title)"
                        : item.notes,
                    isGenerated: true,
                    recurringSourceID: item.id,
                    recurringDueDate: dueDate
                )
                context.insert(transaction)
                AccountBalanceService.apply(transaction, to: item.account)
            }
            let previousDueDate = item.nextDueDate
            item.advanceNextDueDate()
            // Guard against a non-advancing calendar (e.g. a malformed
            // frequency/calendar combination that fails to move nextDueDate
            // forward), which would otherwise loop forever. This branch is
            // not exercised by tests since Calendar isn't injectable here.
            if item.nextDueDate <= previousDueDate {
                print("RecurringTransaction processing: nextDueDate failed to advance for item \(item.id); stopping to avoid infinite loop.")
                break
            }
            NotificationScheduler.syncReminder(for: item)
        }
    }

    do {
        try context.save()
        BudgetAlertCoordinator.checkBudgets(context: context)
        return true
    } catch {
        // Surface the error to the console; callers can add additional
        // error-handling if required.
        print("RecurringTransaction processing failed to save: \(error)")
        return false
    }
}
