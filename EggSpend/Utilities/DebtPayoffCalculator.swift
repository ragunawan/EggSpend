import Foundation

struct DebtPayoffResult: Equatable {
    enum Status: Equatable {
        case paidOff
        case missingInputs
        case insufficientPayment
        case projected
    }

    let status: Status
    let months: Int
    let totalInterest: Double
    let payoffDate: Date?
}

enum DebtPayoffCalculator {
    static func calculate(
        balance: Double,
        annualPercentageRate: Double?,
        minimumPayment: Double?,
        extraPayment: Double = 0,
        startDate: Date = .now,
        calendar: Calendar = .current
    ) -> DebtPayoffResult {
        let principal = abs(balance)
        guard principal > 0 else {
            return DebtPayoffResult(status: .paidOff, months: 0, totalInterest: 0, payoffDate: startDate)
        }
        guard let apr = annualPercentageRate, let minimumPayment else {
            return DebtPayoffResult(status: .missingInputs, months: 0, totalInterest: 0, payoffDate: nil)
        }

        let monthlyPayment = max(0, minimumPayment) + max(0, extraPayment)
        guard monthlyPayment > 0 else {
            return DebtPayoffResult(status: .insufficientPayment, months: 0, totalInterest: 0, payoffDate: nil)
        }

        let monthlyRate = max(0, apr) / 100 / 12
        if monthlyRate > 0, monthlyPayment <= principal * monthlyRate {
            return DebtPayoffResult(status: .insufficientPayment, months: 0, totalInterest: 0, payoffDate: nil)
        }

        var remaining = principal
        var months = 0
        var interestPaid = 0.0

        while remaining > 0.005 && months < 1_200 {
            let interest = remaining * monthlyRate
            interestPaid += interest
            remaining += interest
            remaining -= min(monthlyPayment, remaining)
            months += 1
        }

        guard months < 1_200 else {
            return DebtPayoffResult(status: .insufficientPayment, months: 0, totalInterest: interestPaid, payoffDate: nil)
        }

        let payoffDate = calendar.date(byAdding: .month, value: months, to: startDate)
        return DebtPayoffResult(status: .projected, months: months, totalInterest: interestPaid, payoffDate: payoffDate)
    }
}
