import XCTest
import SwiftData
@testable import EggSpend

final class MonthlyReviewCalculatorTests: XCTestCase {
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    // MARK: - Month bounds / filtering

    func testMonthBounds() {
        let mid = date(2026, 3, 15)
        let (start, end) = MonthlyReviewCalculator.monthBounds(for: mid)
        XCTAssertEqual(start, date(2026, 3, 1))
        XCTAssertEqual(end, date(2026, 4, 1))
    }

    func testFilterKeepsOnlyTransactionsInMonth() {
        let txs = [
            Transaction(title: "In month",  amount: 10, date: date(2026, 3, 5),  type: .expense),
            Transaction(title: "Before",    amount: 10, date: date(2026, 2, 28), type: .expense),
            Transaction(title: "After",     amount: 10, date: date(2026, 4, 1),  type: .expense),
            Transaction(title: "Boundary",  amount: 10, date: date(2026, 3, 1),  type: .expense)
        ]
        let result = MonthlyReviewCalculator.filter(txs, forMonth: date(2026, 3, 15))
        XCTAssertEqual(result.map(\.title).sorted(), ["Boundary", "In month"])
    }

    // MARK: - Income / expenses / savings rate

    func testIncomeAndExpensesSums() {
        let txs = [
            Transaction(title: "Salary", amount: 3000, type: .income),
            Transaction(title: "Bonus",  amount: 500,  type: .income),
            Transaction(title: "Rent",   amount: 1200, type: .expense),
            Transaction(title: "Food",   amount: 300,  type: .expense)
        ]
        XCTAssertEqual(MonthlyReviewCalculator.income(from: txs), 3500, accuracy: 0.001)
        XCTAssertEqual(MonthlyReviewCalculator.expenses(from: txs), 1500, accuracy: 0.001)
    }

    func testSavingsRatePositive() {
        let rate = MonthlyReviewCalculator.savingsRate(income: 4000, expenses: 3000)
        XCTAssertEqual(rate ?? 0, 0.25, accuracy: 0.001)
    }

    func testSavingsRateNegativeWhenOverspent() {
        let rate = MonthlyReviewCalculator.savingsRate(income: 1000, expenses: 1500)
        XCTAssertEqual(rate ?? 0, -0.5, accuracy: 0.001)
    }

    func testSavingsRateNilWhenNoIncome() {
        XCTAssertNil(MonthlyReviewCalculator.savingsRate(income: 0, expenses: 200))
    }

    // MARK: - Top categories

    func testTopCategoriesAggregatesAndSorts() {
        let food = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22")
        let transit = TransactionCategory(name: "Transit", icon: "car.fill", colorHex: "3498DB")
        let txs = [
            Transaction(title: "Lunch",   amount: 20, type: .expense, category: food),
            Transaction(title: "Dinner",  amount: 40, type: .expense, category: food),
            Transaction(title: "Bus",     amount: 15, type: .expense, category: transit),
            Transaction(title: "Salary",  amount: 3000, type: .income, category: nil)
        ]
        let top = MonthlyReviewCalculator.topCategories(from: txs)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top.first?.name, "Food")
        XCTAssertEqual(top.first?.amount ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(top.last?.name, "Transit")
    }

