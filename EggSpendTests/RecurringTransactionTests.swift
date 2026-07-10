import XCTest
import SwiftData
@testable import EggSpend

final class RecurringTransactionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self, CategoryRule.self])
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
        XCTAssertEqual(transactions.first?.recurringSourceID, item.id)
        XCTAssertNotNil(transactions.first?.recurringDueDate)
    }

    /// `processRecurringTransactions` returns `true` on a successful save so callers
    /// (currently none do) can react to it. Failure paths (`context.save()` throwing)
    /// aren't reproducible with the in-memory container used here and are covered by
    /// inspection only: the `catch` branch logs and returns `false`.
    func testProcessRecurringTransactionsReturnsTrueOnSuccess() throws {
        let past = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
        let item = RecurringTransaction(title: "Subscription", amount: 9.99,
                                        type: .expense, frequency: .monthly, startDate: past)
        item.nextDueDate = past
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        let result = processRecurringTransactions(all, context: context)

        XCTAssertTrue(result)
    }

    func testProcessRecurringDoesNotDuplicateExistingGeneratedOccurrence() throws {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let item = RecurringTransaction(title: "Subscription", amount: 9.99,
                                        type: .expense, frequency: .monthly, startDate: past)
        item.nextDueDate = past
        context.insert(item)
        let existing = Transaction(
            title: "Subscription",
            amount: 9.99,
            date: past,
            type: .expense,
            isGenerated: true,
            recurringSourceID: item.id,
            recurringDueDate: past
        )
        context.insert(existing)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertTrue(item.nextDueDate > past)
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

    func testProcessRecurringGeneratesFinalOccurrenceForEndedItem() throws {
        // nextDueDate is 14 days in the past, endDate is yesterday (1 day
        // ago): the first occurrence at now-14d is <= endDate, so it's
        // generated. Advancing one month from now-14d lands at least 28 days
        // later (shortest month, February), i.e. at or beyond now+14d, which
        // is always > now-1d (endDate) since 28 > 14+1. So exactly one
        // occurrence is generated on/before endDate for every possible
        // calendar/month length, making the fixture deterministic.
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: .now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let item = RecurringTransaction(title: "Ended Sub", amount: 12, type: .expense,
                                        frequency: .monthly, startDate: twoWeeksAgo)
        item.nextDueDate = twoWeeksAgo
        item.endDate = yesterday
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 1, "Exactly one occurrence should have been generated before the item ended")
        XCTAssertLessThanOrEqual(transactions.first?.date ?? .distantFuture, yesterday)
        XCTAssertGreaterThan(item.nextDueDate, yesterday, "nextDueDate should have advanced past the end date")
    }

    func testProcessRecurringEndedItemIsIdempotentAcrossRelaunch() throws {
        let calendar = Calendar.current
        let fiveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -5, to: .now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let item = RecurringTransaction(title: "Ended Sub", amount: 12, type: .expense,
                                        frequency: .monthly, startDate: fiveWeeksAgo)
        item.nextDueDate = fiveWeeksAgo
        item.endDate = yesterday
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)
        let countAfterFirstRun = try context.fetch(FetchDescriptor<Transaction>()).count

        // Simulate a second app launch processing the same (now ended) item.
        processRecurringTransactions(all, context: context)
        let countAfterSecondRun = try context.fetch(FetchDescriptor<Transaction>()).count

        XCTAssertEqual(countAfterFirstRun, countAfterSecondRun,
                       "Re-processing an ended item should not create duplicate transactions")
    }

    func testProcessRecurringTerminatesForDeepBacklog() throws {
        // Daily item, nextDueDate 400 days in the past, no endDate.
        // The while loop runs for every k in 0...400 where
        // nextDueDate = now - (400 - k) days, since at k = 400 the due date
        // equals `now` exactly and `<=` still admits it. That is 401
        // occurrences (day -400 through day 0 inclusive); advancing past k=400
        // yields now + 1 day, which exceeds `now` and stops the loop.
        let calendar = Calendar.current
        let past = calendar.date(byAdding: .day, value: -400, to: .now)!
        let item = RecurringTransaction(title: "Daily Thing", amount: 1, type: .expense,
                                        frequency: .daily, startDate: past)
        item.nextDueDate = past
        context.insert(item)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringTransaction>())
        processRecurringTransactions(all, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 401, "Loop should terminate after generating exactly 401 daily occurrences")
    }

    // Note: the non-advancing-calendar guard in processRecurringTransactions
    // (breaking when nextDueDate fails to move forward) is not covered by a
    // test here since Calendar isn't injectable into RecurringTransaction;
    // this is a documented gap rather than an oversight.

    func testRecurringProjectionIncludesNext30DaysAndExcludesEndedItems() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let weekly = RecurringTransaction(title: "Gym", amount: 30, type: .expense,
                                          frequency: .weekly, startDate: tomorrow)
        weekly.nextDueDate = tomorrow

        let ended = RecurringTransaction(title: "Old", amount: 10, type: .expense,
                                         frequency: .daily, startDate: tomorrow)
        ended.nextDueDate = tomorrow
        ended.endDate = calendar.date(byAdding: .day, value: -1, to: .now)

        let occurrences = RecurringProjection.occurrences(from: [weekly, ended], start: .now, days: 30)
        XCTAssertEqual(occurrences.filter { $0.title == "Gym" }.count, 5)
        XCTAssertFalse(occurrences.contains { $0.title == "Old" })
    }
}
