import XCTest
import SwiftData
import SwiftUI
@testable import EggSpend

final class CategoryTests: XCTestCase {
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

    func testCategoryInitialization() throws {
        let cat = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22")
        XCTAssertEqual(cat.name, "Food")
        XCTAssertEqual(cat.icon, "fork.knife")
        XCTAssertEqual(cat.colorHex, "E67E22")
        XCTAssertNil(cat.appliesTo)
        XCTAssertTrue(cat.transactions?.isEmpty ?? true)
    }

    func testCategoryTypeFilter() throws {
        let expenseCat = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        let incomeCat = TransactionCategory(name: "Salary", icon: "briefcase.fill", colorHex: "27AE60", typeFilter: .income)
        let universalCat = TransactionCategory(name: "Other", icon: "circle", colorHex: "95A5A6")

        XCTAssertEqual(expenseCat.appliesTo, .expense)
        XCTAssertEqual(incomeCat.appliesTo, .income)
        XCTAssertNil(universalCat.appliesTo)
    }

    func testCategoryColorParsing() throws {
        let cat = TransactionCategory(name: "Test", icon: "star", colorHex: "FF5733")
        let color = Color(hex: "FF5733")
        XCTAssertNotNil(color)
    }

    func testColorHexParsingValid() {
        XCTAssertNotNil(Color(hex: "E67E22"))
        XCTAssertNotNil(Color(hex: "27AE60"))
        XCTAssertNotNil(Color(hex: "000000"))
        XCTAssertNotNil(Color(hex: "FFFFFF"))
    }

    func testColorHexParsingInvalid() {
        XCTAssertNil(Color(hex: "XYZ"))
        XCTAssertNil(Color(hex: "12345"))
        XCTAssertNil(Color(hex: ""))
    }

    func testColorHexWithHash() {
        XCTAssertNotNil(Color(hex: "#E67E22"))
        XCTAssertNotNil(Color(hex: "#FFFFFF"))
    }

    func testCategoryPersistence() throws {
        let cat = TransactionCategory(name: "Transport", icon: "car.fill", colorHex: "3498DB", typeFilter: .expense)
        context.insert(cat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Transport")
        XCTAssertEqual(fetched.first?.appliesTo, .expense)
    }

    func testDefaultCategorySeed() throws {
        PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertFalse(categories.isEmpty, "Should seed default categories")
    }

    func testDefaultCategorySeedIsIdempotent() throws {
        PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: container)
        PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: container)
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let names = categories.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Should not create duplicate categories")
    }

    func testCategoryTransactionRelationship() throws {
        let cat = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        context.insert(cat)
        let tx = Transaction(title: "Lunch", amount: 12, type: .expense, category: cat)
        context.insert(tx)
        try context.save()

        let fetchedCats = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertFalse(fetchedCats.first?.transactions?.isEmpty ?? true)
    }

    func testCategoryDeletion() throws {
        let cat = TransactionCategory(name: "Temp", icon: "star", colorHex: "AABBCC")
        context.insert(cat)
        try context.save()

        var categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(categories.count, 1)

        context.delete(categories[0])
        try context.save()

        categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        XCTAssertEqual(categories.count, 0)
    }
}
