import SwiftData
import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case investment = "Investment"
    case credit = "Credit Card"
    case loan = "Loan"
    case other = "Other"

    var id: String { rawValue }

    var isAsset: Bool {
        switch self {
        case .checking, .savings, .investment, .other: return true
        case .credit, .loan: return false
        }
    }

    var icon: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "building.columns"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .credit: return "creditcard"
        case .loan: return "doc.text.fill"
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

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var isAsset: Bool { type.isAsset }

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \SavingsGoal.linkedAccount)
    var savingsGoals: [SavingsGoal]? = []

    init(name: String, type: AccountType, balance: Double, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.balance = balance
        self.notes = notes
        self.createdAt = .now
        self.transactions = []
        self.savingsGoals = []
    }
}
