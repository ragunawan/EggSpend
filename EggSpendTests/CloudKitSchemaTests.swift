import XCTest
import SwiftData
@testable import EggSpend

final class CloudKitSchemaTests: XCTestCase {
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

    func testBudgetCategoryInverseRelationship() throws {
        let category = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22")
        context.insert(category)
        let budget = Budget(name: "Groceries", limitAmount: 400, category: category)
        context.insert(budget)
        try context.save()

        let fetchedCategories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetchedCategories.first?.budgets?.count, 1)
        XCTAssertEqual(fetchedCategories.first?.budgets?.first?.id, budget.id)
    }

    func testBudgetTransactionInverseRelationship() throws {
        let budget = Budget(name: "Groceries", limitAmount: 400)
        let transaction = Transaction(title: "Market", amount: 50, type: .expense, budget: budget)
        context.insert(budget)
        context.insert(transaction)
        try context.save()

        let fetchedBudgets = try context.fetch(FetchDescriptor<Budget>())
        XCTAssertEqual(fetchedBudgets.first?.transactions?.count, 1)
        XCTAssertEqual(fetchedBudgets.first?.transactions?.first?.id, transaction.id)
    }

    func testRecurringTransactionCategoryInverseRelationship() throws {
        let category = TransactionCategory(name: "Utilities", icon: "bolt.fill", colorHex: "7F8C8D")
        context.insert(category)
        let recurring = RecurringTransaction(title: "Electric Bill", amount: 80, type: .expense, category: category)
        context.insert(recurring)
        try context.save()

        let fetchedCategories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetchedCategories.first?.recurringTransactions?.count, 1)
        XCTAssertEqual(fetchedCategories.first?.recurringTransactions?.first?.id, recurring.id)
    }

    func testAccountTransferInverseRelationship() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        context.insert(checking)
        context.insert(savings)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(transfer)
        try context.save()

        let fetchedAccounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
        let fetchedChecking = fetchedAccounts.first { $0.name == "Checking" }
        let fetchedSavings = fetchedAccounts.first { $0.name == "Savings" }
        XCTAssertEqual(fetchedChecking?.transfersOut?.count, 1)
        XCTAssertEqual(fetchedChecking?.transfersOut?.first?.id, transfer.id)
        XCTAssertEqual(fetchedSavings?.transfersIn?.count, 1)
        XCTAssertEqual(fetchedSavings?.transfersIn?.first?.id, transfer.id)
    }

    func testCategoryDeletionNullifiesBudgetAndRecurringTransaction() throws {
        let category = TransactionCategory(name: "Temp", icon: "star", colorHex: "AABBCC")
        context.insert(category)
        let budget = Budget(name: "Temp Budget", limitAmount: 100, category: category)
        let recurring = RecurringTransaction(title: "Temp Recurring", amount: 10, type: .expense, category: category)
        context.insert(budget)
        context.insert(recurring)
        try context.save()

        context.delete(category)
        try context.save()

        XCTAssertNil(budget.category)
        XCTAssertNil(recurring.category)
    }

    func testBudgetDeletionNullifiesTransactionBudget() throws {
        let budget = Budget(name: "Temp Budget", limitAmount: 100)
        let transaction = Transaction(title: "Temp Spend", amount: 10, type: .expense, budget: budget)
        context.insert(budget)
        context.insert(transaction)
        try context.save()

        context.delete(budget)
        try context.save()

        XCTAssertNil(transaction.budget)
    }

    /// Regression guard: constructing a `ModelContainer` against the CloudKit-enabled
    /// configuration must not throw a schema-validation error (missing inverse
    /// relationships, non-optional attributes/relationships without defaults). This
    /// is the exact failure mode that originally caused CloudKit sync to silently
    /// fall back to local-only storage.
    func testSchemaIsCloudKitCompatible() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self, CategoryRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .automatic)
        XCTAssertNoThrow(try ModelContainer(for: schema, configurations: [config]))
    }
}
