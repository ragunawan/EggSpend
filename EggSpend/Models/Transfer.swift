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

    init(
        amount: Double,
        date: Date = .now,
        fromAccount: Account?,
        toAccount: Account?,
        notes: String = ""
    ) {
        self.id = UUID()
        self.amount = abs(amount)
        self.date = date
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.notes = notes
        self.createdAt = .now
    }
}
