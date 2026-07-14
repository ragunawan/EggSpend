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

struct AmortizationPayment: Identifiable, Equatable {
    let id: Int
    let date: Date
    let beginningBalance: Double
    let payment: Double
    let principal: Double
    let interest: Double
    let extraPayment: Double
    let escrow: Double
    let endingBalance: Double
}

struct AmortizationYear: Identifiable, Equatable {
    let id: Int
    let year: Int
    let payments: [AmortizationPayment]

    var principal: Double { payments.reduce(0) { $0 + $1.principal } }
    var interest: Double { payments.reduce(0) { $0 + $1.interest } }
    var escrow: Double { payments.reduce(0) { $0 + $1.escrow } }
    var totalPaid: Double { payments.reduce(0) { $0 + $1.payment + $1.escrow } }
    var endingBalance: Double { payments.last?.endingBalance ?? 0 }
}

struct AmortizationSchedule: Equatable {
    enum Status: Equatable {
        case paidOff
        case missingInputs
        case insufficientPayment
        case projected
    }

    let status: Status
    let years: [AmortizationYear]
    let totalInterest: Double
    let totalPrincipal: Double
    let totalEscrow: Double
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

    static func amortizationSchedule(
        balance: Double,
        annualPercentageRate: Double?,
        monthlyPayment: Double?,
        extraPayment: Double = 0,
        firstPaymentDate: Date,
        monthlyEscrow: Double = 0,
        calendar: Calendar = .current
    ) -> AmortizationSchedule {
        var remaining = abs(balance)
        guard remaining > 0 else {
            return AmortizationSchedule(
                status: .paidOff,
                years: [],
                totalInterest: 0,
                totalPrincipal: 0,
                totalEscrow: 0,
                payoffDate: firstPaymentDate
            )
        }
        guard let apr = annualPercentageRate, let monthlyPayment else {
            return AmortizationSchedule(
                status: .missingInputs,
                years: [],
                totalInterest: 0,
                totalPrincipal: 0,
                totalEscrow: 0,
                payoffDate: nil
            )
        }

        let basePayment = max(0, monthlyPayment)
        let extra = max(0, extraPayment)
        let principalAndInterestPayment = basePayment + extra
        guard principalAndInterestPayment > 0 else {
            return AmortizationSchedule(
                status: .insufficientPayment,
                years: [],
                totalInterest: 0,
                totalPrincipal: 0,
                totalEscrow: 0,
                payoffDate: nil
            )
        }

        let monthlyRate = max(0, apr) / 100 / 12
        if monthlyRate > 0, principalAndInterestPayment <= remaining * monthlyRate {
            return AmortizationSchedule(
                status: .insufficientPayment,
                years: [],
                totalInterest: 0,
                totalPrincipal: 0,
                totalEscrow: 0,
                payoffDate: nil
            )
        }

        var payments: [AmortizationPayment] = []
        var monthIndex = 0
        let escrow = max(0, monthlyEscrow)

        while remaining > 0.005 && monthIndex < 1_200 {
            let interest = remaining * monthlyRate
            let availableForPrincipal = max(0, principalAndInterestPayment - interest)
            let principal = min(remaining, availableForPrincipal)
            let actualPayment = principal + interest
            let endingBalance = max(0, remaining - principal)
            let date = calendar.date(byAdding: .month, value: monthIndex, to: firstPaymentDate) ?? firstPaymentDate

            payments.append(
                AmortizationPayment(
                    id: monthIndex + 1,
                    date: date,
                    beginningBalance: remaining,
                    payment: actualPayment,
                    principal: principal,
                    interest: interest,
                    extraPayment: min(extra, principal),
                    escrow: escrow,
                    endingBalance: endingBalance
                )
            )

            remaining = endingBalance
            monthIndex += 1
        }

        guard monthIndex < 1_200 else {
            return AmortizationSchedule(
                status: .insufficientPayment,
                years: [],
                totalInterest: payments.reduce(0) { $0 + $1.interest },
                totalPrincipal: payments.reduce(0) { $0 + $1.principal },
                totalEscrow: payments.reduce(0) { $0 + $1.escrow },
                payoffDate: nil
            )
        }

        let grouped = Dictionary(grouping: payments) { payment in
            calendar.component(.year, from: payment.date)
        }
        let years = grouped.keys.sorted().enumerated().map { index, year in
            AmortizationYear(
                id: index,
                year: year,
                payments: grouped[year]?.sorted { $0.id < $1.id } ?? []
            )
        }

        return AmortizationSchedule(
            status: .projected,
            years: years,
            totalInterest: payments.reduce(0) { $0 + $1.interest },
            totalPrincipal: payments.reduce(0) { $0 + $1.principal },
            totalEscrow: payments.reduce(0) { $0 + $1.escrow },
            payoffDate: payments.last?.date
        )
    }
}
