import XCTest
import SwiftData
@testable import EggSpend

final class TransactionEntryServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            Transaction.self, TransactionCategory.self, Account.self,
            Budget.self, RecurringTransaction.self, SavingsGoal.self,
            Transfer.self, BalanceSnapshot.self, CategoryRule.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testCreateTransactionAppliesBalanceRecordsRuleAndInvokesAlerts() throws {
        let account = Account(name: "Checking", type: .checking, balance: 100)
        let category = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "#000000", typeFilter: .expense)
        let budget = Budget(name: "Coffee Budget", limitAmount: 50, category: category)
        context.insert(account)
        context.insert(category)
        context.insert(budget)

        var alertCallCount = 0
        let transaction = TransactionEntryService.createTransaction(
            title: "  Blue Bottle  ",
            amount: 12.50,
            date: Date(timeIntervalSince1970: 1_000),
            type: .expense,
            category: category,
            account: account,
            budget: budget,
            notes: "latte",
            context: context,
            budgetAlertChecker: { alertContext in
                XCTAssertTrue(alertContext === self.context)
                alertCallCount += 1
            }
        )

        XCTAssertEqual(transaction.title, "Blue Bottle")
        XCTAssertEqual(transaction.amount, 12.50, accuracy: 0.001)
        XCTAssertEqual(transaction.category?.id, category.id)
        XCTAssertEqual(transaction.account?.id, account.id)
        XCTAssertEqual(transaction.budget?.id, budget.id)
        XCTAssertEqual(account.balance, 87.50, accuracy: 0.001)
        XCTAssertEqual(alertCallCount, 1)

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.normalizedPattern, "blue bottle")
        XCTAssertEqual(rules.first?.categoryID, category.id)
    }

    func testUpdateTransactionReversesOldAccountAppliesNewAccountRecordsRuleAndInvokesAlerts() throws {
        let oldAccount = Account(name: "Checking", type: .checking, balance: 100)
        let newAccount = Account(name: "Savings", type: .savings, balance: 50)
        let category = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "#000000", typeFilter: .expense)
        let budget = Budget(name: "Dining Budget", limitAmount: 200, category: category)
        let transaction = Transaction(title: "Lunch", amount: 20, type: .expense, account: oldAccount)
        context.insert(oldAccount)
        context.insert(newAccount)
        context.insert(category)
        context.insert(budget)
        context.insert(transaction)
        AccountBalanceService.apply(transaction, to: oldAccount)

        var alertCallCount = 0
        TransactionEntryService.updateTransaction(
            transaction,
            title: "  Dinner  ",
            amount: 30,
            date: Date(timeIntervalSince1970: 2_000),
            type: .expense,
            category: category,
            account: newAccount,
            budget: budget,
            notes: "changed",
            context: context,
            budgetAlertChecker: { _ in alertCallCount += 1 }
        )

        XCTAssertEqual(oldAccount.balance, 100, accuracy: 0.001)
        XCTAssertEqual(newAccount.balance, 20, accuracy: 0.001)
        XCTAssertEqual(transaction.title, "Dinner")
        XCTAssertEqual(transaction.notes, "changed")
        XCTAssertEqual(transaction.account?.id, newAccount.id)
        XCTAssertEqual(transaction.budget?.id, budget.id)
        XCTAssertEqual(alertCallCount, 1)

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.normalizedPattern, "dinner")
    }

    func testUpdateTransactionClearsBudgetWhenChangingToIncome() throws {
        let budget = Budget(name: "Dining Budget", limitAmount: 200)
        let transaction = Transaction(title: "Refund", amount: 20, type: .expense, budget: budget)
        context.insert(budget)
        context.insert(transaction)

        TransactionEntryService.updateTransaction(
            transaction,
            title: "Refund",
            amount: 20,
            date: Date(timeIntervalSince1970: 5_000),
            type: .income,
            category: nil,
            account: nil,
            budget: budget,
            notes: "",
            context: context,
            budgetAlertChecker: { _ in }
        )

        XCTAssertNil(transaction.budget)
    }

    func testCreateTransferAppliesBalancesAndInsertsTransfer() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 100)
        let savings = Account(name: "Savings", type: .savings, balance: 10)
        context.insert(checking)
        context.insert(savings)

        let transfer = TransactionEntryService.createTransfer(
            amount: 25,
            date: Date(timeIntervalSince1970: 3_000),
            fromAccount: checking,
            toAccount: savings,
            notes: "move",
            context: context
        )

        XCTAssertEqual(checking.balance, 75, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 35, accuracy: 0.001)
        XCTAssertEqual(transfer.notes, "move")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transfer>()).count, 1)
    }

    func testUpdateTransferReversesOldAccountsAndAppliesNewValues() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 100)
        let savings = Account(name: "Savings", type: .savings, balance: 10)
        let cash = Account(name: "Cash", type: .other, balance: 40)
        let investment = Account(name: "Investment", type: .investment, balance: 200)
        let transfer = Transfer(amount: 25, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(cash)
        context.insert(investment)
        context.insert(transfer)
        TransferBalanceService.apply(transfer)

        TransactionEntryService.updateTransfer(
            transfer,
            amount: 15,
            date: Date(timeIntervalSince1970: 4_000),
            fromAccount: cash,
            toAccount: investment,
            notes: "updated"
        )

        XCTAssertEqual(checking.balance, 100, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 10, accuracy: 0.001)
        XCTAssertEqual(cash.balance, 25, accuracy: 0.001)
        XCTAssertEqual(investment.balance, 215, accuracy: 0.001)
        XCTAssertEqual(transfer.notes, "updated")
        XCTAssertEqual(transfer.fromAccount?.id, cash.id)
        XCTAssertEqual(transfer.toAccount?.id, investment.id)
    }

    func testCreateTransferWithSavingsGoalTagsTransferAndCreditsManualProgress() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 100)
        context.insert(checking)
        context.insert(goal)

        let transfer = TransactionEntryService.createTransfer(
            amount: 300,
            date: Date(timeIntervalSince1970: 3_000),
            fromAccount: checking,
            toAccount: nil,
            savingsGoal: goal,
            notes: "vacation fund",
            context: context
        )

        XCTAssertEqual(transfer.savingsGoal?.id, goal.id)
        XCTAssertEqual(goal.manualCurrentAmount, 400, accuracy: 0.001)
    }

    func testUpdateTransferChangingSavingsGoalRebalancesBothGoals() throws {
        let goalA = SavingsGoal(name: "Vacation", targetAmount: 2000, currentAmount: 100)
        let goalB = SavingsGoal(name: "Emergency Fund", targetAmount: 5000, currentAmount: 50)
        let transfer = Transfer(amount: 300, fromAccount: nil, toAccount: nil, savingsGoal: goalA)
        context.insert(goalA)
        context.insert(goalB)
        context.insert(transfer)
        TransferBalanceService.apply(transfer)
        SavingsGoalContributionService.apply(transfer)
        XCTAssertEqual(goalA.manualCurrentAmount, 400, accuracy: 0.001)

        TransactionEntryService.updateTransfer(
            transfer,
            amount: 300,
            date: Date(timeIntervalSince1970: 4_000),
            fromAccount: nil,
            toAccount: nil,
            savingsGoal: goalB,
            notes: ""
        )

        XCTAssertEqual(goalA.manualCurrentAmount, 100, accuracy: 0.001, "Reassigned away from goalA — its contribution should be reversed")
        XCTAssertEqual(goalB.manualCurrentAmount, 350, accuracy: 0.001, "Newly tagged goalB should receive the contribution")
        XCTAssertEqual(transfer.savingsGoal?.id, goalB.id)
    }

    // MARK: - Delete + undo restore

    func testDeleteTransactionReversesBalanceAndRestoreReappliesExactly() throws {
        let account = Account(name: "Checking", type: .checking, balance: 100)
        let category = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "#000000", typeFilter: .expense)
        context.insert(account)
        context.insert(category)
        let transaction = TransactionEntryService.createTransaction(
            title: "Lunch", amount: 20, date: Date(timeIntervalSince1970: 1_000),
            type: .expense, category: category, account: account, notes: "tacos",
            context: context, budgetAlertChecker: { _ in }
        )
        let originalID = transaction.id
        let originalCreatedAt = transaction.createdAt
        XCTAssertEqual(account.balance, 80, accuracy: 0.001)

        let snapshot = TransactionEntryService.deleteTransaction(transaction, context: context)
        try context.save()

        XCTAssertEqual(account.balance, 100, accuracy: 0.001, "Delete must reverse the balance effect")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)

        let restored = TransactionEntryService.restoreTransaction(snapshot, context: context)
        try context.save()

        XCTAssertEqual(account.balance, 80, accuracy: 0.001, "Restore must re-apply the balance effect")
        XCTAssertEqual(restored.id, originalID, "Restore must preserve the original id")
        XCTAssertEqual(restored.createdAt, originalCreatedAt)
        XCTAssertEqual(restored.title, "Lunch")
        XCTAssertEqual(restored.amount, 20, accuracy: 0.001)
        XCTAssertEqual(restored.type, .expense)
        XCTAssertEqual(restored.notes, "tacos")
        XCTAssertEqual(restored.category?.id, category.id)
        XCTAssertEqual(restored.account?.id, account.id)
    }

    func testRestoreTransactionDoesNotRecordCategoryRule() throws {
        let category = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "#000000", typeFilter: .expense)
        context.insert(category)
        let transaction = Transaction(title: "Lunch", amount: 20, type: .expense, category: category)
        context.insert(transaction)

        let snapshot = TransactionEntryService.deleteTransaction(transaction, context: context)
        TransactionEntryService.restoreTransaction(snapshot, context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<CategoryRule>()).isEmpty,
                      "Undo is not a fresh categorization signal")
    }

    func testRestoreTransactionWithDeletedCategoryResolvesToNil() throws {
        let category = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "#000000", typeFilter: .expense)
        context.insert(category)
        let transaction = Transaction(title: "Lunch", amount: 20, type: .expense, category: category)
        context.insert(transaction)

        let snapshot = TransactionEntryService.deleteTransaction(transaction, context: context)
        context.delete(category)
        try context.save()

        let restored = TransactionEntryService.restoreTransaction(snapshot, context: context)
        XCTAssertNil(restored.category, "A dangling category ID must resolve to nil, not crash")
        XCTAssertEqual(restored.title, "Lunch")
    }

    func testDeleteAndRestoreTransferRoundTripsBalancesAndGoal() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1_000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let goal = SavingsGoal(name: "Vacation", targetAmount: 2_000, currentAmount: 100)
        context.insert(checking)
        context.insert(savings)
        context.insert(goal)
        let transfer = TransactionEntryService.createTransfer(
            amount: 300, date: Date(timeIntervalSince1970: 2_000),
            fromAccount: checking, toAccount: savings, savingsGoal: goal,
            notes: "monthly", context: context
        )
        let originalID = transfer.id
        XCTAssertEqual(checking.balance, 700, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 800, accuracy: 0.001)
        XCTAssertEqual(goal.manualCurrentAmount, 400, accuracy: 0.001)

        let snapshot = TransactionEntryService.deleteTransfer(transfer, context: context)
        try context.save()

        XCTAssertEqual(checking.balance, 1_000, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 500, accuracy: 0.001)
        XCTAssertEqual(goal.manualCurrentAmount, 100, accuracy: 0.001, "Delete must reverse the goal contribution")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Transfer>()).isEmpty)

        let restored = TransactionEntryService.restoreTransfer(snapshot, context: context)
        try context.save()

        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(checking.balance, 700, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 800, accuracy: 0.001)
        XCTAssertEqual(goal.manualCurrentAmount, 400, accuracy: 0.001, "Restore must re-apply the goal contribution")
        XCTAssertEqual(restored.fromAccount?.id, checking.id)
        XCTAssertEqual(restored.toAccount?.id, savings.id)
        XCTAssertEqual(restored.savingsGoal?.id, goal.id)
        XCTAssertEqual(restored.notes, "monthly")
    }
}
