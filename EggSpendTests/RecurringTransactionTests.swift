import XCTest
import SwiftData
@testable import EggSpend

final class RecurringTransactionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testRecurringTransactionInitialization() {
        let item = RecurringTransaction(title: "Rent", amount: 1500, type: .expense,
                                        frequency: .monthly)
        XCTAssertEqual(item.title, "Rent")
        XCTAssertEqual(item.amount, 1500, accuracy: 0.001)
        XCTAssertEqual(item.type, .expense)
        XCTAssertEqual(item.frequency, .monthly)
        XCTAssertTrue(item.isActive)
        XCTAssertNil(item.endDate)
    }

    func testRecurrenceFrequencyAllCases() {
        XCTAssertEqual(RecurrenceFrequency.allCases.count, 5)
        for freq in RecurrenceFrequency.allCases {
            XCTAssertFalse(freq.icon.isEmpty, "\(freq.rawValue) should have an icon")
        }
    }

    func testBiweeklyCalendarValue() {
        XCTAssertEqual(RecurrenceFrequency.biweekly.calendarValue, 2)
    }

    func testAdvanceNextDueDateMonthly() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let item = RecurringTransaction(title: "Netflix", amount: 17.99, type: .expense,
                                        frequency: .monthly, startDate: start)
        item.nextDueDate = start
        item.advanceNextDueDate()
        let expected = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        XCTAssertEqual(item.nextDueDate, expected)
    }

    func testAdvanceNextDueDateWeekly() {
        let start = Date.now
        let item = RecurringTransaction(title: "Gym", amount: 30, type: .expense,
                                        frequency: .weekly, startDate: start)
        item.nextDueDate = start
        item.advanceNextDueDate()
        let expected = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: start)!
        XCTAssertEqual(item.nextDueDate.timeIntervalSinceReferenceDate,
                       expected.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testProcessRecurringGeneratesTransactions() throws {
        let past = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
        let item = RecurringTransaction(title: "Subscription", amount: 9.99,
                                        type: .expense, frequency: .monthly, startDate: past)
        item.nextDueDate = past
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(transactions.isEmpty, "Should have generated at least one transaction")
        XCTAssertEqual(transactions.first?.title, "Subscription")
        XCTAssertTrue(item.nextDueDate > past, "nextDueDate should have advanced")
    }

    func testProcessRecurringRespectsEndDate() throws {
        let past = Calendar.current.date(byAdding: .month, value: -5, to: .now)!
        let endDate = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
        let item = RecurringTransaction(title: "Old Sub", amount: 5, type: .expense,
                                        frequency: .monthly, startDate: past)
        item.nextDueDate = past
        item.endDate = endDate
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        for tx in transactions {
            XCTAssertLessThanOrEqual(tx.date, endDate, "No transactions past end date")
        }
    }

    func testInactiveRecurringIsSkipped() throws {
        let past = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let item = RecurringTransaction(title: "Paused", amount: 20, type: .expense,
                                        frequency: .monthly, startDate: past)
        item.nextDueDate = past
        item.isActive = false
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertTrue(transactions.isEmpty, "Inactive recurring should not generate transactions")
    }

    func testRecurringPersistence() throws {
        let item = RecurringTransaction(title: "Salary", amount: 5000, type: .income,
                                        frequency: .biweekly)
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RecurringTransaction>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.frequency, .biweekly)
        XCTAssertEqual(fetched.first?.amount ?? 0, 5000, accuracy: 0.001)
    }

    func testReminderFieldsDefaultToDisabled() {
        let item = RecurringTransaction(title: "Rent", amount: 1500, type: .expense, frequency: .monthly)
        XCTAssertFalse(item.reminderEnabled)
        XCTAssertEqual(item.reminderDaysBefore, 1)
    }

    func testReminderFieldsPersist() throws {
        let item = RecurringTransaction(title: "Rent", amount: 1500, type: .expense, frequency: .monthly)
        item.reminderEnabled = true
        item.reminderDaysBefore = 5
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RecurringTransaction>())
        XCTAssertEqual(fetched.first?.reminderEnabled, true)
        XCTAssertEqual(fetched.first?.reminderDaysBefore, 5)
    }

    func testRecurringTransactionAccountPersists() throws {
        let account = Account(name: "Chase Checking", type: .checking, balance: 1000)
        context.insert(account)
        let item = RecurringTransaction(title: "Rent", amount: 1500, type: .expense,
                                        frequency: .monthly, account: account)
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RecurringTransaction>())
        XCTAssertEqual(fetched.first?.account?.name, "Chase Checking")
    }

    func testProcessRecurringAppliesAccountBalance() throws {
        let account = Account(name: "Chase Checking", type: .checking, balance: 1000)
        context.insert(account)

        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let expense = RecurringTransaction(title: "Rent", amount: 200, type: .expense,
                                           frequency: .monthly, startDate: past, account: account)
        expense.nextDueDate = past
        context.insert(expense)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        XCTAssertEqual(account.balance, 800, accuracy: 0.001)
    }
}
