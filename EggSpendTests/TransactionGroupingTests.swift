import XCTest
@testable import EggSpend

/// `Transaction` instances here are constructed unattached to any `ModelContainer` —
/// `TransactionGrouping.groupByDay` is a pure function over `[LedgerRow]` and needs no
/// persistence layer (see `MonthlyReviewCalculatorTests` for the general pattern; unlike
/// that suite, this one has no reason to stand up a container at all).
final class TransactionGroupingTests: XCTestCase {
    /// Fixed calendar/time zone for deterministic day-boundary math regardless of the host machine.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func row(_ title: String, _ date: Date) -> LedgerRow {
        .transaction(Transaction(title: title, amount: 10, date: date, type: .expense))
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return utcCalendar.date(from: components)!
    }

    // MARK: - Correctness

    func testEmptyInputProducesNoGroups() {
        let result = TransactionGrouping.groupByDay([], calendar: utcCalendar)
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleDayProducesOneBucket() {
        let rows = [
            row("A", utcDate(2026, 7, 10, 9, 0)),
            row("B", utcDate(2026, 7, 10, 14, 0))
        ]
        let result = TransactionGrouping.groupByDay(rows, calendar: utcCalendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].day, utcDate(2026, 7, 10))
        XCTAssertEqual(result[0].rows.count, 2)
    }

    func testMultipleDaysSortDescending() {
        let rows = [
            row("A", utcDate(2026, 7, 1)),
            row("B", utcDate(2026, 7, 10)),
            row("C", utcDate(2026, 6, 15))
        ]
        let result = TransactionGrouping.groupByDay(rows, calendar: utcCalendar)
        XCTAssertEqual(result.map(\.day), [
            utcDate(2026, 7, 10),
            utcDate(2026, 7, 1),
            utcDate(2026, 6, 15)
        ])
    }

    func testSameCalendarDayDifferentTimesCollapseToOneBucket() {
        let rows = [
            row("Early", utcDate(2026, 7, 10, 0, 5)),
            row("Late", utcDate(2026, 7, 10, 23, 55))
        ]
        let result = TransactionGrouping.groupByDay(rows, calendar: utcCalendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rows.count, 2)
    }

    func testIntraDayOrderIsPreserved() {
        // Rows arrive pre-sorted descending by exact timestamp, as `TransactionsListView.rows` does.
        let rows = [
            row("Noon", utcDate(2026, 7, 10, 12, 0)),
            row("Morning", utcDate(2026, 7, 10, 8, 0)),
            row("Midnight-ish", utcDate(2026, 7, 10, 0, 1))
        ]
        let result = TransactionGrouping.groupByDay(rows, calendar: utcCalendar)
        XCTAssertEqual(result.count, 1)
        let titles = result[0].rows.compactMap { row -> String? in
            if case .transaction(let tx) = row { return tx.title }
            return nil
        }
        XCTAssertEqual(titles, ["Noon", "Morning", "Midnight-ish"])
    }

    // MARK: - Performance

    func testGroupByDayPerformanceOnLargeDataset() {
        // ~5k rows spread across ~200 distinct days, built outside the measure block.
        var rows: [LedgerRow] = []
        rows.reserveCapacity(5000)
        let base = utcDate(2020, 1, 1)
        for i in 0..<5000 {
            let dayOffset = i % 200
            let minuteOffset = i % (24 * 60)
            let date = utcCalendar.date(byAdding: .day, value: dayOffset, to: base)!
            let timestamped = utcCalendar.date(byAdding: .minute, value: minuteOffset, to: date)!
            rows.append(row("Row \(i)", timestamped))
        }

        // No hard wall-clock assertion — the baseline lives in the result bundle, not a
        // brittle time budget. This exists to catch a future reintroduction of an
        // O(n^2)-ish path via a widening measured trend, not a fixed pass/fail threshold.
        measure {
            _ = TransactionGrouping.groupByDay(rows, calendar: utcCalendar)
        }
    }
}
