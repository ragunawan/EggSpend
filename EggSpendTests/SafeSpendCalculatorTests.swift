import XCTest
import SwiftData
@testable import EggSpend

final class SafeSpendCalculatorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: 1. No accounts

    func testNoAccountsReturnsZeroSafeSpend() {
        let result = SafeSpendCalculator.calculate(
            accounts: [], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.safeToSpendToday, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .pause)
    }

    // MARK: 2. Liquid balance excludes investments/liabilities

    func testLiquidBalanceIncludesCheckingAndSavingsOnly() {
        let checking   = Account(name: "Checking",   type: .checking,    balance: 1_000)
        let savings    = Account(name: "Savings",    type: .savings,     balance: 2_000)
        let investment = Account(name: "Invest",     type: .investment,  balance: 5_000)
        let credit     = Account(name: "Card",       type: .credit,      balance: 500)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking, savings, investment, credit],
            transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.liquidBalance, 3_000, accuracy: 0.001)
    }

    // MARK: 3. Upcoming recurring expense reduces safe spend

    func testUpcomingRecurringExpenseReducesSafeSpend() {
        let checking = Account(name: "Checking", type: .checking, balance: 2_000)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let rent = RecurringTransaction(title: "Rent", amount: 300, type: .expense,
                                        frequency: .monthly, startDate: tomorrow)
        rent.nextDueDate = tomorrow

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [rent], budgets: [], savingsGoals: []
        )
        // liquid 2000 - buffer 500 - outflow 300 = 1200 (no budgets, so cash side wins)
        XCTAssertEqual(result.upcomingNetOutflowReserve, 300, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendToday, 1_200, accuracy: 0.001)
    }

    // MARK: 4. Upcoming recurring income offsets recurring expense

    func testUpcomingRecurringIncomeOffsetsExpense() {
        let checking = Account(name: "Checking", type: .checking, balance: 2_000)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

        let rent = RecurringTransaction(title: "Rent", amount: 300, type: .expense,
                                        frequency: .monthly, startDate: tomorrow)
        rent.nextDueDate = tomorrow
        let paycheck = RecurringTransaction(title: "Paycheck", amount: 500, type: .income,
                                            frequency: .monthly, startDate: tomorrow)
        paycheck.nextDueDate = tomorrow

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [rent, paycheck], budgets: [], savingsGoals: []
        )
        // net = +200, so reserve clamps to 0
        XCTAssertEqual(result.upcomingNetOutflowReserve, 0, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendToday, 1_500, accuracy: 0.001)
    }

    // MARK: 5. Required buffer is reserved

    func testRequiredBufferScalesWithRecentSpendingAndIsReserved() {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let recentExpense = Transaction(title: "Big Purchase", amount: 5_000, date: .now, type: .expense)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [recentExpense], recurring: [], budgets: [], savingsGoals: []
        )
        // avgDailyExpenses = 5000/60 = 83.333..., buffer = 83.333 * 7 = 583.333...
        let expectedBuffer = (5_000.0 / 60.0) * 7.0
        XCTAssertEqual(result.requiredBuffer, expectedBuffer, accuracy: 0.01)
        XCTAssertEqual(result.safeToSpendToday, 1_000 - expectedBuffer, accuracy: 0.01)
    }

    func testRequiredBufferFloorAppliesWithNoSpendingHistory() {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.requiredBuffer, 500, accuracy: 0.001)
    }

    // MARK: 6. Active savings goal with target date reserves daily required contribution

    func testDatedSavingsGoalReservesDailyRequiredContribution() {
        let checking = Account(name: "Checking", type: .checking, balance: 5_000)
        let targetDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let goal = SavingsGoal(name: "Trip", targetAmount: 1_000, currentAmount: 0, targetDate: targetDate)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: [goal]
        )
        // remaining 1000 / 10 days = 100/day reserve
        XCTAssertEqual(result.plannedSavingsReserve, 100, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendToday, 5_000 - 500 - 100, accuracy: 0.001)
        XCTAssertTrue(result.unscheduledSavingsGoalNames.isEmpty)
    }

    func testGoalWithoutTargetDateIsNotReservedAndIsListedAsUnscheduled() {
        let checking = Account(name: "Checking", type: .checking, balance: 5_000)
        let goal = SavingsGoal(name: "Open-ended Fund", targetAmount: 1_000, currentAmount: 0)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: [goal]
        )
        XCTAssertEqual(result.plannedSavingsReserve, 0, accuracy: 0.001)
        XCTAssertEqual(result.unscheduledSavingsGoalNames, ["Open-ended Fund"])
        // No reserve is taken for it, so this behaves like having no savings goals at all.
        XCTAssertEqual(result.safeToSpendToday, 5_000 - 500, accuracy: 0.001)
    }

    func testLinkedAccountGoalUsesLiveAccountBalanceForRemainingAmount() {
        let checking = Account(name: "Checking", type: .checking, balance: 5_000)
        let savingsAccount = Account(name: "Savings", type: .savings, balance: 400)
        let targetDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let goal = SavingsGoal(name: "Linked Goal", targetAmount: 1_000,
                               targetDate: targetDate, linkedAccount: savingsAccount)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking, savingsAccount], transactions: [], recurring: [], budgets: [], savingsGoals: [goal]
        )
        // remaining = 1000 - 400 (linked balance) = 600; 600/10 = 60/day reserve
        XCTAssertEqual(result.plannedSavingsReserve, 60, accuracy: 0.001)
    }

    // MARK: 7. Safe spend clamps to zero when obligations exceed liquid cash

    func testSafeSpendClampsToZeroWhenObligationsExceedLiquidCash() {
        let checking = Account(name: "Checking", type: .checking, balance: 200)
        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        // 200 - buffer(500) is negative, clamps to 0
        XCTAssertEqual(result.safeToSpendToday, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .pause)
    }

    // MARK: 8. Positive case returns expected safe amount

    func testPositiveCaseReturnsExpectedSafeAmount() {
        let checking = Account(name: "Checking", type: .checking, balance: 3_000)
        let savings  = Account(name: "Savings",  type: .savings,  balance: 2_000)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!

        let income  = RecurringTransaction(title: "Paycheck", amount: 1_000, type: .income,
                                           frequency: .monthly, startDate: tomorrow)
        income.nextDueDate = tomorrow
        let expense = RecurringTransaction(title: "Utilities", amount: 400, type: .expense,
                                           frequency: .monthly, startDate: tomorrow)
        expense.nextDueDate = tomorrow

        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        let goal = SavingsGoal(name: "Goal", targetAmount: 600, currentAmount: 0, targetDate: targetDate)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking, savings], transactions: [], recurring: [income, expense],
            budgets: [], savingsGoals: [goal]
        )
        // liquid 5000, buffer 500 (no spending history), outflow net = +600 -> reserve 0,
        // savings reserve = 600/30 = 20, no budgets so cash side wins
        XCTAssertEqual(result.liquidBalance, 5_000, accuracy: 0.001)
        XCTAssertEqual(result.requiredBuffer, 500, accuracy: 0.001)
        XCTAssertEqual(result.upcomingNetOutflowReserve, 0, accuracy: 0.001)
        XCTAssertEqual(result.plannedSavingsReserve, 20, accuracy: 0.001)
        XCTAssertEqual(result.cashAvailableAfterObligations, 4_480, accuracy: 0.001)
        XCTAssertFalse(result.hasActiveBudgets)
        XCTAssertEqual(result.safeToSpendToday, 4_480, accuracy: 0.001)
    }

    // MARK: 9. Status thresholds

    func testStatusIsPauseWhenSafeSpendIsZero() {
        let checking = Account(name: "Checking", type: .checking, balance: 0)
        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.safeToSpendToday, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .pause)
    }

    func testStatusIsTightWhenSafeSpendIsLowButPositive() {
        // liquid 520 - buffer 500 = 20, below the $25 tight floor
        let checking = Account(name: "Checking", type: .checking, balance: 520)
        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.safeToSpendToday, 20, accuracy: 0.001)
        XCTAssertEqual(result.status, .tight)
    }

    func testStatusIsOnTrackWhenSafeSpendIsComfortablyPositive() {
        // liquid 1500 - buffer 500 = 1000, well above the tight ceiling
        let checking = Account(name: "Checking", type: .checking, balance: 1_500)
        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [], savingsGoals: []
        )
        XCTAssertEqual(result.safeToSpendToday, 1_000, accuracy: 0.001)
        XCTAssertEqual(result.status, .onTrack)
    }

    // MARK: 10. Budgets cap safe spend

    func testBudgetAllowanceCapsSafeSpendBelowCashSide() {
        // Liquid balance is large enough that the budget's per-day allowance is the
        // binding constraint no matter how many days remain in the current period
        // (i.e. this doesn't depend on what day of the month the test runs).
        let checking = Account(name: "Checking", type: .checking, balance: 100_000)
        let budget = Budget(name: "Dining", limitAmount: 300, period: .monthly)
        let expectedAllowance = 300.0 / Double(budget.daysRemainingInCurrentPeriod())

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [budget], savingsGoals: []
        )
        XCTAssertTrue(result.hasActiveBudgets)
        XCTAssertEqual(result.cashAvailableAfterObligations, 99_500, accuracy: 0.001)
        XCTAssertEqual(result.budgetDailyAllowance, expectedAllowance, accuracy: 0.01)
        XCTAssertLessThan(result.budgetDailyAllowance, result.cashAvailableAfterObligations)
        XCTAssertEqual(result.safeToSpendToday, result.budgetDailyAllowance, accuracy: 0.01)
    }

    func testOverspentBudgetContributesZeroToAllowance() {
        let checking = Account(name: "Checking", type: .checking, balance: 10_000)
        let budget = Budget(name: "Dining", limitAmount: 100, period: .monthly)
        let overspend = Transaction(title: "Big Dinner", amount: 500, date: .now, type: .expense)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [overspend], recurring: [], budgets: [budget], savingsGoals: []
        )
        XCTAssertEqual(result.budgetDailyAllowance, 0, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendToday, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .pause)
    }

    func testInactiveBudgetsDoNotConstrainSafeSpend() {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let budget = Budget(name: "Paused Budget", limitAmount: 1, period: .monthly)
        budget.isActive = false

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [budget], savingsGoals: []
        )
        XCTAssertFalse(result.hasActiveBudgets)
        // Falls back to cash-based amount: 1000 - 500 buffer = 500
        XCTAssertEqual(result.safeToSpendToday, 500, accuracy: 0.001)
    }

    func testMultipleBudgetsSumToCombinedDailyAllowance() {
        let checking = Account(name: "Checking", type: .checking, balance: 10_000)
        let dining = Budget(name: "Dining", limitAmount: 300, period: .monthly)
        let transport = Budget(name: "Transport", limitAmount: 90, period: .monthly)

        let result = SafeSpendCalculator.calculate(
            accounts: [checking], transactions: [], recurring: [], budgets: [dining, transport], savingsGoals: []
        )
        let expectedAllowance = SafeSpendCalculator.budgetDailyAllowance(
            budgets: [dining, transport], transactions: []
        )
        XCTAssertEqual(result.budgetDailyAllowance, expectedAllowance, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendToday, expectedAllowance, accuracy: 0.001)
    }
}
