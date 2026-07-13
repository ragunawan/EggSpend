import SwiftUI
import SwiftData
import Charts

enum CompactCurrencyAxisFormatter {
    // Symbol-prefix layout ("$1.2K") and English K suffixes are accepted v1
    // imprecision for locales that place the symbol after the number — this is
    // a compact chart axis label, not a currency-accurate display.
    static func string(from value: Double, currencySymbol: String = "$") -> String {
        guard value.isFinite else { return "\(currencySymbol)0" }

        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000 {
            return "\(sign)\(currencySymbol)\(compactNumber(magnitude / 1_000))K"
        }

        return "\(sign)\(currencySymbol)\(compactNumber(magnitude))"
    }

    private static func compactNumber(_ value: Double) -> String {
        let integerDigits = max(1, Int(floor(log10(max(abs(value), 1)))) + 1)
        let fractionDigits = max(0, 4 - integerDigits)
        let formatted = String(format: "%.\(fractionDigits)f", value)
        if formatted.contains(".") {
            return formatted
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return formatted
    }
}

enum ChartYAxisDomain {
    static func range(for values: [Double], fallback: ClosedRange<Double> = 0...1) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minValue = finiteValues.min(), let maxValue = finiteValues.max() else {
            return fallback
        }

        let dataRange = maxValue - minValue
        var lowerBound = minValue - dataRange * 0.2
        var upperBound = maxValue + dataRange * 0.2

        if lowerBound == upperBound {
            let padding = max(abs(minValue) * 0.2, 1)
            lowerBound -= padding
            upperBound += padding
        }

        return lowerBound...upperBound
    }
}

