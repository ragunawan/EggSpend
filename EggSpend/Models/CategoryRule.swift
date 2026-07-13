import SwiftData
import Foundation

/// A learned "if a transaction's title normalizes to this pattern, assign this
/// category" rule, recorded by `CategoryRuleEngine` whenever the user manually
/// categorizes a transaction. Read back at import/entry time to auto-suggest
/// (never silently force) a category for a matching title.
///
/// Design notes (all stored properties are defaulted/optional for CloudKit):
/// - No `@Attribute(.unique)` on `normalizedPattern` — CloudKit does not
///   support unique constraints, so at-most-one-row-per-pattern is a
///   best-effort upsert in code (`CategoryRuleEngine.recordRule`), not a
///   schema guarantee.
/// - `categoryID` is a plain `UUID` copy of `TransactionCategory.id`, not a
///   `@Relationship`. Categories are hard-deleted (not soft-archived like
///   accounts — see T7), and a `.nullify` relationship would null out this
///   rule's category on category deletion. That collides with this domain:
///   here `nil`/dangling must always mean "no rule matches", never "matches
///   uncategorized". Budget membership is explicit on `Transaction.budget`,
///   so category rules must not be reused for budget matching. Keeping a
///   detached UUID lets a dangling id resolve
///   to no-match at read time instead of accidentally auto-assigning
///   uncategorized spend.
/// - Cross-device CloudKit sync can race and produce more than one row for
///   the same `normalizedPattern` (e.g. two devices recording a rule for the
///   same title before syncing). This is expected and tolerated on read, not
///   swept/deduplicated on write: readers pick the row with the latest
///   `createdAt` per pattern.
@Model
final class CategoryRule {
    var id: UUID = UUID()
    var normalizedPattern: String = ""
    var categoryID: UUID = UUID()
    var createdAt: Date = Date.now

    init(normalizedPattern: String, categoryID: UUID, createdAt: Date = .now) {
        self.id = UUID()
        self.normalizedPattern = normalizedPattern
        self.categoryID = categoryID
        self.createdAt = createdAt
    }
}
