import XCTest
import SwiftData
@testable import EggSpend

final class BalanceSnapshotTests: XCTestCase {
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

    func testCaptureCreatesOneSnapshotPerAccountPerDay() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 5000)
        context.insert(checking)
        context.insert(savings)
        try context.save()

        let written = BalanceSnapshotService.captureIfNeeded(accounts: [checking, savings], context: context)
        XCTAssertEqual(written, 2)

        let snapshots = try context.fetch(FetchDescriptor<BalanceSnapshot>())
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.contains { $0.accountID == checking.id && $0.balance == 1000 })
        XCTAssertTrue(snapshots.contains { $0.accountID == savings.id && $0.balance == 5000 })
    }

    func testCaptureIsIdempotentSameDay() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(checking)
        try context.save()

        let firstWrite = BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context)
        XCTAssertEqual(firstWrite, 1)

        let secondWrite = BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context)
        XCTAssertEqual(secondWrite, 0)

        let snapshots = try context.fetch(FetchDescriptor<BalanceSnapshot>())
        XCTAssertEqual(snapshots.count, 1)
    }

    func testCaptureUpdatesExistingRowWhenBalanceChangesSameDay() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(checking)
        try context.save()

        BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context)

        checking.balance = 1500
        try context.save()

        let written = BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context)
        XCTAssertEqual(written, 1)

        let snapshots = try context.fetch(FetchDescriptor<BalanceSnapshot>())
        XCTAssertEqual(snapshots.count, 1, "same-day recapture should update the existing row, not insert a second one")
        XCTAssertEqual(snapshots.first?.balance, 1500)
    }

    func testCaptureDayRolloverCreatesNewRow() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(checking)
        try context.save()

        let calendar = Calendar.current
        let day1 = Date.now
        BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context, date: day1, calendar: calendar)

        checking.balance = 1200
        try context.save()

        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        let written = BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context, date: day2, calendar: calendar)
        XCTAssertEqual(written, 1)

        let snapshots = try context.fetch(FetchDescriptor<BalanceSnapshot>())
        XCTAssertEqual(snapshots.count, 2, "a new calendar day should create a new row, preserving the prior day's snapshot")
    }

    func testCaptureNormalizesDateToStartOfDay() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(checking)
        try context.save()

        let calendar = Calendar.current
        let afternoon = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: Date.now)!
        BalanceSnapshotService.captureIfNeeded(accounts: [checking], context: context, date: afternoon, calendar: calendar)

        let snapshots = try context.fetch(FetchDescriptor<BalanceSnapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.date, calendar.startOfDay(for: afternoon))
    }
}
