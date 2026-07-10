import XCTest
import SwiftData
@testable import EggSpend

final class TransactionFilterTests: XCTestCase {
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

    func testEmptyFilterIsInactiveAndMatchesEverything() {
        let filter = TransactionFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeCount, 0)

        let tx = Transaction(title: "Coffee", amount: 4.5, type: .expense)
        XCTAssertTrue(filter.matches(tx))
    }

    func testTypeFilter() {
        var filter = TransactionFilter()
        filter.type = .income

        let income = Transaction(title: "Salary", amount: 3000, type: .income)
        let expense = Transaction(title: "Rent", amount: 1200, type: .expense)

        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(income))
        XCTAssertFalse(filter.matches(expense))
    }

    func testCategoryFilter() throws {
        let groceries = TransactionCategory(name: "Groceries", icon: "cart", colorHex: "E67E22")
        let dining = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "C0392B")
        context.insert(groceries)
        context.insert(dining)
        try context.save()

        var filter = TransactionFilter()
        filter.categoryIDs = [groceries.id]

        let txGroceries = Transaction(title: "Market", amount: 50, type: .expense, category: groceries)
        let txDining = Transaction(title: "Dinner", amount: 30, type: .expense, category: dining)
        let txUncategorized = Transaction(title: "Misc", amount: 10, type: .expense)

        XCTAssertTrue(filter.matches(txGroceries))
        XCTAssertFalse(filter.matches(txDining))
        XCTAssertFalse(filter.matches(txUncategorized))
    }

    func testAccountFilter() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 5000)
        context.insert(checking)
        context.insert(savings)
        try context.save()

        var filter = TransactionFilter()
        filter.accountIDs = [checking.id]

        let txChecking = Transaction(title: "Card swipe", amount: 20, type: .expense, account: checking)
        let txSavings = Transaction(title: "Transfer", amount: 100, type: .expense, account: savings)
        let txNoAccount = Transaction(title: "Cash", amount: 5, type: .expense)

        XCTAssertTrue(filter.matches(txChecking))
        XCTAssertFalse(filter.matches(txSavings))
        XCTAssertFalse(filter.matches(txNoAccount))
    }

    func testDateRangeFilter() {
        var filter = TransactionFilter()
        let now = Date.now
        filter.startDate = Calendar.current.date(byAdding: .day, value: -7, to: now)
        filter.endDate = now

        let inRange = Transaction(title: "Recent", amount: 10,
                                  date: Calendar.current.date(byAdding: .day, value: -3, to: now)!,
                                  type: .expense)
        let tooOld = Transaction(title: "Old", amount: 10,
                                 date: Calendar.current.date(byAdding: .day, value: -30, to: now)!,
                                 type: .expense)
        let inFuture = Transaction(title: "Future", amount: 10,
                                   date: Calendar.current.date(byAdding: .day, value: 30, to: now)!,
                                   type: .expense)

        XCTAssertTrue(filter.matches(inRange))
        XCTAssertFalse(filter.matches(tooOld))
        XCTAssertFalse(filter.matches(inFuture))
    }

    func testDateRangeEndDateIsInclusiveOfWholeDay() {
        var filter = TransactionFilter()
        let endDay = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        filter.endDate = endDay

        let lateOnEndDay = Calendar.current.date(
            byAdding: DateComponents(hour: 23, minute: 59), to: endDay
        )!
        let tx = Transaction(title: "Late purchase", amount: 10, date: lateOnEndDay, type: .expense)

        XCTAssertTrue(filter.matches(tx), "End date should include the entire day")
    }

    func testAmountRangeFilter() {
        var filter = TransactionFilter()
        filter.minAmount = 20
        filter.maxAmount = 100

        let belowRange = Transaction(title: "Cheap", amount: 5, type: .expense)
        let inRange = Transaction(title: "Mid", amount: 50, type: .expense)
        let aboveRange = Transaction(title: "Expensive", amount: 500, type: .expense)

        XCTAssertFalse(filter.matches(belowRange))
        XCTAssertTrue(filter.matches(inRange))
        XCTAssertFalse(filter.matches(aboveRange))
    }

    func testGeneratedOnlyFilter() {
        var filter = TransactionFilter()
        filter.generatedOnly = true

        let generated = Transaction(title: "Netflix", amount: 17.99, type: .expense, isGenerated: true)
        let manual = Transaction(title: "Manual entry", amount: 17.99, type: .expense, isGenerated: false)

        XCTAssertTrue(filter.matches(generated))
        XCTAssertFalse(filter.matches(manual))
    }

    func testCombinedFiltersRequireAllToMatch() throws {
        let category = TransactionCategory(name: "Subscriptions", icon: "play.rectangle", colorHex: "8E44AD")
        context.insert(category)
        try context.save()

        var filter = TransactionFilter()
        filter.type = .expense
        filter.categoryIDs = [category.id]
        filter.minAmount = 10

        let matching = Transaction(title: "Netflix", amount: 17.99, type: .expense, category: category)
        let wrongType = Transaction(title: "Refund", amount: 17.99, type: .income, category: category)
        let wrongCategory = Transaction(title: "Other", amount: 17.99, type: .expense)
        let tooCheap = Transaction(title: "Cheap sub", amount: 2, type: .expense, category: category)

        XCTAssertTrue(filter.matches(matching))
        XCTAssertFalse(filter.matches(wrongType))
        XCTAssertFalse(filter.matches(wrongCategory))
        XCTAssertFalse(filter.matches(tooCheap))
    }

    func testResetClearsAllCriteria() {
        var filter = TransactionFilter()
        filter.type = .expense
        filter.categoryIDs = [UUID()]
        filter.accountIDs = [UUID()]
        filter.startDate = .now
        filter.endDate = .now
        filter.minAmount = 1
        filter.maxAmount = 100
        filter.generatedOnly = true
        XCTAssertTrue(filter.isActive)

        filter.reset()

        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeCount, 0)
        XCTAssertNil(filter.type)
        XCTAssertTrue(filter.categoryIDs.isEmpty)
        XCTAssertTrue(filter.accountIDs.isEmpty)
        XCTAssertNil(filter.startDate)
        XCTAssertNil(filter.endDate)
        XCTAssertNil(filter.minAmount)
        XCTAssertNil(filter.maxAmount)
        XCTAssertFalse(filter.generatedOnly)
    }

    func testActiveCountGroupsRelatedCriteria() {
        var filter = TransactionFilter()
        filter.minAmount = 10
        filter.maxAmount = 100
        XCTAssertEqual(filter.activeCount, 1, "Min and max amount together should count as a single active group")

        filter.startDate = .now
        filter.endDate = .now
        XCTAssertEqual(filter.activeCount, 2, "Start and end date together should count as a single active group")
    }
}
