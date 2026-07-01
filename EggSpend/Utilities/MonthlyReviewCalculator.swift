import Foundation

// MARK: - Output Types

struct MonthlyReviewData {
    let income: Double
    let expenses: Double
    let netSavings: Double
    let savingsRate: Double?       // nil when income == 0; negative when expenses > income
    let topCategories: [CategorySpend]
    let budgetOverruns: [BudgetOverrun]
    let netWorthAtStart: Double
    let netWorthAtEnd: Double
    let netWorthChange: Double
}

struct CategorySpend: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let amount: Double
}

struct BudgetOverrun: Identifiable {
    var id: String { name }
    let name: String
    let spent: Double
    let limit: Double
    var overage: Double { spent - limit }
    var progress: Double { limit > 0 ? spent / limit : 0 }
}

// MARK: - Calculator

enum MonthlyReviewCalculator {

    /// Start (inclusive) and end (exclusive) of the calendar month containing `date`.
    static func monthBounds(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfMonth(for: date)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Transactions whose date falls within the calendar month of `date`.
    static func filter(_ transactions: [Transaction], forMonth date: Date) -> [Transaction] {
        let (start, end) = monthBounds(for: date)
        return transactions.filter { $0.date >= start && $0.date < end }
    }

    /// Sum of income transaction amounts.
    static func income(from transactions: [Transaction]) -> Double {
        transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    /// Sum of expense transaction amounts.
    static func expenses(from transactions: [Transaction]) -> Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    /// (income − expenses) / income. Returns nil when income is zero.
    static func savingsRate(income: Double, expenses: Double) -> Double? {
        guard income > 0 else { return nil }
        return (income - expenses) / income
    }

    /// Top expense categories by total spend, capped at `limit` entries.
    static func topCategories(from transactions: [Transaction], limit: Int = 5) -> [CategorySpend] {
        var dict: [String: (icon: String, amount: Double)] = [:]
        for tx in transactions where tx.type == .expense {
            let key  = tx.category?.name ?? "Uncategorized"
            let icon = tx.category?.icon ?? "questionmark.circle"
            dict[key] = (icon, (dict[key]?.amount ?? 0) + tx.amount)
        }
        return dict
            .map { CategorySpend(name: $0.key, icon: $0.value.icon, amount: $0.value.amount) }
            .sorted { $0.amount > $1.amount }
            .prefix(limit)
            .map { $0 }
    }

    /// Monthly budgets whose spending in `month` exceeds their limit, sorted by overage descending.
    /// Only monthly-period budgets are evaluated; weekly/yearly periods don't map cleanly to a calendar month.
    static func budgetOverruns(
        budgets: [Budget],
        transactions: [Transaction],
        month: Date
    ) -> [BudgetOverrun] {
        let (start, end) = monthBounds(for: month)
        return budgets
            .filter { $0.period == .monthly && $0.isActive }
            .compactMap { budget in
                let spent = transactions
                    .filter { tx in
                        guard tx.type == .expense else { return false }
                        guard tx.date >= start && tx.date < end else { return false }
                        if let cat = budget.category {
                            return tx.category?.id == cat.id
                        } else {
                            return tx.category == nil
                        }
                    }
                    .reduce(0) { $0 + $1.amount }
                guard spent > budget.limitAmount else { return nil }
                return BudgetOverrun(name: budget.name, spent: spent, limit: budget.limitAmount)
            }
            .sorted { $0.overage > $1.overage }
    }

    /// Reconstructs the net worth at `date` by starting from the current account balances
    /// and reversing every transaction that occurred after `date`.
    static func netWorth(accounts: [Account], allTransactions: [Transaction], at date: Date) -> Double {
        let current = accounts.reduce(0.0) { $0 + ($1.isAsset ? $1.balance : -$1.balance) }
        let delta = allTransactions
            .filter { $0.date > date }
            .reduce(0.0) { $0 + ($1.type == .income ? $1.amount : -$1.amount) }
        return current - delta
    }

    // MARK: - Full calculation

    static func calculate(
        month: Date,
        transactions: [Transaction],
        accounts: [Account],
        budgets: [Budget]
    ) -> MonthlyReviewData {
        let monthTx  = filter(transactions, forMonth: month)
        let inc      = income(from: monthTx)
        let exp      = expenses(from: monthTx)
        let (start, end) = monthBounds(for: month)
        let nwStart  = netWorth(accounts: accounts, allTransactions: transactions, at: start)
        let nwEnd    = netWorth(accounts: accounts, allTransactions: transactions, at: end)

        return MonthlyReviewData(
            income:          inc,
            expenses:        exp,
            netSavings:      inc - exp,
            savingsRate:     savingsRate(income: inc, expenses: exp),
            topCategories:   topCategories(from: monthTx),
            budgetOverruns:  budgetOverruns(budgets: budgets, transactions: transactions, month: month),
            netWorthAtStart: nwStart,
            netWorthAtEnd:   nwEnd,
            netWorthChange:  nwEnd - nwStart
        )
    }
}
