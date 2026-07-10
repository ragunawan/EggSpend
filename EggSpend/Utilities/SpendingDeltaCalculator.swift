import Foundation

/// "What changed this month?" — compares each category's current-month spend
/// against its trailing-3-month average and renders the biggest movers as
/// plain-English sentences.
///
/// Note on `isGenerated` (deliberately diverges from `ForecastEngine`'s drift
/// convention): `ForecastEngine` excludes materialized recurring transactions
/// from some of its projection math to avoid double-counting a recurring
/// event that is both "already happened" and "still projected forward."
/// This calculator only ever looks backward at real spend that already
/// happened, so a materialized recurring transaction (`isGenerated == true`)
/// is real money spent and must be counted — there is no projection to
/// double-count against. This matches `MonthlyReviewCalculator.topCategories`
/// exactly, which also does not filter on `isGenerated`.
enum SpendingDeltaCalculator {

    struct CategoryDelta: Identifiable {
        var id: String { categoryName }
        let categoryName: String
        let icon: String
        let currentAmount: Double
        let trailingAverage: Double
        var delta: Double { currentAmount - trailingAverage }
        /// Deterministic, template-based sentence describing the delta, pinned at
        /// construction time to the `locale` passed into `calculate(...)`. Amounts
        /// are always rendered as an absolute value via `CurrencyFormat` (never a
        /// raw minus sign) — direction is conveyed in words instead.
        let sentence: String
        /// Exactly the currency strings interpolated into `sentence`, in order —
        /// the `expectedFigures` a `NarrativeGenerator` caller must pass so the
        /// figure-preservation validator can hold an AI rewrite to these values.
        /// Kept in lockstep with the sentence templates below; never derived
        /// separately in view code.
        let figures: [String]

        init(categoryName: String, icon: String, currentAmount: Double, trailingAverage: Double, locale: Locale) {
            self.categoryName = categoryName
            self.icon = icon
            self.currentAmount = currentAmount
            self.trailingAverage = trailingAverage
            let delta = currentAmount - trailingAverage
            if delta > 0 {
                let figure = CurrencyFormat.money(abs(delta), locale: locale)
                sentence = "\(categoryName) is \(figure) above your usual pace."
                figures = [figure]
            } else if currentAmount > 0 {
                let figure = CurrencyFormat.money(abs(delta), locale: locale)
                sentence = "\(categoryName) is \(figure) below your usual pace."
                figures = [figure]
            } else {
                // currentAmount == 0 and trailingAverage > 0 (spend stopped entirely).
                let figure = CurrencyFormat.money(trailingAverage, locale: locale)
                sentence = "You haven't spent on \(categoryName) this month, down from your usual \(figure)."
                figures = [figure]
            }
        }
    }

    /// True iff there is at least one full prior calendar month of history to compare
    /// against — i.e. the earliest transaction's month-start is on or before the start
    /// of the calendar month immediately preceding the current one. An account whose
    /// oldest transaction falls within the current month (e.g. day 3 after first use)
    /// has non-empty transactions but still fails this bar.
    static func hasSufficientHistory(
        transactions: [Transaction],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let earliest = transactions.map(\.date).min() else { return false }
        let currentMonthStart = calendar.startOfMonth(for: now)
        guard let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) else {
            return false
        }
        let earliestMonthStart = calendar.startOfMonth(for: earliest)
        return earliestMonthStart <= previousMonthStart
    }

    /// Per-category expense totals for a single calendar month window, keyed the same
    /// way `MonthlyReviewCalculator.topCategories` keys its dictionary (category name,
    /// or "Uncategorized"), filtered to `type == .expense && !isAdjustment` — reused
    /// verbatim from `MonthlyReviewCalculator` so this calculator never diverges from
    /// the app's one "excludes balance-adjustment rows from spend metrics" convention.
    private static func categoryTotals(
        transactions: [Transaction],
        monthStart: Date
    ) -> [String: (icon: String, amount: Double)] {
        let (start, end) = MonthlyReviewCalculator.monthBounds(for: monthStart)
        var dict: [String: (icon: String, amount: Double)] = [:]
        for tx in transactions where tx.type == .expense && !tx.isAdjustment && tx.date >= start && tx.date < end {
            let key = tx.category?.name ?? "Uncategorized"
            let icon = tx.category?.icon ?? "questionmark.circle"
            dict[key] = (icon, (dict[key]?.amount ?? 0) + tx.amount)
        }
        return dict
    }

    /// Top `topN` categories by absolute current-month-vs-trailing-average delta.
    /// Returns `[]` when there isn't at least one full prior month of history
    /// (per `hasSufficientHistory`).
    static func calculate(
        transactions: [Transaction],
        asOf now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        topN: Int = 3
    ) -> [CategoryDelta] {
        guard hasSufficientHistory(transactions: transactions, asOf: now, calendar: calendar) else { return [] }

        let currentMonthStart = calendar.startOfMonth(for: now)
        let earliestMonthStart = calendar.startOfMonth(for: transactions.map(\.date).min() ?? now)

        // The three calendar months immediately prior to the current one.
        let trailingMonthStarts: [Date] = (1...3).compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonthStart)
        }
        // Only average over trailing months whose start is on/after the earliest
        // transaction's month — a partial-history user (e.g. joined 6 weeks ago)
        // shouldn't have their average diluted by empty pre-history months.
        let usableTrailingMonthStarts = trailingMonthStarts.filter { $0 >= earliestMonthStart }

        let currentTotals = categoryTotals(transactions: transactions, monthStart: currentMonthStart)
        let trailingTotalsPerMonth = usableTrailingMonthStarts.map {
            categoryTotals(transactions: transactions, monthStart: $0)
        }

        // Zero-fill both directions: a category present only this month gets a 0
        // trailing average; a category present only in trailing months gets a 0
        // current amount — neither is silently dropped.
        var categoryNames = Set(currentTotals.keys)
        for totals in trailingTotalsPerMonth { categoryNames.formUnion(totals.keys) }

        let divisor = max(usableTrailingMonthStarts.count, 1)

        let deltas: [CategoryDelta] = categoryNames.map { name in
            let current = currentTotals[name]?.amount ?? 0
            let icon = currentTotals[name]?.icon
                ?? trailingTotalsPerMonth.compactMap { $0[name]?.icon }.first
                ?? "questionmark.circle"
            let trailingSum = trailingTotalsPerMonth.reduce(0.0) { $0 + ($1[name]?.amount ?? 0) }
            let trailingAverage = trailingSum / Double(divisor)
            return CategoryDelta(categoryName: name, icon: icon, currentAmount: current,
                                  trailingAverage: trailingAverage, locale: locale)
        }

        return deltas
            .filter { $0.delta != 0 }
            // Secondary sort by name keeps output deterministic when two categories
            // tie on |delta| — `categoryNames` is a Set, so iteration order alone
            // isn't reliable ("deterministic sentences" is an acceptance-bar requirement).
            .sorted {
                abs($0.delta) != abs($1.delta) ? abs($0.delta) > abs($1.delta) : $0.categoryName < $1.categoryName
            }
            .prefix(topN)
            .map { $0 }
    }
}
