import XCTest
import SwiftData
@testable import EggSpend

final class DuplicateSweeperTests: XCTestCase {
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

    /// Builds a "generated" transaction with the recurring linking fields
    /// populated, mimicking `processRecurringTransactions`'s construction.
    /// `createdAt` and `id` are mutated after construction since the
    /// designated initializer always stamps `.now` / `UUID()`.
    @discardableResult
    private func makeGenerated(
        title: String = "Netflix",
        amount: Double = 50,
        type: TransactionType = .expense,
        account: Account?,
        sourceID: UUID,
        dueDate: Date,
        createdAt: Date,
        id: UUID = UUID()
    ) -> Transaction {
        let tx = Transaction(
            title: title,
            amount: amount,
            date: dueDate,
            type: type,
            account: account,
            isGenerated: true,
            recurringSourceID: sourceID,
            recurringDueDate: dueDate
        )
        tx.createdAt = createdAt
        tx.id = id
        context.insert(tx)
        return tx
    }

    // MARK: 1. Acceptance test

    func testAcceptance_DoubleAppliedDuplicate_ResolvesToOneWithBalanceCorrected() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)

        let sourceID = UUID()
        let dueDate = Date.now

        // Simulate two devices independently materializing and applying the
        // same occurrence: balance already reflects BOTH applications.
        let earlier = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                     dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-60))
        let later = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                   dueDate: dueDate, createdAt: dueDate)
        AccountBalanceService.apply(earlier, to: account)
        AccountBalanceService.apply(later, to: account)
        XCTAssertEqual(account.balance, 900, accuracy: 0.001)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 1)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, earlier.id)
        // Corrected by exactly one application: 900 + 50 = 950.
        XCTAssertEqual(account.balance, 950, accuracy: 0.001)
    }

    // MARK: 2. Nil-key exclusion

    func testNilKeyExclusion_ManualLegacyAndAdjustmentRowsSurvive() {
        let account = Account(name: "Checking", type: .checking, balance: 500)
        context.insert(account)

        let manual = Transaction(title: "Coffee", amount: 5, type: .expense, account: account)
        context.insert(manual)

        // Legacy-generated: isGenerated true but recurringSourceID nil.
        let legacy = Transaction(title: "Old gen", amount: 10, type: .expense, account: account,
                                  isGenerated: true, recurringSourceID: nil, recurringDueDate: nil)
        context.insert(legacy)

        let adjustment = Transaction(title: "Balance adjustment", amount: 20, type: .income,
                                      account: account, isGenerated: false, isAdjustment: true)
        context.insert(adjustment)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 0)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 3)
    }

    // MARK: 3. Different sourceIDs, same day

    func testDifferentSourceIDs_SameDay_NotGrouped() {
        let account = Account(name: "Checking", type: .checking, balance: 500)
        context.insert(account)
        let dueDate = Date.now

        makeGenerated(account: account, sourceID: UUID(), dueDate: dueDate, createdAt: dueDate)
        makeGenerated(account: account, sourceID: UUID(), dueDate: dueDate, createdAt: dueDate)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 0)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 2)
    }

    // MARK: 4. Same sourceID, different days

    func testSameSourceID_DifferentDays_NotGrouped() {
        let account = Account(name: "Checking", type: .checking, balance: 500)
        context.insert(account)
        let sourceID = UUID()
        let day1 = Date.now
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!

        makeGenerated(account: account, sourceID: sourceID, dueDate: day1, createdAt: day1)
        makeGenerated(account: account, sourceID: sourceID, dueDate: day2, createdAt: day2)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 0)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 2)
    }

    // MARK: 5. Deterministic survivor on createdAt tie, insertion-order independent

    func testDeterministicSurvivor_OnCreatedAtTie_LexicographicallySmallerIDWins() {
        let account = Account(name: "Checking", type: .checking, balance: 500)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now
        let sameCreatedAt = Date.now

        let idA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let idB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        makeGenerated(account: account, sourceID: sourceID, dueDate: dueDate,
                      createdAt: sameCreatedAt, id: idA)
        makeGenerated(account: account, sourceID: sourceID, dueDate: dueDate,
                      createdAt: sameCreatedAt, id: idB)

        DuplicateSweeper.sweep(context: context)

        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, idA)

        // Insertion-order independence: reverse insertion order in a second
        // container should converge on the same survivor id.
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self, CategoryRule.self])
        let config2 = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container2 = try! ModelContainer(for: schema, configurations: [config2])
        let context2 = ModelContext(container2)

        let account2 = Account(name: "Checking", type: .checking, balance: 500)
        context2.insert(account2)

        let txB = Transaction(title: "Netflix", amount: 50, date: dueDate, type: .expense,
                               account: account2, isGenerated: true, recurringSourceID: sourceID,
                               recurringDueDate: dueDate)
        txB.createdAt = sameCreatedAt
        txB.id = idB
        context2.insert(txB)

        let txA = Transaction(title: "Netflix", amount: 50, date: dueDate, type: .expense,
                               account: account2, isGenerated: true, recurringSourceID: sourceID,
                               recurringDueDate: dueDate)
        txA.createdAt = sameCreatedAt
        txA.id = idA
        context2.insert(txA)

        DuplicateSweeper.sweep(context: context2)

        let remaining2 = (try? context2.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining2.count, 1)
        XCTAssertEqual(remaining2.first?.id, idA)
    }

    // MARK: 6. Idempotence

    func testIdempotence_SecondSweepIsNoOp() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now

        let earlier = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                     dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-60))
        let later = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                   dueDate: dueDate, createdAt: dueDate)
        AccountBalanceService.apply(earlier, to: account)
        AccountBalanceService.apply(later, to: account)

        let firstPass = DuplicateSweeper.sweep(context: context)
        XCTAssertEqual(firstPass, 1)
        let balanceAfterFirstPass = account.balance

        let secondPass = DuplicateSweeper.sweep(context: context)
        XCTAssertEqual(secondPass, 0)
        XCTAssertEqual(account.balance, balanceAfterFirstPass, accuracy: 0.001)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: 7. Loser without account

    func testLoserWithoutAccount_DeletedWithoutCrashOrBalanceChange() {
        let account = Account(name: "Checking", type: .checking, balance: 500)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now

        // Neither row is linked to an account.
        let earlier = makeGenerated(account: nil, sourceID: sourceID, dueDate: dueDate,
                                     createdAt: dueDate.addingTimeInterval(-60))
        makeGenerated(account: nil, sourceID: sourceID, dueDate: dueDate, createdAt: dueDate)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(account.balance, 500, accuracy: 0.001)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, earlier.id)
    }

    // MARK: 8. Different-amount duplicates

    func testDifferentAmountDuplicates_EachLoserReversedByOwnAmount() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now

        let earlier = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                     dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-120))
        let middle = makeGenerated(amount: 65, account: account, sourceID: sourceID,
                                    dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-60))
        let latest = makeGenerated(amount: 80, account: account, sourceID: sourceID,
                                    dueDate: dueDate, createdAt: dueDate)
        AccountBalanceService.apply(earlier, to: account)
        AccountBalanceService.apply(middle, to: account)
        AccountBalanceService.apply(latest, to: account)
        // 1000 - 50 - 65 - 80 = 805
        XCTAssertEqual(account.balance, 805, accuracy: 0.001)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 2)
        // Survivor is `earlier` (50); the 65 and 80 losers are reversed:
        // 805 + 65 + 80 = 950, leaving only the earlier's -50 applied (1000 - 50 = 950).
        XCTAssertEqual(account.balance, 950, accuracy: 0.001)
    }

    // MARK: 9. Triplet

    func testTriplet_KeepsEarliestRemovesTwoReturnsTwo() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now

        let earlier = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                     dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-120))
        let middle = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                    dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-60))
        let latest = makeGenerated(amount: 50, account: account, sourceID: sourceID,
                                    dueDate: dueDate, createdAt: dueDate)
        AccountBalanceService.apply(earlier, to: account)
        AccountBalanceService.apply(middle, to: account)
        AccountBalanceService.apply(latest, to: account)
        XCTAssertEqual(account.balance, 850, accuracy: 0.001)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 2)
        let remaining = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, earlier.id)
        // Corrected by two applications: 850 + 50 + 50 = 950.
        XCTAssertEqual(account.balance, 950, accuracy: 0.001)
    }

    // MARK: 10. Income-type duplicates

    func testIncomeDuplicates_ReversalSubtractsSignedAmount() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        let sourceID = UUID()
        let dueDate = Date.now

        let earlier = makeGenerated(amount: 200, type: .income, account: account, sourceID: sourceID,
                                     dueDate: dueDate, createdAt: dueDate.addingTimeInterval(-60))
        let later = makeGenerated(amount: 200, type: .income, account: account, sourceID: sourceID,
                                   dueDate: dueDate, createdAt: dueDate)
        AccountBalanceService.apply(earlier, to: account)
        AccountBalanceService.apply(later, to: account)
        XCTAssertEqual(account.balance, 1400, accuracy: 0.001)

        let removed = DuplicateSweeper.sweep(context: context)

        XCTAssertEqual(removed, 1)
        // Removing the duplicate income row should bring balance DOWN by 200.
        XCTAssertEqual(account.balance, 1200, accuracy: 0.001)
    }
}
