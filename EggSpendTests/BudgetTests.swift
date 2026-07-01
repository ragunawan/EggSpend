import XCTest
import SwiftData
@testable import EggSpend

final class BudgetTests: XCTestCase {
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

    func testBudgetInitialization() throws {
        let budget = Budget(name: "Groceries", limitAmount: 500, period: .monthly,
                            category: nil, colorHex: "E67E22")
        XCTAssertEqual(budget.name, "Groceries")
        XCTAssertEqual(budget.limitAmount, 500, accuracy: 0.001)
        XCTAssertEqual(budget.period, .monthly)
        XCTAssertTrue(budget.isActive)
        XCTAssertNil(budget.category)
    }

    func testBudgetPeriodCases() {
        XCTAssertEqual(BudgetPeriod.allCases.count, 3)
        XCTAssertFalse(BudgetPeriod.monthly.icon.isEmpty)
        XCTAssertFalse(BudgetPeriod.weekly.icon.isEmpty)
        XCTAssertFalse(BudgetPeriod.yearly.icon.isEmpty)
    }

    func testBudgetSpentCalculation() throws {
        let cat = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        context.insert(cat)
        let budget = Budget(name: "Food Budget", limitAmount: 300, period: .monthly,
                            category: cat, colorHex: "E67E22")
        context.insert(budget)

        let now = Date.now
        let txInPeriod1 = Transaction(title: "Lunch", amount: 15, date: now, type: .expense, category: cat)
        let txInPeriod2 = Transaction(title: "Dinner", amount: 45, date: now, type: .expense, category: cat)
        let txOtherCat  = Transaction(title: "Uber", amount: 20, date: now, type: .expense)
        let txOldDate   = Transaction(title: "Old meal",
                                      amount: 100,
                                      date: Calendar.current.date(byAdding: .month, value: -2, to: now)!,
                                      type: .expense, category: cat)
        [txInPeriod1, txInPeriod2, txOtherCat, txOldDate].forEach { context.insert($0) }
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let spent = budget.spent(from: all)
        XCTAssertEqual(spent, 60, accuracy: 0.001, "Only in-period, same-category transactions should count")
    }

    func testBudgetProgress() throws {
        let budget = Budget(name: "Transport", limitAmount: 200, period: .monthly,
                            category: nil, colorHex: "3498DB")
        context.insert(budget)
        let txs = [
            Transaction(title: "Bus", amount: 50, type: .expense),
            Transaction(title: "Taxi", amount: 50, type: .expense)
        ]
        txs.forEach { context.insert($0) }
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let progress = budget.progress(from: all)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testBudgetProgressExceedsOneWhenOverBudget() throws {
        let budget = Budget(name: "Small", limitAmount: 10, period: .monthly,
                            category: nil, colorHex: "FF0000")
        context.insert(budget)
        context.insert(Transaction(title: "Overspend", amount: 999, type: .expense))
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let progress = budget.progress(from: all)
        XCTAssertGreaterThan(progress, 1.0, "Progress > 1.0 signals over-budget to callers")
    }

    func testBudgetRemaining() throws {
        let budget = Budget(name: "Entertainment", limitAmount: 100, period: .monthly,
                            category: nil, colorHex: "9B59B6")
        context.insert(budget)
        context.insert(Transaction(title: "Movie", amount: 30, type: .expense))
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(budget.remaining(from: all), 70, accuracy: 0.001)
    }

    func testBudgetStatusColor() {
        let budget = Budget(name: "Test", limitAmount: 100, period: .monthly,
                            category: nil, colorHex: "AABBCC")
        // Safe under 70%
        let safeProg  = budget.statusColor(progress: 0.5)
        let warnProg  = budget.statusColor(progress: 0.8)
        let dangerProg = budget.statusColor(progress: 0.95)
        let exceededProg = budget.statusColor(progress: 1.1)
        XCTAssertNotNil(safeProg)
        XCTAssertNotNil(warnProg)
        XCTAssertNotNil(dangerProg)
        XCTAssertNotNil(exceededProg)
    }

    func testDaysRemainingInCurrentPeriodIsWithinPeriodBounds() {
        let weekly  = Budget(name: "Weekly",  limitAmount: 100, period: .weekly)
        let monthly = Budget(name: "Monthly", limitAmount: 100, period: .monthly)
        let yearly  = Budget(name: "Yearly",  limitAmount: 100, period: .yearly)

        XCTAssertTrue((1...7).contains(weekly.daysRemainingInCurrentPeriod()))
        XCTAssertTrue((1...31).contains(monthly.daysRemainingInCurrentPeriod()))
        XCTAssertTrue((1...366).contains(yearly.daysRemainingInCurrentPeriod()))
    }

    func testBudgetPersistence() throws {
        let budget = Budget(name: "Saved Budget", limitAmount: 250, period: .weekly,
                            category: nil, colorHex: "27AE60")
        context.insert(budget)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Budget>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Saved Budget")
        XCTAssertEqual(fetched.first?.period, .weekly)
    }

    // MARK: evaluateAlert

    func testEvaluateAlertFiresAtNearLimitThreshold() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let tx = Transaction(title: "Groceries", amount: 85, type: .expense)
        let result = budget.evaluateAlert(from: [tx])
        XCTAssertEqual(result, .nearLimit)
        XCTAssertEqual(budget.lastAlertedThreshold, .nearLimit)
    }

    func testEvaluateAlertFiresAtExceededThreshold() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let tx = Transaction(title: "Groceries", amount: 110, type: .expense)
        let result = budget.evaluateAlert(from: [tx])
        XCTAssertEqual(result, .exceeded)
    }

    func testEvaluateAlertDoesNotRefireSameThresholdTwice() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let tx = Transaction(title: "Groceries", amount: 85, type: .expense)
        XCTAssertEqual(budget.evaluateAlert(from: [tx]), .nearLimit)
        XCTAssertNil(budget.evaluateAlert(from: [tx]))
    }

    func testEvaluateAlertSkipsIntermediateWhenJumpingStraightToExceeded() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let tx = Transaction(title: "Splurge", amount: 120, type: .expense)
        let result = budget.evaluateAlert(from: [tx])
        XCTAssertEqual(result, .exceeded)
        XCTAssertEqual(budget.lastAlertedThreshold, .exceeded)
    }

    func testEvaluateAlertResetsOnNewPeriod() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let tx = Transaction(title: "Groceries", amount: 85, type: .expense)
        XCTAssertEqual(budget.evaluateAlert(from: [tx]), .nearLimit)

        // Simulate rollover into a new period.
        budget.lastAlertedPeriodStart = Calendar.current.date(byAdding: .month, value: -1, to: budget.lastAlertedPeriodStart!)!
        XCTAssertEqual(budget.evaluateAlert(from: [tx]), .nearLimit)
    }

    func testEvaluateAlertReturnsNilWhenAlertsDisabled() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = false
        let tx = Transaction(title: "Groceries", amount: 110, type: .expense)
        XCTAssertNil(budget.evaluateAlert(from: [tx]))
    }

    func testEvaluateAlertReturnsNilWhenBudgetInactive() {
        let budget = Budget(name: "Food", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        budget.isActive = false
        let tx = Transaction(title: "Groceries", amount: 110, type: .expense)
        XCTAssertNil(budget.evaluateAlert(from: [tx]))
    }
}
