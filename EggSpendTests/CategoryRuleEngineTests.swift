import XCTest
import SwiftData
@testable import EggSpend

final class CategoryRuleEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self,
                             BalanceSnapshot.self, CategoryRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testRecordThenMatchReturnsCategory() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: rules, categories: categories)

        XCTAssertEqual(resolved?.id, coffee.id)
    }

    func testMostRecentRuleWins() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        let dining = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "E67E22")
        context.insert(coffee)
        context.insert(dining)
        try context.save()

        // Two raw rows for the same pattern, inserted out of chronological order:
        // the row inserted second has the EARLIER createdAt.
        let pattern = CSVParser.normalizedTitle("Blue Bottle Coffee")
        let insertedFirstButLatestCreatedAt = CategoryRule(normalizedPattern: pattern, categoryID: coffee.id, createdAt: date(2026, 1, 5))
        let insertedSecondButEarliestCreatedAt = CategoryRule(normalizedPattern: pattern, categoryID: dining.id, createdAt: date(2026, 1, 1))
        context.insert(insertedFirstButLatestCreatedAt)
        context.insert(insertedSecondButEarliestCreatedAt)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: rules, categories: categories)

        XCTAssertEqual(resolved?.id, coffee.id, "the row with the latest createdAt should win, regardless of insertion order")
    }

    func testRecordRuleUpsertsSingleRow() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        let dining = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "E67E22")
        context.insert(coffee)
        context.insert(dining)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))
        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: dining, context: context, now: date(2026, 1, 2))

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 1, "recording a rule for the same pattern twice should update the existing row, not insert a second one")
        XCTAssertEqual(rules.first?.categoryID, dining.id)
    }

    func testDanglingCategoryIDReturnsNil() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))

        context.delete(coffee)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: rules, categories: categories)

        XCTAssertNil(resolved, "a rule pointing at a deleted category should resolve to no match, not a crash or stale category")
    }

    func testNormalizationMatchesCaseAndWhitespaceVariants() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())

        XCTAssertEqual(CategoryRuleEngine.categoryFor(title: "  blue    bottle coffee  ", rules: rules, categories: categories)?.id, coffee.id)
        XCTAssertEqual(CategoryRuleEngine.categoryFor(title: "BLUE BOTTLE COFFEE", rules: rules, categories: categories)?.id, coffee.id)
    }

    func testDeletingRuleStopsMatching() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        let rule = try XCTUnwrap(CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1)))

        context.delete(rule)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: rules, categories: categories)

        XCTAssertNil(resolved)
    }

    func testDuplicateRowsReadToleranceLatestWins() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        let dining = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "E67E22")
        context.insert(coffee)
        context.insert(dining)
        try context.save()

        // Simulate a cross-device sync race: two raw rows for the same pattern, never swept.
        let pattern = CSVParser.normalizedTitle("Blue Bottle Coffee")
        context.insert(CategoryRule(normalizedPattern: pattern, categoryID: coffee.id, createdAt: date(2026, 1, 1)))
        context.insert(CategoryRule(normalizedPattern: pattern, categoryID: dining.id, createdAt: date(2026, 1, 10)))
        try context.save()

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(rules.count, 2, "duplicate rows are tolerated, not swept, on read")

        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: rules, categories: categories)
        XCTAssertEqual(resolved?.id, dining.id)
    }

    func testExactMatcherDoesNotMatchDigitVariants() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee 0423", rules: rules, categories: categories)

        XCTAssertNil(resolved, "exact-normalized-title v1 must not match digit-suffixed statement-line variants")
    }

    func testNoRulesOrUnrelatedTitleReturnsNil() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        // No rules recorded at all.
        var categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        var resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: [], categories: categories)
        XCTAssertNil(resolved)

        // A rule exists, but for an unrelated title.
        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        resolved = CategoryRuleEngine.categoryFor(title: "Trader Joe's", rules: rules, categories: categories)
        XCTAssertNil(resolved)
    }

    func testRecordRuleWithWhitespaceOnlyTitleReturnsNilAndInsertsNoRow() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        let result = CategoryRuleEngine.recordRule(title: "   ", category: coffee, context: context, now: date(2026, 1, 1))
        XCTAssertNil(result)

        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertTrue(rules.isEmpty, "an empty-normalized title should not create a rule row")
    }

    func testCategoryForWithEmptyOrWhitespaceTitleReturnsNilEvenWithRules() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())

        XCTAssertNil(CategoryRuleEngine.categoryFor(title: "", rules: rules, categories: categories))
        XCTAssertNil(CategoryRuleEngine.categoryFor(title: "   ", rules: rules, categories: categories))
    }

    func testDeleteAllRulesRemovesAllDuplicateRowsForPatternAndLeavesOthersUntouched() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        let dining = TransactionCategory(name: "Dining", icon: "fork.knife", colorHex: "E67E22")
        context.insert(coffee)
        context.insert(dining)
        try context.save()

        // Two duplicate rows for the target pattern (mirrors testDuplicateRowsReadToleranceLatestWins).
        let targetPattern = CSVParser.normalizedTitle("Blue Bottle Coffee")
        context.insert(CategoryRule(normalizedPattern: targetPattern, categoryID: coffee.id, createdAt: date(2026, 1, 1)))
        context.insert(CategoryRule(normalizedPattern: targetPattern, categoryID: dining.id, createdAt: date(2026, 1, 10)))

        // A rule for an unrelated pattern should survive the delete.
        let otherPattern = CSVParser.normalizedTitle("Trader Joe's")
        context.insert(CategoryRule(normalizedPattern: otherPattern, categoryID: dining.id, createdAt: date(2026, 1, 1)))
        try context.save()

        CategoryRuleEngine.deleteAllRules(matching: targetPattern, in: context)

        let remaining = try context.fetch(FetchDescriptor<CategoryRule>())
        XCTAssertEqual(remaining.count, 1, "both duplicate rows for the target pattern should be deleted")
        XCTAssertEqual(remaining.first?.normalizedPattern, otherPattern, "rules for other patterns must survive")

        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let resolved = CategoryRuleEngine.categoryFor(title: "Blue Bottle Coffee", rules: remaining, categories: categories)
        XCTAssertNil(resolved, "no rule should match the deleted pattern anymore")
    }

    // MARK: - applyCategoryRules (CSVImportView.swift)

    func testApplyCategoryRulesAssignsUncategorizedRowAndFlagsAutoAssigned() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())

        let result = ParsedTransactionResult(
            rowIndex: 0, title: "Blue Bottle Coffee", date: date(2026, 1, 2), amount: 5.0,
            type: .expense, categoryName: nil, notes: ""
        )

        let applied = applyCategoryRules(in: [result], rules: rules, categories: categories)

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].categoryName, "Coffee")
        XCTAssertTrue(applied[0].isAutoAssignedCategory)
    }

    func testApplyCategoryRulesNeverOverwritesCSVSpecifiedCategory() throws {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "A0522D")
        context.insert(coffee)
        try context.save()

        CategoryRuleEngine.recordRule(title: "Blue Bottle Coffee", category: coffee, context: context, now: date(2026, 1, 1))
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())

        let result = ParsedTransactionResult(
            rowIndex: 0, title: "Blue Bottle Coffee", date: date(2026, 1, 2), amount: 5.0,
            type: .expense, categoryName: "Dining", notes: ""
        )

        let applied = applyCategoryRules(in: [result], rules: rules, categories: categories)

        XCTAssertEqual(applied[0].categoryName, "Dining", "an explicit CSV category must never be overwritten by a rule guess")
        XCTAssertFalse(applied[0].isAutoAssignedCategory)
    }

    func testApplyCategoryRulesLeavesNoMatchRowUntouched() throws {
        let categories: [TransactionCategory] = []
        let rules: [CategoryRule] = []

        let result = ParsedTransactionResult(
            rowIndex: 0, title: "Unrelated Merchant", date: date(2026, 1, 2), amount: 5.0,
            type: .expense, categoryName: nil, notes: ""
        )

        let applied = applyCategoryRules(in: [result], rules: rules, categories: categories)

        XCTAssertNil(applied[0].categoryName)
        XCTAssertFalse(applied[0].isAutoAssignedCategory)
    }
}
