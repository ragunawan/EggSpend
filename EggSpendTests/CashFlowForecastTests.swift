import XCTest
import SwiftData
@testable import EggSpend

final class CashFlowForecastTests: XCTestCase {
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

    // MARK: - liquidBalance

    func testLiquidBalanceIncludesCheckingAndSavingsOnly() {
        let checking   = Account(name: "Checking",   type: .checking,    balance: 1_000)
        let savings    = Account(name: "Savings",    type: .savings,     balance: 2_000)
        let investment = Account(name: "Invest",     type: .investment,  balance: 5_000)
        let credit     = Account(name: "Card",       type: .credit,      balance: 500)
        let loan       = Account(name: "Loan",       type: .loan,        balance: 10_000)

        let result = ForecastEngine.liquidBalance(from: [checking, savings, investment, credit, loan])
        XCTAssertEqual(result, 3_000, accuracy: 0.001)
    }

    func testLiquidBalanceWithNoLiquidAccounts() {
        let investment = Account(name: "Invest", type: .investment, balance: 9_000)
        XCTAssertEqual(ForecastEngine.liquidBalance(from: [investment]), 0, accuracy: 0.001)
    }

    func testLiquidBalanceWithEmptyAccounts() {
        XCTAssertEqual(ForecastEngine.liquidBalance(from: []), 0, accuracy: 0.001)
    }

    func testLiquidBalanceExcludesArchivedCheckingAccount() {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let archivedChecking = Account(name: "Old Checking", type: .checking, balance: 4_000)
        archivedChecking.isArchived = true
        let savings = Account(name: "Savings", type: .savings, balance: 2_000)

        let result = ForecastEngine.liquidBalance(from: [checking, archivedChecking, savings])
        XCTAssertEqual(result, 3_000, accuracy: 0.001)
    }

    // MARK: - averageDailyNetFlow

    func testAverageDailyNetFlowWithNoTransactions() {
        let result = ForecastEngine.averageDailyNetFlow(from: [], lookbackDays: 30)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testAverageDailyNetFlowCalculation() {
        // 3 income transactions totalling $300 in the last 30 days
        let recent = Calendar.current.date(byAdding: .day, value: -10, to: .now)!
        let tx1 = Transaction(title: "Salary", amount: 200, date: recent, type: .income)
        let tx2 = Transaction(title: "Freelance", amount: 100, date: recent, type: .income)

        let result = ForecastEngine.averageDailyNetFlow(from: [tx1, tx2], lookbackDays: 30)
        // Net = 300, lookback = 30 → 10.0/day
        XCTAssertEqual(result, 10.0, accuracy: 0.001)
    }

    func testAverageDailyNetFlowExcludesTransactionsOutsideLookback() {
        // A transaction 90 days ago should not affect a 30-day lookback
        let old    = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        let recent = Calendar.current.date(byAdding: .day, value: -5,  to: .now)!
        let oldTx  = Transaction(title: "Old Income", amount: 1_000, date: old,    type: .income)
        let newTx  = Transaction(title: "New Expense", amount:  60,  date: recent, type: .expense)

        let result = ForecastEngine.averageDailyNetFlow(from: [oldTx, newTx], lookbackDays: 30)
        // Only newTx is in the window: -60 / 30 = -2
        XCTAssertEqual(result, -2.0, accuracy: 0.001)
    }

    func testAverageDailyNetFlowWithMixedTypes() {
        let date   = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let income  = Transaction(title: "Income",  amount: 100, date: date, type: .income)
        let expense = Transaction(title: "Expense", amount:  40, date: date, type: .expense)

        let result = ForecastEngine.averageDailyNetFlow(from: [income, expense], lookbackDays: 60)
        // Net = 60, lookback = 60 → 1.0/day
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testAverageDailyNetFlowExcludesAdjustments() {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let income = Transaction(title: "Income", amount: 100, date: date, type: .income)
        let adjustment = Transaction(title: "Balance adjustment", amount: 500, date: date,
                                     type: .expense, isAdjustment: true)

        let result = ForecastEngine.averageDailyNetFlow(from: [income, adjustment], lookbackDays: 60)
        // Only the real income counts: 100 / 60
        XCTAssertEqual(result, 100.0 / 60.0, accuracy: 0.001)
    }

    func testAverageDailyNetFlowExcludesGeneratedTransactions() {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let income = Transaction(title: "Income", amount: 100, date: date, type: .income)
        let generated = Transaction(title: "Rent", amount: 500, date: date, type: .expense,
                                    isGenerated: true, recurringSourceID: UUID())

        let result = ForecastEngine.averageDailyNetFlow(from: [income, generated], lookbackDays: 60)
        // Only the organic income counts: 100 / 60
        XCTAssertEqual(result, 100.0 / 60.0, accuracy: 0.001)
    }

    // MARK: - upcomingEvents

    func testUpcomingEventsReturnsActiveRecurringWithinHorizon() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let item = RecurringTransaction(title: "Rent", amount: 1_500, type: .expense,
                                        frequency: .monthly, startDate: .now)
        item.nextDueDate = tomorrow

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.first?.title, "Rent")
        XCTAssertEqual(events.first?.amount ?? 0, -1_500, accuracy: 0.001)
    }

