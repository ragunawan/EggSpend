import XCTest
import SwiftData
@testable import EggSpend

final class SubscriptionDetectorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    // Fixed UTC/Gregorian calendar so day-gap math never depends on the
    // machine's local time zone or DST transitions.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

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

    // MARK: - Fixture helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func adding(_ days: Int, to base: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: base)!
    }

    private func expense(_ title: String, _ amount: Double, _ date: Date) -> Transaction {
        Transaction(title: title, amount: amount, date: date, type: .expense)
    }

    // MARK: - Cadence & cost

    func testDetectsMonthlySubscriptionWithCorrectCadenceAndCost() throws {
        let d1 = date(2026, 1, 1)
        let d2 = adding(31, to: d1)   // within 27...34
        let d3 = adding(30, to: d2)   // within 27...34
        let txs = [
            expense("Netflix", 17.99, d1),
            expense("Netflix", 17.99, d2),
            expense("Netflix", 17.99, d3)
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertEqual(results.count, 1)
        let netflix = try XCTUnwrap(results.first)
        XCTAssertEqual(netflix.cadence, .monthly)
        XCTAssertEqual(netflix.occurrenceCount, 3)
        XCTAssertEqual(netflix.monthlyCost, 17.99, accuracy: 0.001)
        XCTAssertEqual(netflix.annualizedCost, 17.99 * 12, accuracy: 0.001)
        XCTAssertEqual(netflix.lastDate, d3)
    }

    // Realistic subscription price bump (~16%, comparable to Netflix's
    // real-world 2022/2023 increases). The stability gate is judged on the
    // historical (pre-bump) amounts only, so this must still be detected —
    // a >10% jump on the latest charge alone must not make the whole
    // cluster vanish.
    func testFlagsPriceChangeWhenLatestDiffersFromMode() throws {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("Netflix", 15.49, d1),
            expense("Netflix", 15.49, d2),
            expense("Netflix", 17.99, d3)   // ~16% bump on the latest charge only
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        let netflix = try XCTUnwrap(results.first)
        XCTAssertEqual(netflix.modeAmount, 15.49, accuracy: 0.001)
        XCTAssertEqual(netflix.latestAmount, 17.99, accuracy: 0.001)
        XCTAssertEqual(netflix.priceChanged, true)
        // Cost fields reflect the latest (currently-charged) amount, not the
        // stale historical mode.
        XCTAssertEqual(netflix.monthlyCost, 17.99, accuracy: 0.001)
        XCTAssertEqual(netflix.annualizedCost, 17.99 * 12, accuracy: 0.001)
    }

    // A same-merchant-key charge that's wildly different from history (well
    // beyond a plausible price increase) is unrelated activity, not a price
    // change — the whole cluster is rejected rather than surfacing a bogus
    // "subscription" at the unrelated amount.
    func testRejectsLatestAmountBeyondSanityBound() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let d4 = adding(30, to: d3)
        let txs = [
            expense("Netflix", 15.49, d1),
            expense("Netflix", 15.49, d2),
            expense("Netflix", 15.49, d3),
            expense("Netflix", 200.00, d4)   // unrelated one-off charge, not a price bump
        ]
        let now = adding(5, to: d4)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertTrue(results.isEmpty)
    }

    func testNoPriceChangeFlagWhenAmountsStable() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("Gym", 9.99, d1),
            expense("Gym", 9.99, d2),
            expense("Gym", 9.99, d3)
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertEqual(results.first?.priceChanged, false)
    }

    func testDetectsWeeklyCadence() {
        let d1 = date(2026, 1, 5)
        let d2 = adding(7, to: d1)
        let d3 = adding(7, to: d2)
        let d4 = adding(7, to: d3)
        let txs = [
            expense("Coffee Club", 5.00, d1),
            expense("Coffee Club", 5.00, d2),
            expense("Coffee Club", 5.00, d3),
            expense("Coffee Club", 5.00, d4)
        ]
        let now = adding(2, to: d4)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        let sub = try? XCTUnwrap(results.first)
        XCTAssertEqual(sub?.cadence, .weekly)
        XCTAssertEqual(sub?.monthlyCost ?? 0, 5.00 * 52 / 12, accuracy: 0.001)
    }

    func testDetectsYearlyCadence() {
        let d1 = date(2020, 1, 1)
        let d2 = adding(365, to: d1)
        let d3 = adding(365, to: d2)
        let txs = [
            expense("Domain Renewal", 14.99, d1),
            expense("Domain Renewal", 14.99, d2),
            expense("Domain Renewal", 14.99, d3)
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        let sub = try? XCTUnwrap(results.first)
        XCTAssertEqual(sub?.cadence, .yearly)
        XCTAssertEqual(sub?.monthlyCost ?? 0, 14.99 / 12, accuracy: 0.001)
    }

    func testDetectsBiweeklyCadenceDistinctFromWeekly() {
        let d1 = date(2026, 1, 5)
        let d2 = adding(14, to: d1)
        let d3 = adding(14, to: d2)
        let d4 = adding(14, to: d3)
        let txs = [
            expense("Meal Kit", 40.00, d1),
            expense("Meal Kit", 40.00, d2),
            expense("Meal Kit", 40.00, d3),
            expense("Meal Kit", 40.00, d4)
        ]
        let now = adding(2, to: d4)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        let sub = try? XCTUnwrap(results.first)
        XCTAssertEqual(sub?.cadence, .biweekly)
        XCTAssertNotEqual(sub?.cadence, .weekly)
        XCTAssertEqual(sub?.monthlyCost ?? 0, 40.00 * 26 / 12, accuracy: 0.001)
    }

    // MARK: - Rejections

    // The two HISTORICAL amounts themselves are erratic (not just the
    // latest one) — this must still be rejected regardless of how close the
    // latest charge happens to land to either historical value, since the
    // historical stability gate (not the wide latest-only sanity bound) is
    // what's being exercised here.
    func testRejectsErraticAmounts() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("Erratic", 9.99, d1),
            expense("Erratic", 50.00, d2),   // historical amounts disagree wildly with each other
            expense("Erratic", 15.00, d3)
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertTrue(results.isEmpty)
    }

    func testRejectsFewerThanThreeOccurrences() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let txs = [
            expense("Two Times", 9.99, d1),
            expense("Two Times", 9.99, d2)
        ]
        let now = adding(5, to: d2)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertTrue(results.isEmpty)
    }

    func testGapToleranceBoundaries() {
        func cluster(_ title: String, gap: Int) -> [Transaction] {
            let d1 = date(2026, 1, 1)
            let d2 = adding(gap, to: d1)
            let d3 = adding(gap, to: d2)
            return [
                expense(title, 9.99, d1),
                expense(title, 9.99, d2),
                expense(title, 9.99, d3)
            ]
        }

        // Digits are stripped by the clustering key, so titles must vary by
        // words (not numbers) to stay in distinct clusters.
        let accepted27 = cluster("Boundary Low", gap: 27)
        let accepted34 = cluster("Boundary High", gap: 34)
        let rejected26 = cluster("Boundary Under", gap: 26)
        let rejected35 = cluster("Boundary Over", gap: 35)
        let all = accepted27 + accepted34 + rejected26 + rejected35
        let now = adding(200, to: date(2026, 1, 1))

        let results = SubscriptionDetector.detect(transactions: all, recurring: [], now: now, calendar: calendar)
        let titles = Set(results.map(\.title))
        XCTAssertTrue(titles.contains("Boundary Low"))
        XCTAssertTrue(titles.contains("Boundary High"))
        XCTAssertFalse(titles.contains("Boundary Under"))
        XCTAssertFalse(titles.contains("Boundary Over"))
    }

    // MARK: - RecurringTransaction exclusion

    func testExcludesClustersCoveredByActiveRecurring() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("Spotify", 9.99, d1),
            expense("Spotify", 9.99, d2),
            expense("Spotify", 9.99, d3)
        ]
        let now = adding(5, to: d3)

        let active = RecurringTransaction(title: "Spotify", amount: 9.99, type: .expense, frequency: .monthly, startDate: d1)
        active.isActive = true

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [active], now: now, calendar: calendar)
        XCTAssertTrue(results.isEmpty)
    }

    func testInactiveRecurringDoesNotSuppressDetection() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("Spotify", 9.99, d1),
            expense("Spotify", 9.99, d2),
            expense("Spotify", 9.99, d3)
        ]
        let now = adding(5, to: d3)

        let paused = RecurringTransaction(title: "Spotify", amount: 9.99, type: .expense, frequency: .monthly, startDate: d1)
        paused.isActive = false

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [paused], now: now, calendar: calendar)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Spotify")
    }

    // MARK: - Input filtering

    func testExcludesGeneratedAdjustmentAndIncomeTransactionsFromInput() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let d4 = adding(30, to: d3)
        let d5 = adding(30, to: d4)

        let generated = Transaction(title: "Mixed", amount: 9.99, date: d2, type: .expense, isGenerated: true, recurringSourceID: UUID())
        let adjustment = Transaction(title: "Mixed", amount: 9.99, date: d3, type: .expense, isAdjustment: true)
        let income = Transaction(title: "Mixed", amount: 9.99, date: d4, type: .income)

        // Only these two are eligible (organic, expense, non-adjustment) —
        // below the 3-occurrence minimum once the ineligible rows are
        // filtered out.
        let txs = [
            expense("Mixed", 9.99, d1),
            generated,
            adjustment,
            income,
            expense("Mixed", 9.99, d5)
        ]
        let now = adding(5, to: d5)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Conversion

    func testConversionNextDueDateIsStrictlyFutureAndCalendarExact() {
        let lastDate = date(2026, 1, 1)
        let now = date(2026, 4, 1)   // three months after lastDate

        let detected = SubscriptionDetector.DetectedSubscription(
            title: "Netflix",
            normalizedKey: "netflix",
            cadence: .monthly,
            modeAmount: 17.99,
            latestAmount: 17.99,
            priceChanged: false,
            monthlyCost: 17.99,
            annualizedCost: 17.99 * 12,
            occurrenceCount: 3,
            lastDate: lastDate,
            nextExpectedDate: adding(30, to: lastDate),
            category: nil,
            account: nil
        )

        let fields = SubscriptionDetector.conversionFields(for: detected, now: now, calendar: calendar)

        // Expected: advance one month at a time from lastDate until strictly past now.
        var expected = lastDate
        while expected <= now {
            expected = calendar.date(byAdding: .month, value: 1, to: expected)!
        }

        XCTAssertEqual(fields.nextDueDate, expected)
        XCTAssertEqual(fields.startDate, fields.nextDueDate)
        XCTAssertGreaterThan(fields.nextDueDate, now)
    }

    func testConversionFrequencyMatchesDetectedCadence() {
        let lastDate = date(2026, 1, 5)
        let now = adding(3, to: lastDate)

        let detected = SubscriptionDetector.DetectedSubscription(
            title: "Coffee Club",
            normalizedKey: "coffee club",
            cadence: .weekly,
            modeAmount: 5.00,
            latestAmount: 5.00,
            priceChanged: false,
            monthlyCost: 5.00 * 52 / 12,
            annualizedCost: 5.00 * 52,
            occurrenceCount: 4,
            lastDate: lastDate,
            nextExpectedDate: adding(7, to: lastDate),
            category: nil,
            account: nil
        )

        let fields = SubscriptionDetector.conversionFields(for: detected, now: now, calendar: calendar)
        XCTAssertEqual(fields.frequency, .weekly)
        XCTAssertEqual(fields.type, .expense)
        XCTAssertEqual(fields.title, "Coffee Club")
        XCTAssertEqual(fields.amount, 5.00, accuracy: 0.001)
    }

    // MARK: - Sorting

    func testResultsSortedByMonthlyCostDescending() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let now = adding(5, to: d3)

        let cheap = [
            expense("Cheap", 5.00, d1),
            expense("Cheap", 5.00, d2),
            expense("Cheap", 5.00, d3)
        ]
        let mid = [
            expense("Mid", 20.00, d1),
            expense("Mid", 20.00, d2),
            expense("Mid", 20.00, d3)
        ]
        let expensive = [
            expense("Expensive", 50.00, d1),
            expense("Expensive", 50.00, d2),
            expense("Expensive", 50.00, d3)
        ]

        let results = SubscriptionDetector.detect(transactions: cheap + expensive + mid, recurring: [], now: now, calendar: calendar)
        XCTAssertEqual(results.map(\.title), ["Expensive", "Mid", "Cheap"])
    }

    func testResultsTieBreakByNormalizedKeyAscending() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let now = adding(5, to: d3)

        let zeta = [
            expense("Zeta", 10.00, d1),
            expense("Zeta", 10.00, d2),
            expense("Zeta", 10.00, d3)
        ]
        let alpha = [
            expense("Alpha", 10.00, d1),
            expense("Alpha", 10.00, d2),
            expense("Alpha", 10.00, d3)
        ]

        let results = SubscriptionDetector.detect(transactions: zeta + alpha, recurring: [], now: now, calendar: calendar)
        XCTAssertEqual(results.map(\.title), ["Alpha", "Zeta"])
    }

    // MARK: - Title normalization / clustering

    func testTitleNormalizationClustersReferenceNumberVariants() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let txs = [
            expense("NETFLIX.COM 0423", 17.99, d1),
            expense("Netflix.com 0523", 17.99, d2),
            expense("netflix.com", 17.99, d3)
        ]
        let now = adding(5, to: d3)

        let results = SubscriptionDetector.detect(transactions: txs, recurring: [], now: now, calendar: calendar)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.occurrenceCount, 3)
        XCTAssertEqual(results.first?.normalizedKey, "netflix com")
        // Title is the most recent occurrence's original (unnormalized) title.
        XCTAssertEqual(results.first?.title, "netflix.com")
    }

    func testTitleNormalizationKeepsDistinctMerchantsSeparate() {
        let d1 = date(2026, 1, 1)
        let d2 = adding(30, to: d1)
        let d3 = adding(30, to: d2)
        let now = adding(5, to: d3)

        let bill = [
            expense("apple.com/bill", 2.99, d1),
            expense("apple.com/bill", 2.99, d2),
            expense("apple.com/bill", 2.99, d3)
        ]
        let store = [
            expense("apple store", 2.99, d1),
            expense("apple store", 2.99, d2),
            expense("apple store", 2.99, d3)
        ]

        let results = SubscriptionDetector.detect(transactions: bill + store, recurring: [], now: now, calendar: calendar)
        let keys = Set(results.map(\.normalizedKey))
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(keys.contains("apple com bill"))
        XCTAssertTrue(keys.contains("apple store"))
    }
}
