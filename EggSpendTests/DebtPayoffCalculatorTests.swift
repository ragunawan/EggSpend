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
}