    func testUpcomingEventsExcludesInactiveItems() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let item = RecurringTransaction(title: "Paused", amount: 50, type: .expense,
                                        frequency: .weekly, startDate: .now)
        item.nextDueDate = tomorrow
        item.isActive = false

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        XCTAssertTrue(events.isEmpty)
    }

    func testUpcomingEventsExcludesExpiredItems() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let tomorrow  = Calendar.current.date(byAdding: .day, value:  1, to: .now)!
        let item = RecurringTransaction(title: "Expired", amount: 20, type: .expense,
                                        frequency: .weekly, startDate: .now)
        item.nextDueDate = tomorrow
        item.endDate     = yesterday

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        XCTAssertTrue(events.isEmpty)
    }

    func testUpcomingEventsIncomeIsPositive() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let item = RecurringTransaction(title: "Salary", amount: 3_000, type: .income,
                                        frequency: .monthly, startDate: .now)
        item.nextDueDate = tomorrow

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        XCTAssertEqual(events.first?.amount ?? 0, 3_000, accuracy: 0.001)
    }

    func testUpcomingEventsWeeklyRepeatsTwiceIn14Days() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let item = RecurringTransaction(title: "Gym", amount: 30, type: .expense,
                                        frequency: .weekly, startDate: .now)
        item.nextDueDate = tomorrow

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 14)
        // tomorrow + 8 days = 2 occurrences within 14 days
        XCTAssertEqual(events.count, 2)
    }

    func testUpcomingEventsFastForwardsPastDueDate() {
        // nextDueDate is 10 days ago — should fast-forward, not include past dates
        let pastDue = Calendar.current.date(byAdding: .day, value: -10, to: .now)!
        let item = RecurringTransaction(title: "Netflix", amount: 18, type: .expense,
                                        frequency: .monthly, startDate: pastDue)
        item.nextDueDate = pastDue

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        for ev in events {
            XCTAssertGreaterThanOrEqual(ev.date, Calendar.current.startOfDay(for: .now))
        }
    }

    func testUpcomingEventsIncludesUnmaterializedItemDueToday() {
        // An item created mid-session with nextDueDate == today and not yet turned into a
        // Transaction by launch processing should still surface as a real pending event —
        // same-day occurrences must not be dropped (pins the "no <= now drop" invariant).
        let item = RecurringTransaction(title: "Coffee Subscription", amount: 12, type: .expense,
                                        frequency: .monthly, startDate: .now)
        item.nextDueDate = .now

        let events = ForecastEngine.upcomingEvents(from: [item], horizonDays: 30)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(Calendar.current.isDateInToday(events.first?.date ?? .distantPast))
    }

    // MARK: - buildForecast

    func testBuildForecastPointCountEqualsHorizonPlusOne() {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let (points, _) = ForecastEngine.buildForecast(
            accounts: [checking], transactions: [], recurring: [], horizonDays: 30
        )
        // today + 30 days = 31 points
        XCTAssertEqual(points.count, 31)
    }

    func testBuildForecastAnchorIsCurrentBalance() {
        let checking = Account(name: "Checking", type: .checking, balance: 5_000)
        let savings  = Account(name: "Savings",  type: .savings,  balance: 2_000)

        let (points, _) = ForecastEngine.buildForecast(
            accounts: [checking, savings], transactions: [], recurring: [], horizonDays: 7
        )
        XCTAssertEqual(points.first?.balance ?? 0, 7_000, accuracy: 0.001)
        XCTAssertFalse(points.first?.isProjected ?? true, "Day 0 must not be marked as projected")
    }

    func testBuildForecastAppliesRecurringEventOnScheduledDay() {
        let checking = Account(name: "Checking", type: .checking, balance: 2_000)

        // Rent due in 5 days
        let in5 = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let rent = RecurringTransaction(title: "Rent", amount: 800, type: .expense,
                                        frequency: .monthly, startDate: in5)
        rent.nextDueDate = in5

        let (points, _) = ForecastEngine.buildForecast(
            accounts: [checking], transactions: [], recurring: [rent], horizonDays: 10
        )

        // Day 4 should not yet have rent applied; day 5 should be $800 lower than day 4 (minus drift)
        let day4 = points[4].balance
        let day5 = points[5].balance
        // With zero drift and rent on day 5: day5 = day4 - 800
        XCTAssertEqual(day4 - day5, 800, accuracy: 1.0)
    }

    func testBuildForecastProjectedFlagIsSetForFutureDays() {
        let checking = Account(name: "Checking", type: .checking, balance: 500)
        let (points, _) = ForecastEngine.buildForecast(
            accounts: [checking], transactions: [], recurring: [], horizonDays: 5
        )
        XCTAssertFalse(points[0].isProjected)
        for p in points.dropFirst() {
            XCTAssertTrue(p.isProjected)
        }
    }

    func testBuildForecastEventsMatchUpcomingEvents() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let item = RecurringTransaction(title: "Salary", amount: 3_000, type: .income,
                                        frequency: .monthly, startDate: .now)
        item.nextDueDate = tomorrow

        let (_, events) = ForecastEngine.buildForecast(
            accounts: [], transactions: [], recurring: [item], horizonDays: 30
        )
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.amount > 0 }, "Salary must be positive")
    }

    func testBuildForecastDoesNotDoubleCountMaterializedRecurring() {
        // Rent's most recent occurrence already materialized into a Transaction today
        // (isGenerated == true), and nextDueDate has been advanced 30 days out by launch
        // processing. Rent should show up exactly once in the forecast inputs: as a
        // generated transaction excluded from drift, and as a single upcoming event.
        let rent = RecurringTransaction(title: "Rent", amount: 1_500, type: .expense,
                                        frequency: .monthly, startDate: .now)
        let in30 = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        rent.nextDueDate = in30

        let materialized = Transaction(title: "Rent", amount: 1_500, date: .now, type: .expense,
                                       isGenerated: true, recurringSourceID: rent.id,
                                       recurringDueDate: .now)

        let drift = ForecastEngine.averageDailyNetFlow(from: [materialized], lookbackDays: 60)
        XCTAssertEqual(drift, 0, accuracy: 0.001, "Generated history must not feed the drift")

        let events = ForecastEngine.upcomingEvents(from: [rent], horizonDays: 60)
        XCTAssertEqual(events.count, 1, "Rent must appear exactly once as an upcoming event")
        XCTAssertTrue(Calendar.current.isDate(events.first?.date ?? .distantPast, inSameDayAs: in30))
    }
}
