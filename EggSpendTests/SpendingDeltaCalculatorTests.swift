import XCTest
import SwiftData
@testable import EggSpend

final class SpendingDeltaCalculatorTests: XCTestCase {
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    private func category(_ name: String) -> TransactionCategory {
        TransactionCategory(name: name, icon: "questionmark.circle", colorHex: "000000")
    }

    private let enUS = Locale(identifier: "en_US")

    // MARK: - Delta ranking (hand-computed fixture)

    func testDeltaRankingExactOrderAndSentences() {
        let dining = category("Dining")
        let entertainment = category("Entertainment")
        let transport = category("Transport")
        let utilities = category("Utilities")

        let txs = [
            // Current month (March 2026)
            Transaction(title: "Dining current",  amount: 420, date: date(2026, 3, 10), type: .expense, category: dining),
            Transaction(title: "Ent current",      amount: 200, date: date(2026, 3, 10), type: .expense, category: entertainment),
            Transaction(title: "Transport current",amount: 100, date: date(2026, 3, 10), type: .expense, category: transport),
            Transaction(title: "Utilities current",amount: 80,  date: date(2026, 3, 10), type: .expense, category: utilities),

            // Feb 2026
            Transaction(title: "Dining Feb",  amount: 300, date: date(2026, 2, 10), type: .expense, category: dining),
            Transaction(title: "Ent Feb",      amount: 60,  date: date(2026, 2, 10), type: .expense, category: entertainment),
            Transaction(title: "Transport Feb",amount: 120, date: date(2026, 2, 10), type: .expense, category: transport),
            Transaction(title: "Utilities Feb",amount: 80,  date: date(2026, 2, 10), type: .expense, category: utilities),

            // Jan 2026
            Transaction(title: "Dining Jan",  amount: 300, date: date(2026, 1, 10), type: .expense, category: dining),
            Transaction(title: "Ent Jan",      amount: 50,  date: date(2026, 1, 10), type: .expense, category: entertainment),
            Transaction(title: "Transport Jan",amount: 140, date: date(2026, 1, 10), type: .expense, category: transport),
            Transaction(title: "Utilities Jan",amount: 80,  date: date(2026, 1, 10), type: .expense, category: utilities),

            // Dec 2025 (also the earliest transaction, giving a full 3-month trailing window)
            Transaction(title: "Dining Dec",  amount: 300, date: date(2025, 12, 10), type: .expense, category: dining),
            Transaction(title: "Ent Dec",      amount: 40,  date: date(2025, 12, 10), type: .expense, category: entertainment),
            Transaction(title: "Transport Dec",amount: 130, date: date(2025, 12, 10), type: .expense, category: transport),
            Transaction(title: "Utilities Dec",amount: 80,  date: date(2025, 12, 10), type: .expense, category: utilities),
        ]

        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)

