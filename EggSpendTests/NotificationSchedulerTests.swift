import XCTest
import SwiftData
import UserNotifications
@testable import EggSpend

final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var authorizationGranted = true
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationCallCount = 0

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        requestAuthorizationCallCount += 1
        completion(authorizationGranted, nil)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler: (@Sendable (Error?) -> Void)?) {
        addedRequests.append(request)
        withCompletionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func getAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        completion(authorizationStatus)
    }
}

final class NotificationSchedulerTests: XCTestCase {
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

    // MARK: reminderFireDate

    func testReminderFireDateComputesCorrectOffset() {
        let now = Date.now
        let due = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = due
        item.reminderEnabled = true
        item.reminderDaysBefore = 3

        let fireDate = NotificationScheduler.reminderFireDate(for: item, now: now)
        let expected = Calendar.current.date(byAdding: .day, value: -3, to: due)!
        XCTAssertNotNil(fireDate)
        XCTAssertEqual(fireDate!.timeIntervalSinceReferenceDate, expected.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testReminderFireDateNilWhenDisabled() {
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        item.reminderEnabled = false
        XCTAssertNil(NotificationScheduler.reminderFireDate(for: item))
    }

    func testReminderFireDateNilWhenInactive() {
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        item.reminderEnabled = true
        item.isActive = false
        XCTAssertNil(NotificationScheduler.reminderFireDate(for: item))
    }

    func testReminderFireDateNilWhenPastEndDate() {
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        item.endDate = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        item.reminderEnabled = true
        XCTAssertNil(NotificationScheduler.reminderFireDate(for: item))
    }

    func testReminderFireDateNilWhenAlreadyInPast() {
        let now = Date.now
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        item.reminderEnabled = true
        item.reminderDaysBefore = 5 // fire date would be 4 days in the past
        XCTAssertNil(NotificationScheduler.reminderFireDate(for: item, now: now))
    }

    // MARK: billReminderRequest

    func testBillReminderRequestContent() {
        let item = RecurringTransaction(title: "Netflix", amount: 17.99, type: .expense, frequency: .monthly)
        let fireDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let request = NotificationScheduler.billReminderRequest(for: item, fireDate: fireDate)
        XCTAssertEqual(request.identifier, NotificationScheduler.billReminderIdentifier(for: item.id))
        XCTAssertTrue(request.content.title.contains("Netflix"))
    }

    // MARK: syncReminder / cancelReminder

    func testSyncReminderRemovesThenAddsWhenEligible() {
        let mock = MockNotificationCenter()
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        item.reminderEnabled = true

        NotificationScheduler.syncReminder(for: item, center: mock)

        let id = NotificationScheduler.billReminderIdentifier(for: item.id)
        XCTAssertEqual(mock.removedIdentifiers, [id])
        XCTAssertEqual(mock.addedRequests.count, 1)
        XCTAssertEqual(mock.addedRequests.first?.identifier, id)
    }

    func testSyncReminderOnlyRemovesWhenIneligible() {
        let mock = MockNotificationCenter()
        let item = RecurringTransaction(title: "Rent", amount: 1000, type: .expense, frequency: .monthly)
        item.nextDueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        item.reminderEnabled = false

        NotificationScheduler.syncReminder(for: item, center: mock)

        XCTAssertEqual(mock.removedIdentifiers.count, 1)
        XCTAssertTrue(mock.addedRequests.isEmpty)
    }

    func testCancelReminderRemovesIdentifier() {
        let mock = MockNotificationCenter()
        let id = UUID()
        NotificationScheduler.cancelReminder(for: id, center: mock)
        XCTAssertEqual(mock.removedIdentifiers, [NotificationScheduler.billReminderIdentifier(for: id)])
    }

    // MARK: budget alerts

    func testBudgetAlertIdentifierIncludesThreshold() {
        let id = UUID()
        XCTAssertTrue(NotificationScheduler.budgetAlertIdentifier(for: id, threshold: .nearLimit).hasSuffix("-80"))
        XCTAssertTrue(NotificationScheduler.budgetAlertIdentifier(for: id, threshold: .exceeded).hasSuffix("-100"))
    }

    func testBudgetAlertContentForNearLimitVsExceeded() {
        let budget = Budget(name: "Groceries", limitAmount: 100, period: .monthly)
        let near = NotificationScheduler.budgetAlertContent(for: budget, threshold: .nearLimit, progress: 0.85)
        let exceeded = NotificationScheduler.budgetAlertContent(for: budget, threshold: .exceeded, progress: 1.1)
        XCTAssertNotEqual(near.title, exceeded.title)
    }

    func testFireBudgetAlertAddsExactlyOneRequest() {
        let mock = MockNotificationCenter()
        let budget = Budget(name: "Groceries", limitAmount: 100, period: .monthly)
        NotificationScheduler.fireBudgetAlert(for: budget, threshold: .nearLimit, progress: 0.85, center: mock)
        XCTAssertEqual(mock.addedRequests.count, 1)
    }

    // MARK: authorization

    func testRequestAuthorizationIfNeededSkipsPromptWhenAlreadyDetermined() {
        let mock = MockNotificationCenter()
        mock.authorizationStatus = .authorized
        let expectation = expectation(description: "completion")
        NotificationScheduler.requestAuthorizationIfNeeded(center: mock) { granted in
            XCTAssertTrue(granted)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 0)
    }

    // MARK: BudgetAlertCoordinator

    func testCheckBudgetsFiresForEligibleBudgetOnly() throws {
        let mock = MockNotificationCenter()
        let enabledBudget = Budget(name: "Enabled", limitAmount: 100, period: .monthly)
        enabledBudget.alertsEnabled = true
        let disabledBudget = Budget(name: "Disabled", limitAmount: 100, period: .monthly)
        disabledBudget.alertsEnabled = false

        let tx = Transaction(title: "Spend", amount: 90, type: .expense)

        BudgetAlertCoordinator.checkBudgets([enabledBudget, disabledBudget], transactions: [tx], center: mock)

        XCTAssertEqual(mock.addedRequests.count, 1)
    }

    func testCheckBudgetsContextOverloadFiltersActiveAndEnabledOnly() throws {
        let mock = MockNotificationCenter()
        let eligible = Budget(name: "Eligible", limitAmount: 100, period: .monthly)
        eligible.alertsEnabled = true
        let inactive = Budget(name: "Inactive", limitAmount: 100, period: .monthly)
        inactive.alertsEnabled = true
        inactive.isActive = false

        context.insert(eligible)
        context.insert(inactive)
        context.insert(Transaction(title: "Spend", amount: 90, type: .expense))
        try context.save()

        BudgetAlertCoordinator.checkBudgets(context: context, center: mock)

        XCTAssertEqual(mock.addedRequests.count, 1)
    }

    /// Pins the explicit `context.save()` added to the context-based overload: alert
    /// dedupe state mutated by `evaluateAlert` must be durably persisted, not just
    /// held in the in-memory objects, otherwise alerts would re-fire on next launch.
    func testCheckBudgetsContextOverloadPersistsAlertStateAcrossFreshContext() throws {
        let mock = MockNotificationCenter()
        let budget = Budget(name: "Groceries", limitAmount: 100, period: .monthly)
        budget.alertsEnabled = true
        let budgetID = budget.id

        context.insert(budget)
        context.insert(Transaction(title: "Spend", amount: 90, type: .expense))
        try context.save()

        BudgetAlertCoordinator.checkBudgets(context: context, center: mock)
        XCTAssertEqual(mock.addedRequests.count, 1)

        // Re-fetch via a brand-new ModelContext on the same container to confirm the
        // threshold/period mutations were actually saved, not just held in-memory.
        let freshContext = ModelContext(container)
        let refetched = try freshContext.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.id == budgetID }
        ))
        XCTAssertEqual(refetched.first?.lastAlertedThresholdRaw, BudgetAlertThreshold.nearLimit.rawValue)
        XCTAssertNotNil(refetched.first?.lastAlertedPeriodStart)
    }
}
