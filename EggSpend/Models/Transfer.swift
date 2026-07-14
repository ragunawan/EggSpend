import SwiftData
import Foundation

@Model
final class Transfer {
    var id: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify)
    var fromAccount: Account?

    @Relationship(deleteRule: .nullify)
    var toAccount: Account?

    /// Optional savings goal this transfer counts toward. Nullify (not cascade)
    /// so deleting the goal leaves the transfer intact — same rationale as
    /// `Transaction.budget`.
    @Relationship(deleteRule: .nullify)
    var savingsGoal: SavingsGoal?

    init(
        amount: Double,
        date: Date = .now,
        fromAccount: Account?,
        toAccount: Account?,
        savingsGoal: SavingsGoal? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.amount = abs(amount)
        self.date = date
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.savingsGoal = savingsGoal
        self.notes = notes
        self.createdAt = .now
    }
}
