import XCTest
@testable import EggSpend

final class DebtPayoffCalculatorTests: XCTestCase {
    func testAlreadyPaidOff() {
        let result = DebtPayoffCalculator.calculate(
            balance: 0,
            annualPercentageRate: 18,
            minimumPayment: 100
        )
        XCTAssertEqual(result.status, .paidOff)
        XCTAssertEqual(result.months, 0)
    }

    func testZeroInterestPayoff() {
        let result = DebtPayoffCalculator.calculate(
            balance: 1_000,
            annualPercentageRate: 0,
            minimumPayment: 100
        )
        XCTAssertEqual(result.status, .projected)
        XCTAssertEqual(result.months, 10)
        XCTAssertEqual(result.totalInterest, 0, accuracy: 0.001)
    }

    func testInsufficientPayment() {
        let result = DebtPayoffCalculator.calculate(
            balance: 10_000,
            annualPercentageRate: 24,
            minimumPayment: 100
        )
        XCTAssertEqual(result.status, .insufficientPayment)
    }

    func testExtraPaymentShortensPayoff() {
        let base = DebtPayoffCalculator.calculate(
            balance: 2_000,
            annualPercentageRate: 12,
            minimumPayment: 100
        )
        let withExtra = DebtPayoffCalculator.calculate(
            balance: 2_000,
            annualPercentageRate: 12,
            minimumPayment: 100,
            extraPayment: 100
        )
        XCTAssertEqual(base.status, .projected)
        XCTAssertEqual(withExtra.status, .projected)
        XCTAssertLessThan(withExtra.months, base.months)
        XCTAssertLessThan(withExtra.totalInterest, base.totalInterest)
    }

    func testAmortizationScheduleGroupsPaymentsByYear() throws {
        let startDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let schedule = DebtPayoffCalculator.amortizationSchedule(
            balance: 1_200,
            annualPercentageRate: 0,
            monthlyPayment: 100,
            firstPaymentDate: startDate,
            monthlyEscrow: 25,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(schedule.status, .projected)
        XCTAssertEqual(schedule.years.count, 1)
        XCTAssertEqual(schedule.years[0].payments.count, 12)
        XCTAssertEqual(schedule.totalPrincipal, 1_200, accuracy: 0.001)
        XCTAssertEqual(schedule.totalInterest, 0, accuracy: 0.001)
        XCTAssertEqual(schedule.totalEscrow, 300, accuracy: 0.001)
        XCTAssertEqual(schedule.years[0].endingBalance, 0, accuracy: 0.001)
    }

    func testAmortizationScheduleHandlesInsufficientPayment() {
        let schedule = DebtPayoffCalculator.amortizationSchedule(
            balance: 10_000,
            annualPercentageRate: 24,
            monthlyPayment: 100,
            firstPaymentDate: Date()
        )

        XCTAssertEqual(schedule.status, .insufficientPayment)
        XCTAssertTrue(schedule.years.isEmpty)
    }
}
