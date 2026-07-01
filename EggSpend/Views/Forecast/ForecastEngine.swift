import Foundation

// MARK: - Public Types

struct ForecastDataPoint {
    let date: Date
    let balance: Double
    let isProjected: Bool
}

struct ForecastEvent: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    /// Positive = inflow, negative = outflow.
    let amount: Double
    let categoryIcon: String

    init(date: Date, title: String, amount: Double, categoryIcon: String = "arrow.clockwise") {
        self.id = UUID()
        self.date = date
        self.title = title
        self.amount = amount
        self.categoryIcon = categoryIcon
    }
}

// MARK: - ForecastEngine

struct ForecastEngine {

    // ASSUMPTION: Only checking and savings accounts contribute to the liquid cash baseline.
    // Investment accounts are excluded — not treated as available for day-to-day spending.
    // Credit card and loan balances are liabilities and are excluded from starting balance.
    static func liquidBalance(from accounts: [Account]) -> Double {
        accounts
            .filter { $0.type == .checking || $0.type == .savings }
            .reduce(0.0) { $0 + $1.balance }
    }

    // ASSUMPTION: Average daily net flow is derived from the most recent `lookbackDays`
    // of actual transactions. Because historically-generated recurring transactions are
    // included in this history, projecting explicit recurring events on top of this drift
    // may cause slight double-counting. The forecast is directional, not accounting-precise.
    static func averageDailyNetFlow(from transactions: [Transaction], lookbackDays: Int = 60) -> Double {
        let calendar = Calendar.current
        let now = Date.now
        guard let since = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return 0 }

        let recent = transactions.filter { $0.date >= since && $0.date <= now }
        guard !recent.isEmpty else { return 0 }

        let netTotal = recent.reduce(0.0) { $0 + $1.signedAmount }
        return netTotal / Double(max(lookbackDays, 1))
    }

    // Projects upcoming recurring events within `horizonDays` from today.
    // Items whose nextDueDate is already past are fast-forwarded to the first
    // occurrence on or after today before the enumeration begins.
    // ASSUMPTION: Paused (isActive == false) and expired (endDate < now) items are excluded.
    static func upcomingEvents(
        from recurring: [RecurringTransaction],
        horizonDays: Int
    ) -> [ForecastEvent] {
        RecurringProjection.occurrences(from: recurring, start: .now, days: horizonDays)
            .map { occurrence in
                ForecastEvent(
                    date: occurrence.dueDate,
                    title: occurrence.title,
                    amount: occurrence.signedAmount,
                    categoryIcon: occurrence.category?.icon ?? occurrence.source.frequency.icon
                )
            }
    }

    // Builds one data point per day (today + horizonDays).
    // Each day's balance = prior balance + dailyDrift + sum of recurring events on that day.
    static func buildForecast(
        accounts: [Account],
        transactions: [Transaction],
        recurring: [RecurringTransaction],
        horizonDays: Int
    ) -> (points: [ForecastDataPoint], events: [ForecastEvent]) {
        let calendar = Calendar.current
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)

        let startBalance = liquidBalance(from: accounts)
        let dailyDrift = averageDailyNetFlow(from: transactions)
        let events = upcomingEvents(from: recurring, horizonDays: horizonDays)

        var points: [ForecastDataPoint] = []
        var runningBalance = startBalance

        // Anchor: today's known liquid balance
        points.append(ForecastDataPoint(date: todayStart, balance: startBalance, isProjected: false))

        for dayOffset in 1...max(horizonDays, 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }

            // Recurring events scheduled on this exact calendar day
            let dayRecurring = events.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let recurringDelta = dayRecurring.reduce(0.0) { $0 + $1.amount }

            runningBalance += dailyDrift + recurringDelta
            points.append(ForecastDataPoint(date: date, balance: runningBalance, isProjected: true))
        }

        return (points, events)
    }
}
