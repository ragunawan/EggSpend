import Foundation
import SwiftData

/// Learns and applies "title -> category" rules from the user's own manual
/// categorization choices, so future entries/imports with the same title can
/// be auto-suggested a category instead of always starting uncategorized.
///
/// Matching is exact-normalized-title v1: two titles match only if
/// `CSVParser.normalizedTitle` (case-folding and whitespace collapsing only)
/// produces the same string. A digit-variant title such as
/// "BLUE BOTTLE 0423" deliberately does NOT match a rule recorded for
/// "Blue Bottle Coffee" — false negatives here are cheap (one more manual
/// categorization, which itself creates/updates the rule for next time),
/// whereas false auto-assignments would silently corrupt financial data.
/// `SubscriptionDetector.clusterKey`-style fuzzing (stripping digits/
/// punctuation) is a plausible v2 if false negatives prove too common in
/// practice, but is deliberately out of scope here.
///
/// Forward notes for the T17b management/UI layer:
/// - The "delete rule" management action must delete ALL rows for a pattern
///   (not just the latest), since duplicate rows per pattern are tolerated by
///   design (see `CategoryRule`'s doc comment) and a partial delete would
///   leave a stale row that could resurface as the "latest" later.
/// - Import auto-assignment should apply only to rows that are currently
///   UNCATEGORIZED (never overwrite an explicit category the import already
///   inferred/set), and should be visually distinguished with its own preview
///   badge so the user can tell "the rule engine guessed this" apart from
///   "the CSV/column mapping said this".
enum CategoryRuleEngine {
    /// Records (or updates) the rule that `title` should map to `category`.
    /// This is an upsert *attempt*: existing rows for the normalized pattern
    /// are fetched and the most recent one is updated in place; if none
    /// exist, a new row is inserted. Cross-device CloudKit sync can still
    /// race two upserts into two rows for the same pattern — reads tolerate
    /// this (see `categoryFor`), so it isn't swept here.
    ///
    /// - Parameters:
    ///   - title: The raw (unnormalized) transaction title the user just categorized.
    ///   - category: The category the user assigned.
    ///   - context: The `ModelContext` used to fetch existing rules, insert/update, and save.
    ///   - now: Injectable "now" for deterministic tests.
    /// - Returns: The `CategoryRule` row that was updated or inserted.
    @discardableResult
    static func recordRule(
        title: String,
        category: TransactionCategory,
        context: ModelContext,
        now: Date = .now
    ) -> CategoryRule {
        let pattern = CSVParser.normalizedTitle(title)
        // A fetch failure here (nil-coalesced to []) is itself a second, rarer
        // duplication source beyond the CloudKit sync race documented above:
        // it makes an existing rule for this pattern invisible, so a new row
        // is inserted below instead of updating in place. The read-side
        // latest-wins tolerance in `categoryFor` covers this case too.
        let existingRules = (try? context.fetch(FetchDescriptor<CategoryRule>())) ?? []
        let matching = existingRules.filter { $0.normalizedPattern == pattern }

        if let latest = matching.max(by: { $0.createdAt < $1.createdAt }) {
            latest.categoryID = category.id
            latest.createdAt = now
            do {
                try context.save()
            } catch {
                print("CategoryRuleEngine: failed to save rule: \(error)")
            }
            return latest
        }

        let rule = CategoryRule(normalizedPattern: pattern, categoryID: category.id, createdAt: now)
        context.insert(rule)
        do {
            try context.save()
        } catch {
            print("CategoryRuleEngine: failed to save rule: \(error)")
        }
        return rule
    }

    /// Resolves the category a matching rule points to for `title`, or `nil`
    /// if no rule matches (or the matching rule's category has since been
    /// deleted). When multiple rows exist for the same normalized pattern
    /// (tolerated duplicates — see `CategoryRule`'s doc comment), the row
    /// with the latest `createdAt` wins.
    ///
    /// - Parameters:
    ///   - title: The raw (unnormalized) title to look up.
    ///   - rules: All known `CategoryRule` rows.
    ///   - categories: All live `TransactionCategory` rows, used to resolve
    ///     `categoryID` back to a category (and to detect dangling ids).
    static func categoryFor(
        title: String,
        rules: [CategoryRule],
        categories: [TransactionCategory]
    ) -> TransactionCategory? {
        let pattern = CSVParser.normalizedTitle(title)
        guard let latest = rules
            .filter({ $0.normalizedPattern == pattern })
            .max(by: { $0.createdAt < $1.createdAt })
        else { return nil }
        return categories.first { $0.id == latest.categoryID }
    }
}
