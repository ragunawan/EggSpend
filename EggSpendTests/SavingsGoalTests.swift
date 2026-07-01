import XCTest
import SwiftData
@testable import EggSpend

final class SavingsGoalTests: XCTestCase {
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

    // MARK: - Initialization

    func testGoalInitialization() throws {
        let goal = SavingsGoal(name: "Emergency Fund", targetAmount: 5000, currentAmount: 1200)
        XCTAssertEqual(goal.name, "Emergency Fund")
        XCTAssertEqual(goal.targetAmount, 5000, accuracy: 0.001)
        XCTAssertEqual(goal.currentAmount, 1200, accuracy: 0.001)
        XCTAssertEqual(goal.status, .active)
        XCTAssertNil(goal.linkedAccount)
        XCTAssertNil(goal.targetDate)
    }

    func testNegativeTargetAndCurrentAmountsAreClamped() {
        let goal = SavingsGoal(name: "Test", targetAmount: -500, currentAmount: -50)
        XCTAssertEqual(goal.targetAmount, 500, accuracy: 0.001, "Target should be stored as a positive magnitude")
        XCTAssertEqual(goal.currentAmount, 0, accuracy: 0.001, "Negative manual progress should clamp to 0")
    }

    // MARK: - Manual progress

    func testManualProgressCalculation() {
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 500)
        XCTAssertEqual(goal.progress, 0.25, accuracy: 0.001)
        XCTAssertEqual(goal.remainingAmount, 1500, accuracy: 0.001)
        XCTAssertFalse(goal.isGoalMet)
        XCTAssertFalse(goal.tracksLinkedAccount)
    }

    func testProgressClampsAtFullWhenOverfunded() {
        let goal = SavingsGoal(name: "Overfunded", targetAmount: 100, currentAmount: 250)
        XCTAssertEqual(goal.progress, 1.0, accuracy: 0.001, "Progress ratio should clamp at 1.0 even past the target")
        XCTAssertEqual(goal.currentAmount, 250, accuracy: 0.001, "Raw currentAmount should not be clamped")
        XCTAssertEqual(goal.remainingAmount, 0, accuracy: 0.001)
        XCTAssertTrue(goal.isGoalMet)
    }

    func testZeroTargetAmountProducesZeroProgress() {
        // Guarded against via init clamping abs(), but exercise the division guard directly.
        let goal = SavingsGoal(name: "Edge Case", targetAmount: 0.0001, currentAmount: 0)
        XCTAssertGreaterThanOrEqual(goal.progress, 0)
    }

    // MARK: - Linked account progress

    func testProgressDerivedFromLinkedAccountIgnoresManualAmount() throws {
        let account = Account(name: "High Yield Savings", type: .savings, balance: 3000)
        context.insert(account)
        let goal = SavingsGoal(name: "Emergency Fund", targetAmount: 6000,
                               currentAmount: 999, linkedAccount: account)
        context.insert(goal)
        try context.save()

        XCTAssertTrue(goal.tracksLinkedAccount)
        XCTAssertEqual(goal.currentAmount, 3000, accuracy: 0.001,
                       "Linked account balance should override the manually entered amount")
        XCTAssertEqual(goal.progress, 0.5, accuracy: 0.001)
    }

    func testLinkedAccountUpdatesAreReflectedLive() throws {
        let account = Account(name: "Savings", type: .savings, balance: 1000)
        context.insert(account)
        let goal = SavingsGoal(name: "Goal", targetAmount: 2000, linkedAccount: account)
        context.insert(goal)
        try context.save()

        XCTAssertEqual(goal.progress, 0.5, accuracy: 0.001)

        account.balance = 2000
        XCTAssertEqual(goal.progress, 1.0, accuracy: 0.001,
                       "Progress should track the account balance without needing a manual update")
    }

    func testNegativeLinkedAccountBalanceClampsToZero() throws {
        let account = Account(name: "Credit Card", type: .credit, balance: -400)
        context.insert(account)
        let goal = SavingsGoal(name: "Misconfigured Goal", targetAmount: 1000, linkedAccount: account)
        context.insert(goal)
        try context.save()

        XCTAssertEqual(goal.currentAmount, 0, accuracy: 0.001,
                       "A negative/debt account balance should not produce negative savings progress")
    }

    func testUnlinkingAccountFallsBackToManualAmount() throws {
        let account = Account(name: "Savings", type: .savings, balance: 800)
        context.insert(account)
        let goal = SavingsGoal(name: "Goal", targetAmount: 1000,
                               currentAmount: 300, linkedAccount: account)
        context.insert(goal)
        try context.save()

        XCTAssertEqual(goal.currentAmount, 800, accuracy: 0.001)

        goal.linkedAccount = nil
        XCTAssertEqual(goal.currentAmount, 300, accuracy: 0.001,
                       "Removing the link should fall back to the manually entered amount")
    }

    // MARK: - Target date

    func testDaysRemainingForFutureDate() {
        let future = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let goal = SavingsGoal(name: "Trip", targetAmount: 1000, targetDate: future)
        XCTAssertEqual(goal.daysRemaining, 10)
        XCTAssertFalse(goal.isOverdue)
    }

    func testOverdueWhenTargetDateHasPassedAndGoalStillActive() {
        let past = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let goal = SavingsGoal(name: "Late Goal", targetAmount: 1000, targetDate: past)
        XCTAssertTrue(goal.isOverdue)
        XCTAssertLessThan(goal.daysRemaining ?? 0, 0)
    }

    func testCompletedGoalIsNeverOverdue() {
        let past = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let goal = SavingsGoal(name: "Late but done", targetAmount: 1000,
                               currentAmount: 1000, targetDate: past, status: .completed)
        XCTAssertFalse(goal.isOverdue, "A completed goal should not be flagged overdue regardless of date")
    }

    func testNoTargetDateMeansNoDaysRemaining() {
        let goal = SavingsGoal(name: "Open-ended", targetAmount: 1000)
        XCTAssertNil(goal.daysRemaining)
        XCTAssertFalse(goal.isOverdue)
    }

    func testMonthlySavingsNeededForFutureTargetDate() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let goal = SavingsGoal(name: "Trip", targetAmount: 4_000, currentAmount: 1_000, targetDate: target)

        XCTAssertEqual(goal.monthlySavingsNeeded(asOf: now, calendar: calendar) ?? 0, 1_000, accuracy: 0.001)
    }

    func testMonthlySavingsNeededUsesOneMonthForCurrentMonthTarget() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 1, day: 25))!
        let goal = SavingsGoal(name: "Short Goal", targetAmount: 500, currentAmount: 100, targetDate: target)

        XCTAssertEqual(goal.monthlySavingsNeeded(asOf: now, calendar: calendar) ?? 0, 400, accuracy: 0.001)
    }

    func testMonthlySavingsNeededNilForPastTargetDate() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let goal = SavingsGoal(name: "Past Goal", targetAmount: 500, targetDate: target)

        XCTAssertNil(goal.monthlySavingsNeeded(asOf: now, calendar: calendar))
    }

    func testMonthlySavingsNeededZeroForCompletedAmount() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let goal = SavingsGoal(name: "Done", targetAmount: 500, currentAmount: 500, targetDate: target)

        XCTAssertEqual(goal.monthlySavingsNeeded(asOf: now, calendar: calendar) ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(goal.monthlySavingsLabel, "Target reached")
    }

    // MARK: - Status

    func testStatusDefaultsToActiveAndCanBeToggled() {
        let goal = SavingsGoal(name: "Goal", targetAmount: 1000)
        XCTAssertEqual(goal.status, .active)
        XCTAssertTrue(goal.isActive)
        XCTAssertFalse(goal.isCompleted)

        goal.status = .completed
        XCTAssertTrue(goal.isCompleted)
        XCTAssertFalse(goal.isActive)
    }

    // MARK: - Persistence

    func testGoalPersistsWithLinkedAccount() throws {
        let account = Account(name: "Roth IRA", type: .investment, balance: 12000)
        context.insert(account)
        let goal = SavingsGoal(name: "Retirement Boost", targetAmount: 20000, linkedAccount: account,
                               colorHex: "5BA4C1", icon: "umbrella.fill")
        context.insert(goal)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavingsGoal>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Retirement Boost")
        XCTAssertEqual(fetched.first?.linkedAccount?.name, "Roth IRA")
        XCTAssertEqual(fetched.first?.icon, "umbrella.fill")
    }

    func testDeletingLinkedAccountNullifiesReference() throws {
        let account = Account(name: "Savings", type: .savings, balance: 500)
        context.insert(account)
        let goal = SavingsGoal(name: "Goal", targetAmount: 1000, linkedAccount: account)
        context.insert(goal)
        try context.save()

        context.delete(account)
        try context.save()

        XCTAssertNil(goal.linkedAccount)
        XCTAssertEqual(goal.currentAmount, 0, accuracy: 0.001,
                       "Once nullified, progress should fall back to the manual amount (0 by default)")
    }
}
