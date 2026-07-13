import XCTest
import SwiftData
@testable import EggSpend

final class MetricsCalculationTests: XCTestCase {
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

    func testTotalIncome() throws {
        insertTransactions([
            ("Salary", 3000, .income),
            ("Freelance", 500, .income),
            ("Rent", 1200, .expense)
        ])
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let income = transactions.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(income, 3500, accuracy: 0.001)
    }

    func testTotalExpenses() throws {
        insertTransactions([
            ("Salary", 3000, .income),
            ("Rent", 1200, .expense),
            ("Groceries", 300, .expense)
        ])
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let expenses = transactions.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(expenses, 1500, accuracy: 0.001)
    }

    func testNetIncome() throws {
        insertTransactions([
            ("Salary", 5000, .income),
            ("Rent", 1500, .expense),
            ("Food", 600, .expense)
        ])
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let income = transactions.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        let expenses = transactions.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(income - expenses, 2900, accuracy: 0.001)
    }

    func testSavingsRate() throws {
        let income = 4000.0
        let expenses = 3000.0
        let savingsRate = (income - expenses) / income
        XCTAssertEqual(savingsRate, 0.25, accuracy: 0.001)
    }

    func testFilterByDateRange() throws {
        let calendar = Calendar.current
        let now = Date.now
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!

        let tx1 = Transaction(title: "Recent", amount: 100, date: now, type: .expense)
        let tx2 = Transaction(title: "Last Month", amount: 200, date: lastMonth, type: .expense)
        let tx3 = Transaction(title: "Old", amount: 300, date: twoMonthsAgo, type: .expense)
        [tx1, tx2, tx3].forEach { context.insert($0) }
        try context.save()

        let cutoff = calendar.date(byAdding: .day, value: -40, to: now)!
        let all = try context.fetch(FetchDescriptor<Transaction>())
        let recent = all.filter { $0.date >= cutoff }
        XCTAssertEqual(recent.count, 2)
    }

    func testZeroTransactions() throws {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let income = transactions.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(income, 0)
    }

    func testCurrentMonthFilter() throws {
        let now = Date.now
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let tx1 = Transaction(title: "This month", amount: 100, date: now, type: .expense)
        let tx2 = Transaction(title: "Last year", amount: 500, date: lastYear, type: .expense)
        [tx1, tx2].forEach { context.insert($0) }
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let thisMonth = all.filter { Calendar.current.isDateInCurrentMonth($0.date) }
        XCTAssertEqual(thisMonth.count, 1)
        XCTAssertEqual(thisMonth.first?.title, "This month")
    }

    func testExpensesByCategory() throws {
        let foodCat = TransactionCategory(name: "Food", icon: "fork.knife", colorHex: "E67E22", typeFilter: .expense)
        let transportCat = TransactionCategory(name: "Transport", icon: "car.fill", colorHex: "3498DB", typeFilter: .expense)
        context.insert(foodCat)
        context.insert(transportCat)

        let tx1 = Transaction(title: "Lunch", amount: 15, type: .expense, category: foodCat)
        let tx2 = Transaction(title: "Dinner", amount: 30, type: .expense, category: foodCat)
        let tx3 = Transaction(title: "Uber", amount: 12, type: .expense, category: transportCat)
        [tx1, tx2, tx3].forEach { context.insert($0) }
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let expenses = all.filter { $0.type == .expense }
        var byCategory: [String: Double] = [:]
        for tx in expenses {
            let key = tx.category?.name ?? "Uncategorized"
            byCategory[key, default: 0] += tx.amount
        }
        XCTAssertEqual(byCategory["Food"] ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(byCategory["Transport"] ?? 0, 12, accuracy: 0.001)
    }

    func testCompactCurrencyAxisFormatterUsesLargeValueSuffixes() {
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 7_500_000_000_000), "$7.5T")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 2_000_000_000), "$2B")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 125_000_000), "$125M")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 42_500), "$42.5K")
    }

    func testCompactCurrencyAxisFormatterRoundsAwayFloatingPointNoise() {
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 7_500_000_000_003.072), "$7.5T")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: 750.49), "$750")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: -1_250_000_000_000), "-$1.3T")
        XCTAssertEqual(CompactCurrencyAxisFormatter.string(from: .nan), "$0")
    }

    func testChartYAxisDomainUsesExactFiniteMinimumAndMaximum() {
        let range = ChartYAxisDomain.range(for: [500, -125, 250, 900])

        XCTAssertEqual(range.lowerBound, -125, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 900, accuracy: 0.001)
    }

    func testChartYAxisDomainIgnoresNonFiniteValues() {
        let range = ChartYAxisDomain.range(for: [.nan, 12, .infinity, -8])

        XCTAssertEqual(range.lowerBound, -8, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 12, accuracy: 0.001)
    }

    func testChartYAxisDomainExpandsFlatSeriesForChartScale() {
        let range = ChartYAxisDomain.range(for: [250, 250])

        XCTAssertLessThan(range.lowerBound, 250)
        XCTAssertGreaterThan(range.upperBound, 250)
    }

    private func insertTransactions(_ data: [(String, Double, TransactionType)]) {
        for (title, amount, type) in data {
            context.insert(Transaction(title: title, amount: amount, type: type))
        }
        try? context.save()
    }
}
