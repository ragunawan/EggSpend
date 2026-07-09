import XCTest
import SwiftData
@testable import EggSpend

final class CategoryManagementTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - testCategoryCreation

    func testCategoryCreation() throws {
        let category = TransactionCategory(
            name: "Groceries",
            icon: "cart.fill",
            colorHex: "27AE60",
            typeFilter: .expense
        )
        context.insert(category)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Groceries")
        XCTAssertEqual(fetched.first?.icon, "cart.fill")
        XCTAssertEqual(fetched.first?.colorHex, "27AE60")
        XCTAssertEqual(fetched.first?.appliesTo, .expense)
        XCTAssertFalse(fetched.first?.isArchived ?? true, "New categories should not be archived by default")
    }

    // MARK: - testCategoryDuplicateNameSameType

    func testCategoryDuplicateNameSameType() throws {
        // Validation is UI-level only; the model allows duplicates
        let cat1 = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        let cat2 = TransactionCategory(name: "Food", icon: "cart.fill", colorHex: "27AE60", typeFilter: .expense)
        context.insert(cat1)
        context.insert(cat2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetched.count, 2, "Model should allow duplicate names; duplicate check is UI-level only")
        let names = fetched.map(\.name)
        XCTAssertEqual(names.filter { $0 == "Food" }.count, 2)
    }

    // MARK: - testCategoryDeletionNullifiesTransactions

    func testCategoryDeletionNullifiesTransactions() throws {
        // Create category
        let category = TransactionCategory(
            name: "Transport",
            icon: "car.fill",
            colorHex: "3498DB",
            typeFilter: .expense
        )
        context.insert(category)

        // Create a transaction linked to the category
        let transaction = Transaction(
            title: "Uber ride",
            amount: 22.50,
            type: .expense,
            category: category
        )
        context.insert(transaction)
        try context.save()

        // Verify relationship is set
        let fetchedTxBefore = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetchedTxBefore.count, 1)
        XCTAssertNotNil(fetchedTxBefore.first?.category, "Transaction should have a category before deletion")

        // Delete the category
        let fetchedCats = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetchedCats.count, 1)
        context.delete(fetchedCats[0])
        try context.save()

        // Category should be gone
        let remainingCats = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(remainingCats.count, 0, "Category should be deleted")

        // Transaction should still exist, with category nullified (deleteRule: .nullify)
        let fetchedTxAfter = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetchedTxAfter.count, 1, "Transaction should still exist after category deletion")
        XCTAssertNil(fetchedTxAfter.first?.category, "Transaction's category should be nil after category deletion")
        XCTAssertEqual(fetchedTxAfter.first?.title, "Uber ride", "Transaction data should be preserved")
    }

    // MARK: - testCategoryArchive

    func testCategoryArchive() throws {
        let category = TransactionCategory(
            name: "Old Subscription",
            icon: "tv.fill",
            colorHex: "9B59B6",
            typeFilter: .expense
        )
        XCTAssertFalse(category.isArchived, "Category should start unarchived")

        context.insert(category)
        try context.save()

        // Archive the category
        let fetched = try context.fetch(FetchDescriptor<TransactionCategory>())
        guard let fetchedCat = fetched.first else {
            XCTFail("Category was not persisted")
            return
        }
        fetchedCat.isArchived = true
        try context.save()

        // Verify archived state persists
        let reFetched = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertTrue(reFetched.first?.isArchived ?? false, "isArchived should persist as true")

        // Unarchive and verify
        reFetched.first?.isArchived = false
        try context.save()
        let reFetched2 = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertFalse(reFetched2.first?.isArchived ?? true, "isArchived should persist as false after unarchiving")
    }

    // MARK: - testDefaultCategoryCount

    func testDefaultCategoryCount() throws {
        PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertGreaterThanOrEqual(categories.count, 10, "Should seed at least 10 default categories")
    }

    // MARK: - testCategoryTypeFilter

    func testCategoryTypeFilter() throws {
        let expenseCategory = TransactionCategory(
            name: "Food",
            icon: "fork.knife",
            colorHex: "E67E22",
            typeFilter: .expense
        )
        let incomeCategory = TransactionCategory(
            name: "Salary",
            icon: "briefcase.fill",
            colorHex: "27AE60",
            typeFilter: .income
        )
        let universalCategory = TransactionCategory(
            name: "Other",
            icon: "ellipsis.circle.fill",
            colorHex: "95A5A6"
            // no typeFilter — defaults to nil (both)
        )

        context.insert(expenseCategory)
        context.insert(incomeCategory)
        context.insert(universalCategory)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TransactionCategory>(
            sortBy: [SortDescriptor(\.name)]
        ))

        let food   = fetched.first { $0.name == "Food" }
        let salary = fetched.first { $0.name == "Salary" }
        let other  = fetched.first { $0.name == "Other" }

        XCTAssertEqual(food?.appliesTo,   .expense,  "Food should apply to expense only")
        XCTAssertEqual(salary?.appliesTo, .income,   "Salary should apply to income only")
        XCTAssertNil(other?.appliesTo,               "Other should apply to both (nil)")

        // typeFilter raw value check
        XCTAssertEqual(food?.typeFilter,   TransactionType.expense.rawValue)
        XCTAssertEqual(salary?.typeFilter, TransactionType.income.rawValue)
        XCTAssertNil(other?.typeFilter)
    }
}
