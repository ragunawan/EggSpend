import SwiftData
import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"

    var sign: Double { self == .income ? 1.0 : -1.0 }
    var systemImage: String { self == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill" }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var date: Date = Date.now
    var typeRaw: String = TransactionType.expense.rawValue
    var notes: String = ""
    var createdAt: Date = Date.now
    var isGenerated: Bool = false
    var recurringSourceID: UUID?
    var recurringDueDate: Date?

    @Relationship(deleteRule: .nullify)
    var category: TransactionCategory?

    @Relationship(deleteRule: .nullify)
    var account: Account?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var signedAmount: Double { type == .income ? amount : -amount }

    init(
        title: String,
        amount: Double,
        date: Date = .now,
        type: TransactionType,
        category: TransactionCategory? = nil,
        account: Account? = nil,
        notes: String = "",
        isGenerated: Bool = false,
        recurringSourceID: UUID? = nil,
        recurringDueDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.amount = abs(amount)
        self.date = date
        self.typeRaw = type.rawValue
        self.category = category
        self.account = account
        self.notes = notes
        self.createdAt = .now
        self.isGenerated = isGenerated
        self.recurringSourceID = recurringSourceID
        self.recurringDueDate = recurringDueDate
    }
}
