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
            .filter { !$0.isArchived && ($0.type == .checking || $0.type == .savings) }
            .reduce(0.0) { $0 + $1.balance }
    }

    // ASSUMPTION: Average daily net flow is derived from the most recent `lookbackDays`
    // of *organic* transactions only — auto-generated recurring transactions
    // (`isGenerated == true`) are excluded, alongside balance adjustments. Recurring flows
    // enter the forecast solely through the explicit `upcomingEvents` schedule below, so
    // each recurring obligation is counted exactly once (drift no longer double-counts it).
    // Accepted side effect: a recently paused or expired recurring item's generated history
    // no longer drags the drift — an obligation that has ended shouldn't project forward.
    static func averageDailyNetFlow(from transactions: [Transaction], lookbackDays: Int = 60) -> Double {
        let calendar = Calendar.current
        let now = Date.now
        guard let since = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return 0 }

        let recent = transactions.filter {
            $0.date >= since && $0.date <= now && !$0.isAdjustment && !$0.isGenerated
        }
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
        accounts: [Account] = [],
        horizonDays: Int
    ) -> [ForecastEvent] {
        let recurringEvents = RecurringProjection.occurrences(from: recurring, start: .now, days: horizonDays)
            .map { occurrence in
                ForecastEvent(
                    date: occurrence.dueDate,
                    title: occurrence.title,
                    amount: occurrence.signedAmount,
                    categoryIcon: occurrence.category?.icon ?? occurrence.source.frequency.icon
                )
            }

        return (recurringEvents + creditCardPaymentEvents(from: accounts))
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date < rhs.date
            }
    }

    static func creditCardPaymentEvents(
        from accounts: [Account],
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> [ForecastEvent] {
        let today = calendar.startOfDay(for: date)
        guard let twoWeeksOut = calendar.date(byAdding: .day, value: 14, to: today) else { return [] }

        return accounts.compactMap { account in
            guard !account.isArchived, account.type == .credit, let dueDate = account.nextDueDate else {
                return nil
            }

            let dueDay = calendar.startOfDay(for: dueDate)
            guard dueDay >= today else { return nil }

            let dueThisMonth = calendar.isDate(dueDay, equalTo: today, toGranularity: .month)
                && calendar.isDate(dueDay, equalTo: today, toGranularity: .year)
            guard dueThisMonth || dueDay <= twoWeeksOut else { return nil }

            let paymentAmount = max(account.minimumPayment ?? 0, 0)
            let fallbackAmount = max(abs(account.balance), 0)
            let amount = paymentAmount > 0 ? paymentAmount : fallbackAmount
            guard amount > 0 else { return nil }

            return ForecastEvent(
                date: dueDay,
                title: "\(account.name) payment",
                amount: -amount,
                categoryIcon: account.type.icon
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
        let events = upcomingEvents(from: recurring, accounts: accounts, horizonDays: horizonDays)

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
