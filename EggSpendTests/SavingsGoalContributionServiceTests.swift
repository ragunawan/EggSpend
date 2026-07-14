import XCTest
import SwiftData
@testable import EggSpend

final class SavingsGoalContributionServiceTests: XCTestCase {
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

    // MARK: - Manually-tracked goal

    func testApplyCreditsManuallyTrackedGoal() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 100)
        let transfer = Transfer(amount: 300, fromAccount: checking, toAccount: nil, savingsGoal: goal)
        context.insert(checking)
        context.insert(goal)
        context.insert(transfer)

        SavingsGoalContributionService.apply(transfer)

        XCTAssertEqual(goal.manualCurrentAmount, 400, accuracy: 0.001)
    }

    func testReverseDebitsManuallyTrackedGoal() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 100)
        let transfer = Transfer(amount: 300, fromAccount: checking, toAccount: nil, savingsGoal: goal)
        context.insert(checking)
        context.insert(goal)
        context.insert(transfer)

        SavingsGoalContributionService.apply(transfer)
        SavingsGoalContributionService.reverse(transfer)

        XCTAssertEqual(goal.manualCurrentAmount, 100, accuracy: 0.001)
    }

    func testReverseNeverDropsManualAmountBelowZero() throws {
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 50)
        let transfer = Transfer(amount: 300, fromAccount: nil, toAccount: nil, savingsGoal: goal)
        context.insert(goal)
        context.insert(transfer)

        // Reverse without a matching apply (e.g. data drift) shouldn't underflow.
        SavingsGoalContributionService.reverse(transfer)

        XCTAssertEqual(goal.manualCurrentAmount, 0, accuracy: 0.001)
    }

    // MARK: - No-ops

    func testApplyNoOpsWhenTransferHasNoGoal() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let transfer = Transfer(amount: 300, fromAccount: checking, toAccount: nil)
        context.insert(checking)
        context.insert(transfer)

        // Should not crash and should not touch any goal state.
        SavingsGoalContributionService.apply(transfer)
        SavingsGoalContributionService.reverse(transfer)
    }

    func testApplyDoesNotDoubleCountForAccountLinkedGoal() throws {
        // A goal linked to an account already derives progress from the live
        // balance, so tagging a transfer into it must not also bump the
        // manual amount — that would double-count the same money.
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let goal = SavingsGoal(name: "Down Payment", targetAmount: 10_000, linkedAccount: savings)
        let transfer = Transfer(amount: 300, fromAccount: checking, toAccount: savings, savingsGoal: goal)
        context.insert(savings)
        context.insert(checking)
        context.insert(goal)
        context.insert(transfer)

        SavingsGoalContributionService.apply(transfer)

        XCTAssertEqual(goal.manualCurrentAmount, 0, accuracy: 0.001)
    }

    // MARK: - Edit

    func testEditingContributionAmountRebalancesGoal() throws {
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 0)
        let transfer = Transfer(amount: 200, fromAccount: nil, toAccount: nil, savingsGoal: goal)
        context.insert(goal)
        context.insert(transfer)

        SavingsGoalContributionService.apply(transfer)
        XCTAssertEqual(goal.manualCurrentAmount, 200, accuracy: 0.001)

        SavingsGoalContributionService.reverse(transfer)
        transfer.amount = 500
        SavingsGoalContributionService.apply(transfer)

        XCTAssertEqual(goal.manualCurrentAmount, 500, accuracy: 0.001)
    }
}