    func testTopCategoriesGroupsUncategorizedSpend() {
        let txs = [
            Transaction(title: "Misc 1", amount: 10, type: .expense, category: nil),
            Transaction(title: "Misc 2", amount: 5,  type: .expense, category: nil)
        ]
        let top = MonthlyReviewCalculator.topCategories(from: txs)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.name, "Uncategorized")
        XCTAssertEqual(top.first?.amount ?? 0, 15, accuracy: 0.001)
    }

    func testTopCategoriesRespectsLimit() {
        let txs = (0..<10).map { i in
            Transaction(title: "Tx\(i)", amount: Double(i + 1), type: .expense,
                        category: TransactionCategory(name: "Cat\(i)", icon: "circle", colorHex: "000000"))
        }
        let top = MonthlyReviewCalculator.topCategories(from: txs, limit: 3)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.map(\.amount), [10, 9, 8])
    }

    // MARK: - Budget overruns

    func testBudgetOverrunsOnlyIncludesExceededMonthlyBudgets() throws {
        let food = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22")
        context.insert(food)

        let overBudget = Budget(name: "Food Budget", limitAmount: 100, period: .monthly, category: food)
        let underBudget = Budget(name: "Transit Budget", limitAmount: 200, period: .monthly, category: nil)
        let weeklyBudget = Budget(name: "Weekly Snacks", limitAmount: 5, period: .weekly, category: nil)
        [overBudget, underBudget, weeklyBudget].forEach { context.insert($0) }

        let month = date(2026, 3, 15)
        let txs = [
            Transaction(title: "Groceries", amount: 150, date: date(2026, 3, 5), type: .expense, category: food),
            Transaction(title: "Bus",       amount: 50,  date: date(2026, 3, 6), type: .expense, category: nil)
        ]
        txs.forEach { context.insert($0) }
        try context.save()

        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let overruns = MonthlyReviewCalculator.budgetOverruns(budgets: budgets, transactions: txs, month: month)

        XCTAssertEqual(overruns.count, 1)
        XCTAssertEqual(overruns.first?.name, "Food Budget")
        XCTAssertEqual(overruns.first?.overage ?? 0, 50, accuracy: 0.001)
    }

    func testBudgetOverrunsExcludesInactiveBudgets() throws {
        let budget = Budget(name: "Inactive", limitAmount: 10, period: .monthly, category: nil)
        budget.isActive = false
        context.insert(budget)
        try context.save()

        let month = date(2026, 3, 15)
        let txs = [Transaction(title: "Spend", amount: 999, date: date(2026, 3, 5), type: .expense)]
        let overruns = MonthlyReviewCalculator.budgetOverruns(budgets: [budget], transactions: txs, month: month)
        XCTAssertTrue(overruns.isEmpty)
    }

    func testBudgetOverrunsSortedByOverageDescending() throws {
        let small = Budget(name: "Small", limitAmount: 10, period: .monthly, category: nil)
        let big = Budget(name: "Big", limitAmount: 100, period: .monthly, category: nil)
        [small, big].forEach { context.insert($0) }

        // Both budgets are uncategorized (nil), so they'd double count against the same
        // transactions in this simplified scenario; evaluate independently instead.
        let month = date(2026, 3, 15)
        let smallOverruns = MonthlyReviewCalculator.budgetOverruns(
            budgets: [small],
            transactions: [Transaction(title: "A", amount: 30, date: date(2026, 3, 2), type: .expense)],
            month: month
        )
        let bigOverruns = MonthlyReviewCalculator.budgetOverruns(
            budgets: [big],
            transactions: [Transaction(title: "B", amount: 500, date: date(2026, 3, 2), type: .expense)],
            month: month
        )
        XCTAssertEqual(smallOverruns.first?.overage ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(bigOverruns.first?.overage ?? 0, 400, accuracy: 0.001)
    }

    // MARK: - Net worth reconstruction

    func testNetWorthAtDateReversesLaterTransactions() {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let accounts = [checking]
        let cutoff = date(2026, 3, 1)
        let txs = [
            Transaction(title: "Paycheck", amount: 500, date: date(2026, 3, 10), type: .income),
            Transaction(title: "Rent",     amount: 200, date: date(2026, 3, 15), type: .expense)
        ]
        // current balance (1000) already reflects +500 income and -200 expense after cutoff,
        // so net worth at cutoff should back those out: 1000 - 500 + 200 = 700
        let netWorth = MonthlyReviewCalculator.netWorth(accounts: accounts, allTransactions: txs, at: cutoff)
        XCTAssertEqual(netWorth, 700, accuracy: 0.001)
    }

    func testNetWorthIgnoresTransactionsBeforeOrOnDate() {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let txs = [Transaction(title: "Old", amount: 100, date: date(2026, 2, 1), type: .income)]
        let netWorth = MonthlyReviewCalculator.netWorth(accounts: [checking], allTransactions: txs, at: date(2026, 3, 1))
        XCTAssertEqual(netWorth, 1000, accuracy: 0.001)
    }

    // MARK: - Full calculation

    func testCalculateProducesConsistentSummary() {
        let food = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22")
        let checking = Account(name: "Checking", type: .checking, balance: 2300)
        let budget = Budget(name: "Food Budget", limitAmount: 50, period: .monthly, category: food)

        let month = date(2026, 3, 15)
        let txs = [
            Transaction(title: "Salary",   amount: 3000, date: date(2026, 3, 1),  type: .income),
            Transaction(title: "Groceries",amount: 80,   date: date(2026, 3, 5),  type: .expense, category: food),
            Transaction(title: "Rent",     amount: 1200, date: date(2026, 3, 6),  type: .expense),
            Transaction(title: "Old food", amount: 999,  date: date(2026, 1, 1),  type: .expense, category: food)
        ]

        let result = MonthlyReviewCalculator.calculate(
            month: month, transactions: txs, accounts: [checking], budgets: [budget]
        )

        XCTAssertEqual(result.income, 3000, accuracy: 0.001)
        XCTAssertEqual(result.expenses, 1280, accuracy: 0.001)
        XCTAssertEqual(result.netSavings, 1720, accuracy: 0.001)
        XCTAssertEqual(result.savingsRate ?? 0, 1720.0 / 3000.0, accuracy: 0.001)
        // Rent has no category, so "Uncategorized" (1200) outranks Food (80, in-month only).
        XCTAssertEqual(result.topCategories.first?.name, "Uncategorized")
        XCTAssertEqual(result.topCategories.first?.amount ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(result.topCategories.last?.name, "Food")
        XCTAssertEqual(result.topCategories.last?.amount ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(result.budgetOverruns.first?.name, "Food Budget")
        XCTAssertEqual(result.netWorthChange, result.netWorthAtEnd - result.netWorthAtStart, accuracy: 0.001)
    }

    /// Regression guard for the motivating goal of the `Transfer` model: moving money
    /// between the user's own accounts must not be visible to income/expense/savings-rate
    /// calculations, since a `Transfer` is never inserted as a `Transaction` row.
    func testTransferDoesNotAffectIncomeExpensesOrSavingsRate() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        context.insert(checking)
        context.insert(savings)

        let month = date(2026, 3, 15)
        let txs = [
            Transaction(title: "Salary", amount: 3000, date: date(2026, 3, 1), type: .income),
            Transaction(title: "Rent",   amount: 1200, date: date(2026, 3, 6), type: .expense)
        ]
        txs.forEach { context.insert($0) }

        let before = MonthlyReviewCalculator.calculate(
            month: month, transactions: txs, accounts: [checking, savings], budgets: []
        )

        let transfer = Transfer(amount: 500, date: date(2026, 3, 10), fromAccount: checking, toAccount: savings)
        context.insert(transfer)
        TransferBalanceService.apply(transfer)
        try context.save()

        let after = MonthlyReviewCalculator.calculate(
            month: month, transactions: txs, accounts: [checking, savings], budgets: []
        )

        XCTAssertEqual(before.income, after.income, accuracy: 0.001)
        XCTAssertEqual(before.expenses, after.expenses, accuracy: 0.001)
        XCTAssertEqual(before.savingsRate ?? 0, after.savingsRate ?? 0, accuracy: 0.001)
    }

    func testCalculateHandlesEmptyMonthGracefully() {
        let result = MonthlyReviewCalculator.calculate(
            month: date(2026, 3, 15), transactions: [], accounts: [], budgets: []
        )
        XCTAssertEqual(result.income, 0)
        XCTAssertEqual(result.expenses, 0)
        XCTAssertEqual(result.netSavings, 0)
        XCTAssertNil(result.savingsRate)
        XCTAssertTrue(result.topCategories.isEmpty)
        XCTAssertTrue(result.budgetOverruns.isEmpty)
        XCTAssertEqual(result.netWorthChange, 0)
    }
}
