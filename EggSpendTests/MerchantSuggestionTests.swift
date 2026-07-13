import XCTest
import SwiftData
@testable import EggSpend

final class MerchantSuggestionTests: XCTestCase {
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

    func testBuildReturnsEmptyForEmptyHistory() {
        XCTAssertTrue(MerchantSuggestion.build(from: [], referenceDate: referenceDate).isEmpty)
    }

    func testBuildDedupesCaseInsensitiveTitlesAndUsesLatestRepresentative() {
        let coffee = TransactionCategory(name: "Coffee", icon: "cup.and.saucer", colorHex: "#000000", typeFilter: .expense)
        let checking = Account(name: "Checking", type: .checking, balance: 0)
        let card = Account(name: "Card", type: .credit, balance: 0)
        context.insert(coffee)
        context.insert(checking)
        context.insert(card)

        let older = transaction(title: "blue bottle", daysAgo: 10, category: nil, account: checking)
        let latest = transaction(title: " Blue Bottle ", daysAgo: 2, category: coffee, account: card)

        let suggestions = MerchantSuggestion.build(from: [older, latest], referenceDate: referenceDate)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.id, "blue bottle")
        XCTAssertEqual(suggestions.first?.title, "Blue Bottle")
        XCTAssertEqual(suggestions.first?.frequency, 2)
        XCTAssertEqual(suggestions.first?.category?.id, coffee.id)
        XCTAssertEqual(suggestions.first?.account?.id, card.id)
    }

    func testBuildExcludesAdjustmentsAndTransactionsOutsideNinetyDayWindow() {
        let valid = transaction(title: "Grocery", daysAgo: 3)
        let adjustment = transaction(title: "Balance adjustment", daysAgo: 4, isAdjustment: true)
        let old = transaction(title: "Old Store", daysAgo: 91)

        let suggestions = MerchantSuggestion.build(from: [valid, adjustment, old], referenceDate: referenceDate)

        XCTAssertEqual(suggestions.map(\.title), ["Grocery"])
    }

    func testBuildRanksFrequencyBeforeRecency() {
        let frequentOlder = [
            transaction(title: "Cafe", daysAgo: 20),
            transaction(title: "Cafe", daysAgo: 19)
        ]
        let recentSingle = transaction(title: "Bookstore", daysAgo: 1)

        let suggestions = MerchantSuggestion.build(from: frequentOlder + [recentSingle], referenceDate: referenceDate)

        XCTAssertEqual(suggestions.map(\.title), ["Cafe", "Bookstore"])
    }

    func testBuildUsesRecencyAsTieBreaker() {
        let olderPair = [
            transaction(title: "Market", daysAgo: 9),
            transaction(title: "Market", daysAgo: 7)
        ]
        let newerPair = [
            transaction(title: "Bakery", daysAgo: 8),
            transaction(title: "Bakery", daysAgo: 1)
        ]

        let suggestions = MerchantSuggestion.build(from: olderPair + newerPair, referenceDate: referenceDate)

        XCTAssertEqual(suggestions.map(\.title), ["Bakery", "Market"])
    }

    func testBuildCapsAtSixSuggestions() {
        let transactions = (0..<8).map { index in
            transaction(title: "Merchant \(index)", daysAgo: index)
        }

        let suggestions = MerchantSuggestion.build(from: transactions, referenceDate: referenceDate)

        XCTAssertEqual(suggestions.count, 6)
        XCTAssertEqual(suggestions.map(\.title), ["Merchant 0", "Merchant 1", "Merchant 2", "Merchant 3", "Merchant 4", "Merchant 5"])
    }

    func testMatchingReturnsPartialTitleMatchesWithLatestCategoryAndAccount() {
        let groceries = TransactionCategory(name: "Groceries", icon: "cart", colorHex: "#000000", typeFilter: .expense)
        let checking = Account(name: "Checking", type: .checking, balance: 0)
        let card = Account(name: "Card", type: .credit, balance: 0)
        context.insert(groceries)
        context.insert(checking)
        context.insert(card)

        _ = transaction(title: "Whole Foods Market", daysAgo: 12, category: nil, account: checking)
        _ = transaction(title: "Whole Foods Market", daysAgo: 1, category: groceries, account: card)
        _ = transaction(title: "Coffee Stand", daysAgo: 2)

        let suggestions = MerchantSuggestion.matching("food", in: fetchTransactions(), referenceDate: referenceDate)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "Whole Foods Market")
        XCTAssertEqual(suggestions.first?.category?.id, groceries.id)
        XCTAssertEqual(suggestions.first?.account?.id, card.id)
    }

    func testMatchingReturnsEmptyForBlankQuery() {
        _ = transaction(title: "Whole Foods Market", daysAgo: 1)

        XCTAssertTrue(MerchantSuggestion.matching("   ", in: fetchTransactions(), referenceDate: referenceDate).isEmpty)
    }

    func testMatchingHonorsLimit() {
        let transactions = (0..<8).map { index in
            transaction(title: "Market \(index)", daysAgo: index)
        }

        let suggestions = MerchantSuggestion.matching("market", in: transactions, referenceDate: referenceDate, limit: 3)

        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.map(\.title), ["Market 0", "Market 1", "Market 2"])
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func transaction(
        title: String,
        daysAgo: Int,
        type: TransactionType = .expense,
        category: TransactionCategory? = nil,
        account: Account? = nil,
        isAdjustment: Bool = false
    ) -> Transaction {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
        let transaction = Transaction(
            title: title,
            amount: 10,
            date: date,
            type: type,
            category: category,
            account: account,
            isAdjustment: isAdjustment
        )
        context.insert(transaction)
        return transaction
    }

    private func fetchTransactions() -> [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    }
}
