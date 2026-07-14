import SwiftData
import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case investment = "Investment"
    case credit = "Credit Card"
    case loan = "Loan"
    case mortgage = "Mortgage"
    case other = "Other"

    var id: String { rawValue }

    var isAsset: Bool {
        switch self {
        case .checking, .savings, .investment, .other: return true
        case .credit, .loan, .mortgage: return false
        }
    }

    var isLiability: Bool { !isAsset }

    var icon: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "building.columns"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .credit: return "creditcard"
        case .loan: return "doc.text.fill"
        case .mortgage: return "house.fill"
        case .other: return "wallet.pass.fill"
        }
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.checking.rawValue
    var balance: Double = 0
    var notes: String = ""
    var createdAt: Date = Date.now
    var dueDate: Date?
    var annualPercentageRate: Double?
    var minimumPayment: Double?
    var plannedExtraPayment: Double?
    var mortgageOriginalPrincipal: Double?
    var mortgageTermMonths: Int?
    var mortgageFirstPaymentDate: Date?
    var mortgageMonthlyPropertyTax: Double?
    var mortgageMonthlyInsurance: Double?
    var mortgageMonthlyPMI: Double?
    var mortgageMonthlyEscrow: Double?
    var includeInNetWorth: Bool = true
    var isArchived: Bool = false
    var isDefaultChecking: Bool = false

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var isAsset: Bool { type.isAsset }
    var isLiability: Bool { type == .credit || type == .loan || type == .mortgage }
    var countsTowardNetWorth: Bool { isAsset || includeInNetWorth }
    var nextDueDate: Date? {
        guard isLiability, let dueDate else { return nil }
        return Self.rolledDueDate(from: dueDate)
    }

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \SavingsGoal.linkedAccount)
    var savingsGoals: [SavingsGoal]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transfer.fromAccount)
    var transfersOut: [Transfer]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transfer.toAccount)
    var transfersIn: [Transfer]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.account)
    var recurringTransactions: [RecurringTransaction]? = []

    init(name: String, type: AccountType, balance: Double, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.balance = balance
        self.notes = notes
        self.createdAt = .now
        self.transactions = []
        self.savingsGoals = []
        self.transfersOut = []
        self.transfersIn = []
        self.recurringTransactions = []
    }

    @discardableResult
    func rollDueDateIfNeeded(asOf date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isLiability, let dueDate else { return false }
        let rolled = Self.rolledDueDate(from: dueDate, asOf: date, calendar: calendar)
        guard rolled != dueDate else { return false }
        self.dueDate = rolled
        return true
    }

    static func rolledDueDate(from dueDate: Date, asOf date: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        var resolved = dueDate

        while calendar.startOfDay(for: resolved) < today {
            guard let next = calendar.date(byAdding: .month, value: 1, to: resolved) else {
                return resolved
            }
            resolved = next
        }

        return resolved
    }
}