struct MetricsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var snapshots: [BalanceSnapshot]

    @State private var selectedPeriod: Period = .month
    @State private var selectedNetWorthDate: Date? = nil
    @State private var selectedCashFlowDate: Date? = nil
    @State private var showAddTransaction = false
    // MARK: - Period

    enum Period: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"

        var bucketUnit: Calendar.Component {
            switch self {
            case .week:  return .day
            case .month: return .weekOfYear
            case .year:  return .month
            }
        }
        var dateStart: Date {
            let cal = Calendar.current
            let now = Date.now
            switch self {
            case .week:  return cal.date(byAdding: .day,   value: -7,  to: now) ?? now
            case .month: return cal.date(byAdding: .month, value: -1,  to: now) ?? now
            case .year:  return cal.date(byAdding: .year,  value: -1,  to: now) ?? now
            }
        }
        var timelineDays: Int {
            switch self {
            case .week: return 8
            case .month: return 31
            case .year: return 366
            }
        }

        var dateInterval: DateInterval {
            let start = dateStart
            return DateInterval(start: start, end: .now)
        }

        var xAxisDates: [Date] {
            let cal = Calendar.current
            let interval = dateInterval
            let start: Date

            switch self {
            case .week:
                start = cal.startOfDay(for: interval.start)
            case .month:
                start = cal.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
            case .year:
                start = cal.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
            }

            var dates: [Date] = []
            var cursor = start
            while cursor <= interval.end {
                dates.append(cursor)
                guard let next = cal.date(byAdding: bucketUnit, value: 1, to: cursor), next > cursor else {
                    break
                }
                cursor = next
            }

            return dates
        }

        var xAxisDomain: ClosedRange<Date> {
            let interval = dateInterval
            return (xAxisDates.first ?? interval.start)...interval.end
        }

        func bucketStart(for date: Date) -> Date {
            let cal = Calendar.current
            switch self {
            case .week:
                return cal.startOfDay(for: date)
            case .month:
                return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            case .year:
                return cal.dateInterval(of: .month, for: date)?.start ?? date
            }
        }
    }

    // MARK: - Derived data

    private var filtered: [Transaction] {
        transactions.filter { $0.date >= selectedPeriod.dateStart }
    }

    private var totalIncome:   Double { filtered.filter { $0.type == .income  && !$0.isAdjustment }.reduce(0) { $0 + $1.amount } }
    private var totalExpenses: Double { filtered.filter { $0.type == .expense && !$0.isAdjustment }.reduce(0) { $0 + $1.amount } }

    private var expensesByCategory: [CategorySpending] {
        var dict: [UUID: CategorySpending] = [:]
        var uncategorized: CategorySpending?

        for tx in filtered where tx.type == .expense && !tx.isAdjustment {
            if let category = tx.category {
                let existing = dict[category.id] ?? CategorySpending(
                    id: category.id,
                    name: category.name,
                    amount: 0,
                    icon: category.icon
                )
                dict[category.id] = CategorySpending(
                    id: existing.id,
                    name: existing.name,
                    amount: existing.amount + tx.amount,
                    icon: existing.icon
                )
            } else {
                let existing = uncategorized ?? CategorySpending(
                    id: nil,
                    name: "Uncategorized",
                    amount: 0,
                    icon: "questionmark.circle"
                )
                uncategorized = CategorySpending(
                    id: nil,
                    name: existing.name,
                    amount: existing.amount + tx.amount,
                    icon: existing.icon
                )
            }
        }

        return (Array(dict.values) + Array([uncategorized].compactMap { $0 }))
            .sorted { $0.amount > $1.amount }
    }

    private var netWorthTimeline: [(date: Date, worth: Double)] {
        NetWorthCalculator.timeline(
            accounts: accounts,
            transactions: transactions,
            snapshots: snapshots,
            days: selectedPeriod.timelineDays
        )
    }

    // Cash flow: income and expenses bucketed over the selected period
    private var cashFlowData: [(date: Date, income: Double, expenses: Double)] {
        var dict = Dictionary(uniqueKeysWithValues: selectedPeriod.xAxisDates.map { ($0, (0.0, 0.0)) })
        for tx in filtered where !tx.isAdjustment {
            let key = selectedPeriod.bucketStart(for: tx.date)
            var pair = dict[key] ?? (0, 0)
            if tx.type == .income  { pair.0 += tx.amount }
            else                   { pair.1 += tx.amount }
            dict[key] = pair
        }
        return dict.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.0 < $1.0 }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                NestBackground()

                List {
                    if accounts.isEmpty && transactions.isEmpty {
                        noDataSection
                    } else {
                        timelineSection
                        if !expensesByCategory.isEmpty { categoryBreakdownSection }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .safeAreaInset(edge: .bottom) {
                    periodPickerNav
                }
            }
            .navigationTitle("Metrics")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView()
            }
        }
    }

    // MARK: - Empty state

    private var noDataSection: some View {
        Section {
            EmptyStateView(
                title: "No Data Yet",
                icon: "chart.bar.xaxis",
                description: "Add your first transaction or account to see your metrics take shape.",
                action: ("Add Transaction", { showAddTransaction = true }),
                context: .listRow
            )
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Period picker

    private var periodPickerNav: some View {
        VStack(spacing: 0) {
            Divider()
            Picker("Period", selection: $selectedPeriod.animation(.quickFade)) {
                ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .tint(Color.yolk)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(.regularMaterial)
        }
    }

    // MARK: - Charts

    private var timelineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                netWorthChart
                Divider()
                cashFlowChart
                cashFlowSummaryStats
            }
            .padding(.vertical, Space.xs)
        }
        .listRowBackground(Color.clear)
    }

    // Net worth area + line chart with tap-to-inspect
    private var netWorthChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nest Egg Over Time")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.nestBrown)

            let data = netWorthTimeline
            let yDomain = ChartYAxisDomain.range(for: data.map(\.worth))

            Chart {
                // Gradient area fill
                ForEach(data, id: \.date) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", yDomain.lowerBound),
                        yEnd:   .value("Worth", point.worth)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.eggBlue.opacity(0.35), Color.eggBlue.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    // Purely decorative fill under the line — the LineMark below carries the data.
                    .accessibilityHidden(true)
                }
                // Line on top
                ForEach(data, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Worth", point.worth)
                    )
                    .foregroundStyle(Color.eggBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                    .accessibilityLabel(point.date.formatted(calloutDateFormat))
                    .accessibilityValue(CurrencyFormat.money(point.worth))
                }
                // Interactive selection rule
                if let sel = selectedNetWorthDate,
                   let closest = data.min(by: {
                       abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
                   }) {
                    RuleMark(x: .value("Selected", closest.date))
                        .foregroundStyle(Color.nestBrown.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .annotation(position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            netWorthCallout(date: closest.date, worth: closest.worth)
                        }
                        // Selection state is already exposed via the LineMark's own
                        // label/value; hide this redundant highlight from VoiceOver.
                        .accessibilityHidden(true)
                    PointMark(
                        x: .value("Selected", closest.date),
                        y: .value("Worth", closest.worth)
                    )
                    .foregroundStyle(Color.eggBlue)
                    .symbolSize(64)
                    .accessibilityHidden(true)
                }
            }
            .chartXSelection(value: $selectedNetWorthDate)
            .chartXScale(domain: selectedPeriod.xAxisDomain)
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let worth = value.as(Double.self) {
                            Text(CompactCurrencyAxisFormatter.string(from: worth, currencySymbol: CurrencyFormat.symbol))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: selectedPeriod.xAxisDates) { value in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat, centered: true)
                }
            }
            .frame(height: 150)

            // Summary row
            if let first = data.first, let last = data.last {
                let change = last.worth - first.worth
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current").font(.caption).foregroundStyle(.secondary)
                        Text(last.worth, format: .currency(code: CurrencyFormat.code))
                            .font(NestType.amount)
                            .foregroundStyle(Color.nestBrown)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Change").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text(abs(change), format: .currency(code: CurrencyFormat.code))
                                .font(NestType.amount)
                        }
                        .foregroundStyle(change >= 0 ? Color.nestLeafGreen : Color.negative)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func netWorthCallout(date: Date, worth: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: calloutDateFormat)
                .font(.caption2).foregroundStyle(.secondary)
            Text(worth, format: .currency(code: CurrencyFormat.code))
                .font(.caption).fontWeight(.semibold).foregroundStyle(Color.nestBrown)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
        .shadow(color: Color.nestBrown.opacity(0.08), radius: 4, y: 2)
    }

    // Cash flow bar chart (income positive, expenses negative from zero line)
    private var cashFlowChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Income & Expenses")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.nestBrown)

            let data = cashFlowData
            let yValues = data.flatMap { [0.0, $0.income, -$0.expenses] }
            let yDomain = ChartYAxisDomain.range(for: yValues)

            Chart {
                ForEach(data, id: \.date) { point in
                    BarMark(
                        x: .value("Period", point.date, unit: selectedPeriod.bucketUnit),
                        y: .value("Income", point.income)
                    )
                    .foregroundStyle(Color.nestLeafGreen.gradient)
                    .position(by: .value("Series", "Income"))
                    .cornerRadius(Radius.control)
                    .accessibilityLabel("\(point.date.formatted(calloutDateFormat)) income")
                    .accessibilityValue(CurrencyFormat.money(point.income))

                    BarMark(
                        x: .value("Period", point.date, unit: selectedPeriod.bucketUnit),
                        y: .value("Expenses", -point.expenses)
                    )
                    .foregroundStyle(Color.negative.opacity(0.8).gradient)
                    .position(by: .value("Series", "Expenses"))
                    .cornerRadius(Radius.control)
                    .accessibilityLabel("\(point.date.formatted(calloutDateFormat)) expenses")
                    .accessibilityValue(CurrencyFormat.money(point.expenses))
                }

                // Zero rule line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.twig.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)

                // Selection rule
                if let sel = selectedCashFlowDate,
                   let closest = data.min(by: {
                       abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
                   }) {
                    RuleMark(x: .value("Selected", closest.date))
                        .foregroundStyle(Color.nestBrown.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .annotation(position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            cashFlowCallout(date: closest.date,
                                            income: closest.income,
                                            expenses: closest.expenses)
                        }
                        // Selection state is already exposed via the BarMarks' own
                        // labels/values; hide this redundant highlight from VoiceOver.
                        .accessibilityHidden(true)
                }
            }
            .chartXSelection(value: $selectedCashFlowDate)
            .chartXScale(domain: selectedPeriod.xAxisDomain)
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(CompactCurrencyAxisFormatter.string(from: abs(v), currencySymbol: CurrencyFormat.symbol))
                                .font(.caption2)
                                .foregroundStyle(v >= 0 ? Color.nestLeafGreen : Color.negative)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: selectedPeriod.xAxisDates) { value in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat, centered: true)
                }
            }
            .chartLegend(position: .topTrailing, spacing: 8) {
                HStack(spacing: 12) {
                    Label("Income",   systemImage: "square.fill").foregroundStyle(Color.nestLeafGreen)
                    Label("Expenses", systemImage: "square.fill").foregroundStyle(Color.negative)
                }
                .font(.caption)
            }
            .frame(height: 140)
        }
    }

    private func cashFlowCallout(date: Date, income: Double, expenses: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: calloutDateFormat)
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(income.formatted(.currency(code: CurrencyFormat.code).precision(.fractionLength(0))),
                      systemImage: "arrow.down.circle.fill")
                    .font(.caption).foregroundStyle(Color.nestLeafGreen)
                Label(expenses.formatted(.currency(code: CurrencyFormat.code).precision(.fractionLength(0))),
                      systemImage: "arrow.up.circle.fill")
                    .font(.caption).foregroundStyle(Color.negative)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
        .shadow(color: Color.nestBrown.opacity(0.08), radius: 4, y: 2)
    }

    private var cashFlowSummaryStats: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Net")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalIncome - totalExpenses, format: .currency(code: CurrencyFormat.code))
                    .font(.headline)
                    .foregroundStyle(totalIncome >= totalExpenses ? Color.nestLeafGreen : Color.negative)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Savings Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if totalIncome > 0 {
                    Text("\(Int((1 - totalExpenses / totalIncome) * 100))%")
                        .font(.headline)
                        .foregroundStyle(Color.nestBrown)
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, Space.xs)
    }

    // MARK: - Axis format helpers

    private var xAxisFormat: Date.FormatStyle {
        switch selectedPeriod {
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).day()
        case .year:  return .dateTime.month(.abbreviated)
        }
    }

    private var calloutDateFormat: Date.FormatStyle {
        switch selectedPeriod {
        case .week:  return .dateTime.weekday(.wide).month(.abbreviated).day()
        case .month: return .dateTime.month(.wide).day()
        case .year:  return .dateTime.month(.wide).year()
        }
    }

    // MARK: - Category breakdown

    private var categoryBreakdownSection: some View {
        Section("Spending by Category") {
            Group {
                Chart(expensesByCategory.prefix(6)) { category in
                    SectorMark(angle: .value("Amount", category.amount),
                               innerRadius: .ratio(0.55),
                               angularInset: 2)
                        .foregroundStyle(by: .value("Category", category.name))
                        .cornerRadius(Radius.control)
                        .accessibilityLabel(category.name)
                        .accessibilityValue(
                            totalExpenses > 0
                                ? "\(CurrencyFormat.money(category.amount)), \(Int(category.amount / totalExpenses * 100))%"
                                : CurrencyFormat.money(category.amount)
                        )
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: Space.xs)
                .frame(height: 150)
                .padding(.vertical, Space.xs)

                ForEach(expensesByCategory.prefix(6)) { category in
                    NavigationLink {
                        TransactionsListView(
                            initialFilter: transactionFilter(for: category),
                            hideTransfers: true,
                            showUpcoming: false
                        )
                    } label: {
                        HStack {
                            Image(systemName: category.icon).frame(width: 24).foregroundStyle(.secondary)
                            Text(category.name)
                            Spacer()
                            Text(category.amount, format: .currency(code: CurrencyFormat.code)).foregroundStyle(.secondary)
                            if totalExpenses > 0 {
                                Text("(\(Int(category.amount / totalExpenses * 100))%)")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

        }
        .listRowBackground(Color.clear)
    }

    private func transactionFilter(for category: CategorySpending) -> TransactionFilter {
        TransactionFilter(
            type: .expense,
            categoryIDs: category.id.map { Set([$0]) } ?? [],
            uncategorizedOnly: category.id == nil,
            startDate: selectedPeriod.dateInterval.start,
            endDate: selectedPeriod.dateInterval.end
        )
    }
}

private struct CategorySpending: Identifiable {
    let id: UUID?
    let name: String
    let amount: Double
    let icon: String
}

#Preview {
    MetricsView()
        .modelContainer(PersistenceController.previewContainer())
}
