import SwiftUI
import SwiftData

private struct CashFlowCalendarDay: Identifiable {
    let id: Date
    let date: Date
    let actuals: [Transaction]
    let recurring: [RecurringOccurrence]
    let bills: [Account]
    let netFlow: Double
    let projectedBalance: Double
}

struct CashFlowCalendarView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true }, sort: \RecurringTransaction.nextDueDate)
    private var recurring: [RecurringTransaction]

    private let days = 30

    private var calendarDays: [CashFlowCalendarDay] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let recurringOccurrences = RecurringProjection.occurrences(from: recurring, start: start, days: days)
        var runningBalance = ForecastEngine.liquidBalance(from: accounts)

        return (0...days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let actuals = transactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let recurringForDay = recurringOccurrences.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            let bills = accounts.filter { account in
                guard !account.isArchived, account.isLiability, let dueDate = account.dueDate else { return false }
                return calendar.component(.day, from: dueDate) == calendar.component(.day, from: date)
            }
            let actualNet = actuals.reduce(0) { $0 + $1.signedAmount }
            let recurringNet = recurringForDay.reduce(0) { $0 + $1.signedAmount }
            let dayNet = actualNet + recurringNet
            if offset > 0 {
                runningBalance += dayNet
            }
            return CashFlowCalendarDay(
                id: date,
                date: date,
                actuals: actuals,
                recurring: recurringForDay,
                bills: bills,
                netFlow: dayNet,
                projectedBalance: runningBalance
            )
        }
    }

    var body: some View {
        ZStack {
            AnimatedCanopyBackground()

            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Starting Liquid Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ForecastEngine.liquidBalance(from: accounts), format: .currency(code: "USD"))
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.nestBrown)
                        }
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.yolk)
                            .font(.title2)
                    }
                }
                .listRowBackground(Color.clear)

                ForEach(calendarDays) { day in
                    Section {
                        daySummary(day)
                        ForEach(day.actuals) { tx in
                            transactionLine(tx)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(day.recurring) { occurrence in
                            recurringLine(occurrence)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(day.bills) { account in
                            billLine(account)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .foregroundStyle(Color.twig)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Cash Flow Calendar")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func daySummary(_ day: CashFlowCalendarDay) -> some View {
        HStack {
            Label(day.netFlow >= 0 ? "Net Inflow" : "Net Outflow", systemImage: day.netFlow >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.caption)
                .foregroundStyle(day.netFlow >= 0 ? Color.eggBlue : .red)
            Spacer()
            Text(day.netFlow, format: .currency(code: "USD"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(day.netFlow >= 0 ? Color.eggBlue : .red)
            Text("Balance \(day.projectedBalance, format: .currency(code: "USD"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }

    private func transactionLine(_ transaction: Transaction) -> some View {
        line(
            icon: transaction.category?.icon ?? transaction.type.systemImage,
            title: transaction.title,
            subtitle: transaction.category?.name ?? "Actual transaction",
            amount: transaction.signedAmount,
            color: transaction.type == .income ? Color.eggBlue : .red
        )
    }

    private func recurringLine(_ occurrence: RecurringOccurrence) -> some View {
        line(
            icon: occurrence.category?.icon ?? occurrence.source.frequency.icon,
            title: occurrence.title,
            subtitle: "Upcoming recurring",
            amount: occurrence.signedAmount,
            color: occurrence.type == .income ? Color.eggBlue : .red
        )
    }

    private func billLine(_ account: Account) -> some View {
        line(
            icon: account.type.icon,
            title: account.name,
            subtitle: "Bill due, no cash impact until paid",
            amount: 0,
            color: Color.yolk
        )
    }

    private func line(icon: String, title: String, subtitle: String, amount: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if amount != 0 {
                Text(abs(amount), format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    NavigationStack {
        CashFlowCalendarView()
            .modelContainer(PersistenceController.previewContainer())
    }
}
