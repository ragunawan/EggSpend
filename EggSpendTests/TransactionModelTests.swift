import XCTest
import SwiftData
@testable import EggSpend

final class TransactionModelTests: XCTestCase {
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

    func testTransactionInitialization() throws {
        let tx = Transaction(title: "Groceries", amount: 85.50, type: .expense)
        XCTAssertEqual(tx.title, "Groceries")
        XCTAssertEqual(tx.amount, 85.50, accuracy: 0.001)
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.notes, "")
        XCTAssertNil(tx.category)
    }

    func testTransactionAmountIsAlwaysPositive() throws {
        let tx = Transaction(title: "Refund", amount: -50.0, type: .income)
        XCTAssertEqual(tx.amount, 50.0, accuracy: 0.001, "Amount should be stored as positive")
    }

    func testTransactionSignedAmount() throws {
        let income = Transaction(title: "Salary", amount: 3000, type: .income)
        let expense = Transaction(title: "Rent", amount: 1200, type: .expense)
        XCTAssertEqual(income.signedAmount, 3000, accuracy: 0.001)
        XCTAssertEqual(expense.signedAmount, -1200, accuracy: 0.001)
    }

    func testTransactionTypeRawValue() throws {
        XCTAssertEqual(TransactionType.income.rawValue, "Income")
        XCTAssertEqual(TransactionType.expense.rawValue, "Expense")
    }

    func testTransactionWithCategory() throws {
        let category = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        context.insert(category)
        let tx = Transaction(title: "Lunch", amount: 12.50, type: .expense, category: category)
        context.insert(tx)
        try context.save()

        XCTAssertEqual(tx.category?.name, "Food")
    }

    func testTransactionWithNotes() throws {
        let tx = Transaction(
            title: "Coffee",
            amount: 4.75,
            type: .expense,
            notes: "Blue Bottle, almond latte"
        )
        XCTAssertEqual(tx.notes, "Blue Bottle, almond latte")
    }

    func testTransactionPersistence() throws {
        let tx = Transaction(title: "Dinner", amount: 65.00, type: .expense)
        context.insert(tx)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Dinner")
    }

    func testTransactionDateDefaultsToNow() throws {
        let before = Date.now
        let tx = Transaction(title: "Test", amount: 10, type: .expense)
        let after = Date.now
        XCTAssertGreaterThanOrEqual(tx.date, before)
        XCTAssertLessThanOrEqual(tx.date, after)
    }

    func testTransactionTypeSystemImage() throws {
        XCTAssertFalse(TransactionType.income.systemImage.isEmpty)
        XCTAssertFalse(TransactionType.expense.systemImage.isEmpty)
        XCTAssertNotEqual(TransactionType.income.systemImage, TransactionType.expense.systemImage)
    }

    func testMultipleTransactionsDeletion() throws {
        for i in 0..<5 {
            let tx = Transaction(title: "Item \(i)", amount: Double(i) * 10, type: .expense)
            context.insert(tx)
        }
        try context.save()

        var all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(all.count, 5)

        context.delete(all[0])
        try context.save()

        all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(all.count, 4)
    }
}
