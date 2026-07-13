import Foundation

// MARK: - Public Types

struct SafeSpendResult {
    /// Final amount safe to spend today: min(cashAvailableAfterObligations, budgetDailyAllowance)
    /// when active budgets exist, otherwise cashAvailableAfterObligations — clamped to 0.
    let safeToSpendToday: Double
    let liquidBalance: Double
    let requiredBuffer: Double
    let upcomingNetOutflowReserve: Double
    let plannedSavingsReserve: Double
    /// Cash side of the calculation: liquidBalance - requiredBuffer - upcomingNetOutflowReserve
    /// - plannedSavingsReserve. Not clamped, so a negative value is visible in the breakdown.
    let cashAvailableAfterObligations: Double
    /// Sum, across active budgets, of each budget's remaining amount (floored at 0) divided by
    /// the days left in its current period. Only constrains the result when active budgets exist.
    let budgetDailyAllowance: Double
    let hasActiveBudgets: Bool
    /// Names of active savings goals with no target date — not reserved for, shown as
    /// "not scheduled" in the detail view.
    let unscheduledSavingsGoalNames: [String]
    let projectedThirtyDayBalance: Double
    let thirtyDayNetWorthDelta: Double
    let status: SafeSpendStatus
}

enum SafeSpendStatus {
    case onTrack
    case tight
    case pause
}

// MARK: - SafeSpendCalculator

enum SafeSpendCalculator {

    // ASSUMPTION: The buffer floor and "tight" sensitivity are fixed v1 defaults,
    // not user-configurable settings.
    private static let minimumBuffer: Double = 500
    private static let bufferDaysOfExpenses: Double = 7
    private static let tightStatusFloor: Double = 25
    private static let tightStatusExpenseFraction: Double = 0.25

    // MARK: Buffer

    // ASSUMPTION: Buffer sizing is driven by recent spending pace, with a $500 floor
    // so a thin transaction history doesn't produce an unrealistically small buffer.
    // Unlike ForecastEngine.averageDailyNetFlow, this deliberately keeps auto-generated
    // recurring history — there's no separate recurring add-back paired with the buffer,
    // so excluding it would understate real recent spending pace.
    static func averageDailyExpenses(from transactions: [Transaction], lookbackDays: Int = 60) -> Double {
        let calendar = Calendar.current
        let now = Date.now
        guard let since = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return 0 }

        let recentExpenses = transactions.filter {
            $0.type == .expense && !$0.isAdjustment && $0.date >= since && $0.date <= now
        }
        guard !recentExpenses.isEmpty else { return 0 }

