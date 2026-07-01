import SwiftData
import Foundation
import SwiftUI
// Color extensions (init?(hex:), init(lightHex:darkHex:), hexString, semantic colors)
// are defined in EggSpendTheme.swift

@Model
final class TransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = ""
    var colorHex: String = ""
    var typeFilter: String?
    var isArchived: Bool = false
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \Budget.category)
    var budgets: [Budget]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurringTransactions: [RecurringTransaction]? = []

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var appliesTo: TransactionType? {
        guard let raw = typeFilter else { return nil }
        return TransactionType(rawValue: raw)
    }

    init(name: String, icon: String, colorHex: String, typeFilter: TransactionType? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.typeFilter = typeFilter?.rawValue
        self.isArchived = false
        self.sortOrder = sortOrder
        self.transactions = []
        self.budgets = []
        self.recurringTransactions = []
    }
}