        // Dining: 420 - avg(300,300,300)=300 -> +120
        // Entertainment: 200 - avg(60,50,40)=50 -> +150 (largest |delta|)
        // Transport: 100 - avg(120,140,130)=130 -> -30
        // Utilities: 80 - avg(80,80,80)=80 -> 0 (dropped)
        XCTAssertEqual(result.map(\.categoryName), ["Entertainment", "Dining", "Transport"])
        XCTAssertEqual(result[0].sentence, "Entertainment is $150.00 above your usual pace.")
        XCTAssertEqual(result[1].sentence, "Dining is $120.00 above your usual pace.")
        XCTAssertEqual(result[2].sentence, "Transport is $30.00 below your usual pace.")
        // figures carry exactly the embedded currency strings (above-pace and below-pace branches).
        XCTAssertEqual(result[0].figures, ["$150.00"])
        XCTAssertEqual(result[2].figures, ["$30.00"])
    }

    func testZeroDeltaCategoryIsDropped() {
        let utilities = category("Utilities")
        let txs = [
            Transaction(title: "Utilities current", amount: 80, date: date(2026, 3, 10), type: .expense, category: utilities),
            Transaction(title: "Utilities Feb",      amount: 80, date: date(2026, 2, 10), type: .expense, category: utilities),
            Transaction(title: "Utilities Jan",      amount: 80, date: date(2026, 1, 10), type: .expense, category: utilities),
            Transaction(title: "Utilities Dec",      amount: 80, date: date(2025, 12, 10), type: .expense, category: utilities),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Zero-fill (new spend / stopped spend)

    func testZeroFillNewSpendAboveUsualPace() {
        let subscriptions = category("Subscriptions")
        let anchor = category("Anchor")
        let txs = [
            // Anchor category exists in all 4 months so hasSufficientHistory is true
            // and the trailing window spans the full 3 months.
            Transaction(title: "Anchor current", amount: 10, date: date(2026, 3, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Feb",      amount: 10, date: date(2026, 2, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Jan",      amount: 10, date: date(2026, 1, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Dec",      amount: 10, date: date(2025, 12, 10), type: .expense, category: anchor),
            // Subscriptions: brand new this month, absent from all trailing months.
            Transaction(title: "New subscription", amount: 60, date: date(2026, 3, 10), type: .expense, category: subscriptions),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Subscriptions" }) else {
            return XCTFail("Expected a Subscriptions delta entry")
        }
        XCTAssertEqual(entry.trailingAverage, 0, accuracy: 0.001)
        XCTAssertEqual(entry.currentAmount, 60, accuracy: 0.001)
        XCTAssertEqual(entry.sentence, "Subscriptions is $60.00 above your usual pace.")
        // figures must be exactly the currency string embedded in the sentence (above-pace branch).
        XCTAssertEqual(entry.figures, ["$60.00"])
    }

    func testZeroFillStoppedSpendDownFromUsual() {
        let gym = category("Gym")
        let anchor = category("Anchor")
        let txs = [
            Transaction(title: "Anchor current", amount: 10, date: date(2026, 3, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Feb",      amount: 10, date: date(2026, 2, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Jan",      amount: 10, date: date(2026, 1, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Dec",      amount: 10, date: date(2025, 12, 10), type: .expense, category: anchor),
            // Gym: spent every trailing month, nothing this month (membership cancelled).
            Transaction(title: "Gym Feb", amount: 45, date: date(2026, 2, 10), type: .expense, category: gym),
            Transaction(title: "Gym Jan", amount: 45, date: date(2026, 1, 10), type: .expense, category: gym),
            Transaction(title: "Gym Dec", amount: 45, date: date(2025, 12, 10), type: .expense, category: gym),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Gym" }) else {
            return XCTFail("Expected a Gym delta entry")
        }
        XCTAssertEqual(entry.currentAmount, 0, accuracy: 0.001)
        XCTAssertEqual(entry.trailingAverage, 45, accuracy: 0.001)
        XCTAssertEqual(entry.sentence, "You haven't spent on Gym this month, down from your usual $45.00.")
        // Stopped-spend branch embeds the trailing average, not the delta.
        XCTAssertEqual(entry.figures, ["$45.00"])
    }

    // MARK: - isAdjustment exclusion

    func testIsAdjustmentTransactionsExcluded() {
        let dining = category("Dining")
        let txs = [
            Transaction(title: "Dining current", amount: 100, date: date(2026, 3, 10), type: .expense, category: dining),
            Transaction(title: "Adjustment current", amount: 500, date: date(2026, 3, 10), type: .expense, category: dining, isAdjustment: true),
            Transaction(title: "Dining Feb", amount: 40, date: date(2026, 2, 10), type: .expense, category: dining),
            Transaction(title: "Dining Jan", amount: 40, date: date(2026, 1, 10), type: .expense, category: dining),
            Transaction(title: "Dining Dec", amount: 40, date: date(2025, 12, 10), type: .expense, category: dining),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Dining" }) else {
            return XCTFail("Expected a Dining delta entry")
        }
        // If the $500 adjustment were included, currentAmount would be 600, not 100.
        XCTAssertEqual(entry.currentAmount, 100, accuracy: 0.001)
    }

    // MARK: - isGenerated inclusion (regression — diverges from ForecastEngine's drift convention)

    func testIsGeneratedTransactionsAreIncluded() {
        let rent = category("Rent")
        let txs = [
            // Materialized recurring transaction — must count as real current-month spend.
            Transaction(title: "Rent (recurring)", amount: 1200, date: date(2026, 3, 1), type: .expense, category: rent, isGenerated: true),
            Transaction(title: "Rent Feb", amount: 1000, date: date(2026, 2, 1), type: .expense, category: rent),
            Transaction(title: "Rent Jan", amount: 1000, date: date(2026, 1, 1), type: .expense, category: rent),
            Transaction(title: "Rent Dec", amount: 1000, date: date(2025, 12, 1), type: .expense, category: rent),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Rent" }) else {
            return XCTFail("Expected a Rent delta entry")
        }
        XCTAssertEqual(entry.currentAmount, 1200, accuracy: 0.001)
        XCTAssertEqual(entry.sentence, "Rent is $200.00 above your usual pace.")
    }

    // MARK: - hasSufficientHistory boundary

    func testHasSufficientHistoryEmptyIsFalse() {
        XCTAssertFalse(SpendingDeltaCalculator.hasSufficientHistory(transactions: [], asOf: date(2026, 3, 15)))
    }

    func testHasSufficientHistoryEarliestWithinCurrentMonthIsFalse() {
        let txs = [Transaction(title: "Recent", amount: 10, date: date(2026, 3, 3), type: .expense)]
        XCTAssertFalse(SpendingDeltaCalculator.hasSufficientHistory(transactions: txs, asOf: date(2026, 3, 15)))
    }

    func testHasSufficientHistoryExactlyOneFullPriorMonthIsTrue() {
        // Earliest transaction lands exactly on the start of the prior month.
        let txs = [Transaction(title: "Feb 1", amount: 10, date: date(2026, 2, 1), type: .expense)]
        XCTAssertTrue(SpendingDeltaCalculator.hasSufficientHistory(transactions: txs, asOf: date(2026, 3, 15)))
    }

    func testCalculateReturnsEmptyWithInsufficientHistory() {
        let dining = category("Dining")
        let txs = [Transaction(title: "Dining", amount: 100, date: date(2026, 3, 3), type: .expense, category: dining)]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Partial trailing window

    func testPartialTrailingWindowAveragesOverOneMonthNotThree() {
        // asOf March 15; earliest transaction ~6 weeks back, entirely within the
        // immediately prior calendar month (Feb) — no Jan/Dec data exists at all,
        // so the trailing average must divide by 1, not 3.
        let dining = category("Dining")
        let txs = [
            Transaction(title: "Dining current", amount: 200, date: date(2026, 3, 10), type: .expense, category: dining),
            Transaction(title: "Dining Feb a", amount: 100, date: date(2026, 2, 1),  type: .expense, category: dining),
            Transaction(title: "Dining Feb b", amount: 50,  date: date(2026, 2, 20), type: .expense, category: dining),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Dining" }) else {
            return XCTFail("Expected a Dining delta entry")
        }
        // Trailing total is 150 over exactly 1 usable month (Feb) -> average 150.
        // If the (empty) Jan/Dec months were wrongly included in the divisor, this
        // would incorrectly come out to 150 / 3 = 50 instead.
        XCTAssertEqual(entry.trailingAverage, 150, accuracy: 0.001)
        XCTAssertEqual(entry.currentAmount, 200, accuracy: 0.001)
        XCTAssertEqual(entry.delta, 50, accuracy: 0.001)
    }

    // MARK: - January year-boundary

    func testJanuaryAnchorResolvesTrailingMonthsToPriorOctNovDec() {
        let dining = category("Dining")
        let txs = [
            Transaction(title: "Dining current", amount: 300, date: date(2026, 1, 10), type: .expense, category: dining),
            Transaction(title: "Dining Dec", amount: 100, date: date(2025, 12, 10), type: .expense, category: dining),
            Transaction(title: "Dining Nov", amount: 100, date: date(2025, 11, 10), type: .expense, category: dining),
            Transaction(title: "Dining Oct", amount: 100, date: date(2025, 10, 10), type: .expense, category: dining),
        ]
        XCTAssertTrue(SpendingDeltaCalculator.hasSufficientHistory(transactions: txs, asOf: date(2026, 1, 15)))
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 1, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "Dining" }) else {
            return XCTFail("Expected a Dining delta entry")
        }
        // avg(100,100,100) = 100; delta = 300 - 100 = 200.
        XCTAssertEqual(entry.trailingAverage, 100, accuracy: 0.001)
        XCTAssertEqual(entry.sentence, "Dining is $200.00 above your usual pace.")
    }

    // MARK: - No NaN/inf when trailing total is 0 with nonzero current

    func testNoNaNOrInfWhenTrailingTotalIsZero() {
        let anchor = category("Anchor")
        let newCat = category("New")
        let txs = [
            Transaction(title: "Anchor current", amount: 10, date: date(2026, 3, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Feb",      amount: 10, date: date(2026, 2, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Jan",      amount: 10, date: date(2026, 1, 10), type: .expense, category: anchor),
            Transaction(title: "Anchor Dec",      amount: 10, date: date(2025, 12, 10), type: .expense, category: anchor),
            Transaction(title: "New spend", amount: 75, date: date(2026, 3, 12), type: .expense, category: newCat),
        ]
        let result = SpendingDeltaCalculator.calculate(transactions: txs, asOf: date(2026, 3, 15), locale: enUS)
        guard let entry = result.first(where: { $0.categoryName == "New" }) else {
            return XCTFail("Expected a New delta entry")
        }
        XCTAssertFalse(entry.trailingAverage.isNaN)
        XCTAssertFalse(entry.trailingAverage.isInfinite)
        XCTAssertFalse(entry.delta.isNaN)
        XCTAssertFalse(entry.delta.isInfinite)
        XCTAssertEqual(entry.trailingAverage, 0, accuracy: 0.001)
    }
}