        let total = recentExpenses.reduce(0.0) { $0 + $1.amount }
        return total / Double(max(lookbackDays, 1))
    }

    static func requiredBuffer(transactions: [Transaction], lookbackDays: Int = 60) -> Double {
        let avgDailyExpenses = averageDailyExpenses(from: transactions, lookbackDays: lookbackDays)
        return max(minimumBuffer, avgDailyExpenses * bufferDaysOfExpenses)
    }

    // MARK: Upcoming obligations

    // ASSUMPTION: Recurring income within the horizon offsets recurring expenses;
    // only a net outflow is reserved. A net inflow does not increase safe-to-spend.
    static func upcomingNetOutflowReserve(
        recurring: [RecurringTransaction],
        accounts: [Account] = [],
        horizonDays: Int
    ) -> Double {
        let events = ForecastEngine.upcomingEvents(from: recurring, accounts: accounts, horizonDays: horizonDays)
        let net = events.reduce(0.0) { $0 + $1.amount }
        return max(0, -net)
    }

    // MARK: Budget allowance

    // ASSUMPTION: Each active budget protects spending explicitly linked to it. A budget
    // already over its limit contributes zero (not negative) to the combined allowance,
    // so one over-budget line drags the total down without other budgets going negative.
    // When no active budgets exist, the budget side imposes no constraint.
    static func budgetDailyAllowance(budgets: [Budget], transactions: [Transaction]) -> Double {
        budgets
            .filter { $0.isActive }
            .reduce(0.0) { partial, budget in
                let remainingToday = max(0, budget.remaining(from: transactions))
                let days = Double(budget.daysRemainingInCurrentPeriod())
                return partial + remainingToday / days
            }
    }

    // MARK: Savings reserve

    // ASSUMPTION: Only active goals with a future target date and remaining progress
    // reserve a daily contribution (remainingAmount / daysRemaining). Goals without a
    // target date aren't reserved for — they're surfaced as "not scheduled" instead of
    // guessing at a contribution amount. Linked-account goals naturally use the live
    // account balance because `remainingAmount` is derived from `currentAmount`, which
    // already resolves the linked balance.
    static func plannedSavingsReserve(
        savingsGoals: [SavingsGoal]
    ) -> (reserve: Double, unscheduledNames: [String]) {
        var reserve = 0.0
        var unscheduled: [String] = []

        for goal in savingsGoals where goal.isActive {
            guard let days = goal.daysRemaining else {
                unscheduled.append(goal.name)
                continue
            }
            guard days > 0, goal.remainingAmount > 0 else { continue }
            reserve += goal.remainingAmount / Double(days)
        }

        return (reserve, unscheduled.sorted())
    }

    // MARK: Status

    static func status(safeToSpendToday: Double, averageDailyExpenses: Double) -> SafeSpendStatus {
        guard safeToSpendToday > 0 else { return .pause }
        let tightCeiling = max(tightStatusFloor, averageDailyExpenses * tightStatusExpenseFraction)
        return safeToSpendToday <= tightCeiling ? .tight : .onTrack
    }

    // MARK: Full calculation

    static func calculate(
        accounts: [Account],
        transactions: [Transaction],
        recurring: [RecurringTransaction],
        budgets: [Budget],
        savingsGoals: [SavingsGoal],
        horizonDays: Int = 30
    ) -> SafeSpendResult {
        let liquid = ForecastEngine.liquidBalance(from: accounts)
        let avgDailyExpenses = averageDailyExpenses(from: transactions)
        let buffer = max(minimumBuffer, avgDailyExpenses * bufferDaysOfExpenses)
        let outflowReserve = upcomingNetOutflowReserve(recurring: recurring, accounts: accounts, horizonDays: horizonDays)
        let (savingsReserve, unscheduledNames) = plannedSavingsReserve(savingsGoals: savingsGoals)

        let cashAvailable = liquid - buffer - outflowReserve - savingsReserve

        let activeBudgets = budgets.filter { $0.isActive }
        let hasActiveBudgets = !activeBudgets.isEmpty
        let budgetAllowance = budgetDailyAllowance(budgets: activeBudgets, transactions: transactions)

        let combined = hasActiveBudgets ? min(cashAvailable, budgetAllowance) : cashAvailable
        let safe = max(0, combined)

        let forecast = ForecastEngine.buildForecast(
            accounts: accounts,
            transactions: transactions,
            recurring: recurring,
            horizonDays: horizonDays
        )
        let projectedBalance = forecast.points.last?.balance ?? liquid

        return SafeSpendResult(
            safeToSpendToday: safe,
            liquidBalance: liquid,
            requiredBuffer: buffer,
            upcomingNetOutflowReserve: outflowReserve,
            plannedSavingsReserve: savingsReserve,
            cashAvailableAfterObligations: cashAvailable,
            budgetDailyAllowance: budgetAllowance,
            hasActiveBudgets: hasActiveBudgets,
            unscheduledSavingsGoalNames: unscheduledNames,
            projectedThirtyDayBalance: projectedBalance,
            thirtyDayNetWorthDelta: projectedBalance - liquid,
            status: status(safeToSpendToday: safe, averageDailyExpenses: avgDailyExpenses)
        )
    }
}
