import SwiftUI
import SwiftData
import Charts

struct CashFlowForecastView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurring: [RecurringTransaction]

    @State private var horizon: ForecastHorizon = .days30
    @State private var selectedDate: Date? = nil
    @State private var showAssumptions = false
    @State private var showAddAccount = false
    // See MetricsView.emptyStateHeight — a single concrete `.frame(height:)`
    // is what actually constrains `ContentUnavailableView` inside a List
    // row; `@ScaledMetric` keeps that fixed height growing with Dynamic Type
    // instead of clipping the CTA button at larger accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var emptyStateHeight: CGFloat = 340

    // MARK: - Horizon

    enum ForecastHorizon: Int, CaseIterable, Identifiable {
        case days30 = 30
        case days60 = 60
        case days90 = 90

        var id: Int { rawValue }
        var label: String { "\(rawValue)d" }
    }

    // MARK: - Derived Data

    private struct ForecastSnapshot {
        let points: [ForecastDataPoint]
        let events: [ForecastEvent]
        let inflows: [ForecastEvent]
        let outflows: [ForecastEvent]
        let startBalance: Double
        let endBalance: Double
        let balanceDelta: Double
        let lowestBalance: Double
        let liquidBalance: Double
        let totalScheduledInflows: Double
        let totalScheduledOutflows: Double
        let eventPointBalances: [UUID: ForecastDataPoint]
    }

    private func makeForecastSnapshot() -> ForecastSnapshot {
        let accountList = Array(accounts)
        let result = ForecastEngine.buildForecast(
            accounts: accountList,
            transactions: Array(transactions),
            recurring: Array(recurring),
            horizonDays: horizon.rawValue
        )
        let points = result.points
        let events = result.events
        let inflows = events.filter { $0.amount > 0 }
        let outflows = events.filter { $0.amount < 0 }
        let startBalance = points.first?.balance ?? 0
        let endBalance = points.last?.balance ?? 0
        let lowestBalance = points.lazy.map(\.balance).min() ?? 0
        let calendar = Calendar.current
        let pointsByDay = Dictionary(uniqueKeysWithValues: points.map { (calendar.startOfDay(for: $0.date), $0) })
        let eventPointBalances = Dictionary(uniqueKeysWithValues: events.prefix(30).compactMap { event in
            pointsByDay[calendar.startOfDay(for: event.date)].map { (event.id, $0) }
        })

        return ForecastSnapshot(
            points: points,
            events: events,
            inflows: inflows,
            outflows: outflows,
            startBalance: startBalance,
            endBalance: endBalance,
            balanceDelta: endBalance - startBalance,
            lowestBalance: lowestBalance,
            liquidBalance: ForecastEngine.liquidBalance(from: accountList),
            totalScheduledInflows: inflows.reduce(0) { $0 + $1.amount },
            totalScheduledOutflows: outflows.reduce(0) { $0 + abs($1.amount) },
            eventPointBalances: eventPointBalances
        )
    }

    // MARK: - Body

    var body: some View {
        let snapshot = makeForecastSnapshot()

        ZStack {
            NestBackground()

            List {
                periodPickerSection
                if accounts.isEmpty {
                    noAccountsSection
                } else {
                    balanceChartSection(snapshot)
                    summaryStatsSection(snapshot)
                    if !snapshot.inflows.isEmpty { inflowsSection(snapshot.inflows) }
                    if !snapshot.outflows.isEmpty { outflowsSection(snapshot.outflows) }
                    assumptionsSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Cash Flow Forecast")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddAccount) {
            AddAccountView()
        }
    }

    // MARK: - Empty state

    private var noAccountsSection: some View {
        Section {
            ContentUnavailableView {
                Label {
                    Text("No Accounts Yet")
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis").symbolEffect(.pulse)
                }
            } description: {
                Text("The forecast needs at least one account to project your balance.")
            } actions: {
                Button { showAddAccount = true } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).tint(Color.nestBrown)
            }
            // See MetricsView.noDataSection — fixes row height so the
            // action button doesn't stretch to fill the scroll view, using
            // `emptyStateHeight` so it still grows with Dynamic Type.
            .frame(height: emptyStateHeight)
            // Cap Dynamic Type growth beyond AX3 — the fixed `emptyStateHeight`
            // budget above was sized/settled for that ceiling (loop 26); letting
            // text keep scaling past it would clip the CTA button again.
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Period Picker

    private var periodPickerSection: some View {
        Section {
            Picker("Horizon", selection: $horizon) {
                ForEach(ForecastHorizon.allCases) { h in
                    Text(h.label).tag(h)
                }
            }
            .pickerStyle(.segmented)
            .tint(Color.yolk)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Balance Chart

    private func balanceChartAccessibilityValue(_ snapshot: ForecastSnapshot) -> String {
        let base = "Today \(CurrencyFormat.money(snapshot.startBalance)), ending \(CurrencyFormat.money(snapshot.endBalance)), lowest \(CurrencyFormat.money(snapshot.lowestBalance))"
        return snapshot.lowestBalance < 0 ? base + ", goes negative" : base
    }

    private func balanceChartSection(_ snapshot: ForecastSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Projected Balance")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.nestBrown)
                    Spacer()
                    if snapshot.lowestBalance < 0 {
                        Label("Goes negative", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(Color.negative)
                    }
                }

                let pts = snapshot.points
                let minBal = pts.map(\.balance).min() ?? 0
                let maxBal = pts.map(\.balance).max() ?? 1
                let yPad  = max((maxBal - minBal) * 0.12, 100)
                let yDomain = (minBal - yPad)...(maxBal + yPad)
                let chartColor = chartColor(for: snapshot.balanceDelta)

                Chart {
                    ForEach(pts, id: \.date) { p in
                        AreaMark(
                            x: .value("Date", p.date),
                            yStart: .value("Base", minBal - yPad),
                            yEnd:   .value("Balance", p.balance)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [chartColor.opacity(0.30), chartColor.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(pts, id: \.date) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value("Balance", p.balance)
                        )
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    }

                    // Zero line — visually marks where balance would go negative
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.negative.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Event dots (capped to keep chart readable)
                    ForEach(snapshot.events.prefix(30), id: \.id) { ev in
                        if let match = snapshot.eventPointBalances[ev.id] {
                            PointMark(
                                x: .value("Date", match.date),
                                y: .value("Balance", match.balance)
                            )
                            .foregroundStyle(ev.amount > 0 ? Color.nestLeafGreen : Color.yolk)
                            .symbolSize(28)
                        }
                    }

                    // Interactive selection rule
                    if let sel = selectedDate,
                       let closest = pts.min(by: {
                           abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
                       }) {
                        RuleMark(x: .value("Selected", closest.date))
                            .foregroundStyle(Color.nestBrown.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                balanceCallout(date: closest.date, balance: closest.balance)
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let balance = value.as(Double.self) {
                                Text(CompactCurrencyAxisFormatter.string(from: balance, currencySymbol: CurrencyFormat.symbol))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisMarks(for: pts, horizonDays: horizon.rawValue)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .frame(height: 220)
                // Summarize the projection as one stop rather than exposing every
                // daily point/event dot individually.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Projected balance")
                .accessibilityValue(balanceChartAccessibilityValue(snapshot))

                // Summary row
                HStack {
                    labeledAmount(label: "Today", value: snapshot.startBalance, alignment: .leading)
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("\(horizon.rawValue)-day change").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: snapshot.balanceDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text(abs(snapshot.balanceDelta), format: .currency(code: CurrencyFormat.code))
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(snapshot.balanceDelta >= 0 ? Color.nestLeafGreen : Color.negative)
                    }
                    Spacer()
                    labeledAmount(label: "Day \(horizon.rawValue)", value: snapshot.endBalance, alignment: .trailing)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        } header: {
            Label("Balance Projection", systemImage: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.twig)
        }
        .listRowBackground(Color.clear)
    }

    private func chartColor(for balanceDelta: Double) -> Color {
        balanceDelta >= 0 ? Color.eggBlue : Color.yolk
    }

    private func balanceCallout(date: Date, balance: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(Color.primary.opacity(0.72))
            Text(balance, format: .currency(code: CurrencyFormat.code))
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(balance >= 0 ? Color.primary : Color.negative)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            Color(lightHex: "FFFFFF", darkHex: "1E1A16"),
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func labeledAmount(label: String, value: Double, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: CurrencyFormat.code))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(value >= 0 ? Color.nestBrown : Color.negative)
        }
    }

    // MARK: - Summary Stats

    private func summaryStatsSection(_ snapshot: ForecastSnapshot) -> some View {
        Section {
            HStack(spacing: 10) {
                statChip(
                    title: "Liquid Base",
                    value: snapshot.liquidBalance,
                    color: Color.eggBlue,
                    icon: "banknote.fill"
                )
                statChip(
                    title: "Sched. In",
                    value: snapshot.totalScheduledInflows,
                    color: Color.nestLeafGreen,
                    icon: "arrow.down.circle.fill"
                )
                statChip(
                    title: "Sched. Out",
                    value: snapshot.totalScheduledOutflows,
                    color: Color.negative,
                    icon: "arrow.up.circle.fill"
                )
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func statChip(title: String, value: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(color)
            Text(value, format: .currency(code: CurrencyFormat.code))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .nestCard()
    }

    // MARK: - Inflows / Outflows

    private func inflowsSection(_ inflows: [ForecastEvent]) -> some View {
        Section {
            ForEach(inflows.prefix(12)) { ev in eventRow(ev) }
            if inflows.count > 12 {
                Text("+ \(inflows.count - 12) more")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Label("Scheduled Inflows", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.nestLeafGreen)
        }
    }

    private func outflowsSection(_ outflows: [ForecastEvent]) -> some View {
        Section {
            ForEach(outflows.prefix(12)) { ev in eventRow(ev) }
            if outflows.count > 12 {
                Text("+ \(outflows.count - 12) more")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Label("Scheduled Outflows", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(Color.negative)
        }
    }

    @ViewBuilder
    private func eventRow(_ event: ForecastEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((event.amount > 0 ? Color.nestLeafGreen : Color.yolk).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: event.categoryIcon)
                    .font(.caption)
                    .foregroundStyle(event.amount > 0 ? Color.nestLeafGreen : Color.yolk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline).foregroundStyle(.primary)
                Text(event.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(abs(event.amount), format: .currency(code: CurrencyFormat.code))
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(event.amount > 0 ? Color.nestLeafGreen : .primary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Color.nestBrown.opacity(0.06), radius: 4, y: 2)
        .padding(.vertical, 1)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Assumptions

    private var assumptionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAssumptions) {
                VStack(alignment: .leading, spacing: 10) {
                    assumptionRow("banknote.fill",
                        "Starting balance uses checking & savings accounts only. Investments, credit cards, and loans are excluded.")
                    assumptionRow("arrow.clockwise",
                        "Active recurring transactions are projected forward from their next due date at their scheduled frequency.")
                    assumptionRow("chart.line.flattrend.xyaxis",
                        "A daily baseline is derived from the last 60 days of transaction history, excluding auto-generated recurring transactions. Recurring bills and income are counted once, via the scheduled events above — so the forecast is a planning estimate, not an accounting balance.")
                    assumptionRow("exclamationmark.triangle",
                        "No interest, taxes, investment returns, or variable expenses beyond recent patterns are modeled.")
                    assumptionRow("calendar.badge.clock",
                        "Paused and expired recurring transactions are not projected.")
                }
                .padding(.vertical, 6)
            } label: {
                Label("Forecast Assumptions", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(Color.twig)
            }
            .tint(Color.yolk)
        }
        .listRowBackground(Color.clear)
    }

    private func assumptionRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.twig)
                .frame(width: 18)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Axis Marks

    private func xAxisMarks(for points: [ForecastDataPoint], horizonDays: Int) -> [Date] {
        guard let firstDate = points.first?.date else { return [] }
        let calendar = Calendar.current
        let strideDays: Int
        switch horizonDays {
        case ...30:
            strideDays = 7
        case ...60:
            strideDays = 14
        default:
            strideDays = 30
        }

        return stride(from: strideDays, through: horizonDays, by: strideDays).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: firstDate)
        }
    }
}

#Preview {
    NavigationStack {
        CashFlowForecastView()
            .modelContainer(PersistenceController.previewContainer())
    }
}
