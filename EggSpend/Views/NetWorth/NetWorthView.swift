import SwiftUI
import SwiftData
import Charts

struct NetWorthView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var snapshots: [BalanceSnapshot]
    @State private var showAddAccount = false
    @State private var editingAccount: Account? = nil
    @State private var plannerAccount: Account? = nil
    @State private var accountToArchive: Account? = nil
    @State private var accountToDelete: Account? = nil

    private var assets: [Account] { accounts.filter { $0.isAsset && !$0.isArchived } }
    private var liabilities: [Account] {
        accounts
            .filter { !$0.isAsset && !$0.isArchived }
            .sorted { lhs, rhs in
                switch (lhs.nextDueDate, rhs.nextDueDate) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }
    private var includedLiabilities: [Account] { liabilities.filter(\.includeInNetWorth) }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }
    // Charges from the most recently closed billing cycle, not a rolling 30-day
    // window: the month-long period ending one cycle before each card's next due
    // date (due dates roll monthly, so that's the cycle already reflected in what's owed).
    private var previousBillingCycleTotals: [UUID: Double] {
        let calendar = Calendar.current
        let cycleWindows: [UUID: (start: Date, end: Date)] = accounts.reduce(into: [:]) { result, account in
            guard account.type == .credit,
                  let upcomingDue = account.nextDueDate,
                  let cycleEnd = calendar.date(byAdding: .month, value: -1, to: upcomingDue),
                  let cycleStart = calendar.date(byAdding: .month, value: -1, to: cycleEnd)
            else { return }
            result[account.id] = (cycleStart, cycleEnd)
        }

        // Seed every card with a computable cycle at $0 so cards with no charges
        // that cycle still show "$0.00" instead of disappearing from the row.
        var totals = cycleWindows.mapValues { _ in 0.0 }
        for transaction in transactions {
            guard transaction.type == .expense,
                  !transaction.isAdjustment,
                  let account = transaction.account,
                  account.type == .credit,
                  let window = cycleWindows[account.id],
                  transaction.date > window.start,
                  transaction.date <= window.end
            else { continue }
            totals[account.id, default: 0] += transaction.amount
        }
        return totals
    }

    private var totalAssets: Double { NetWorthCalculator.totals(accounts: Array(accounts)).assets }
    private var totalLiabilities: Double { NetWorthCalculator.totals(accounts: Array(accounts)).liabilities }
    private var netWorth: Double { totalAssets - totalLiabilities }
    private var netWorthTimeline: [(date: Date, worth: Double)] {
        NetWorthCalculator.timeline(
            accounts: accounts,
            transactions: transactions,
            snapshots: snapshots,
            days: 30
        )
    }
    private var trendSundayMarks: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceSunday = weekday - 1
        guard let mostRecentSunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: today) else {
            return []
        }

        return (0..<4).compactMap { offset in
            calendar.date(byAdding: .day, value: -(offset * 7), to: mostRecentSunday)
        }
        .sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NestBackground()

                List {
                    summarySection
                    sparklineSection
                    assetsSection
                    liabilitiesSection
                    archivedSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Nest Egg")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.yolk)
                    }
                }
            }
            .sheet(isPresented: $showAddAccount) { AddAccountView() }
            .sheet(item: $editingAccount) { account in
                AddAccountView(editingAccount: account)
            }
            .navigationDestination(item: $plannerAccount) { account in
                DebtPayoffPlannerView(account: account)
            }
            .onAppear(perform: rollLiabilityDueDates)
            .onChange(of: accounts.map(\.dueDate)) { _, _ in
                rollLiabilityDueDates()
            }
            .confirmationDialog(
                "Archive Account",
                isPresented: Binding(
                    get: { accountToArchive != nil },
                    set: { isPresented in if !isPresented { accountToArchive = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Archive") {
                    accountToArchive?.isArchived = true
                    accountToArchive = nil
                }
                Button("Cancel", role: .cancel) { accountToArchive = nil }
            } message: {
                if let name = accountToArchive?.name {
                    Text("\"\(name)\" will be hidden from pickers, net worth, and forecasts. Its transaction history is kept, and you can unarchive it anytime from the Archived section.")
                }
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: Binding(
                    get: { accountToDelete != nil },
                    set: { isPresented in if !isPresented { accountToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let account = accountToDelete {
                        modelContext.delete(account)
                        accountToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { accountToDelete = nil }
            } message: {
                if let name = accountToDelete?.name {
                    Text("Permanently delete \"\(name)\"? This cannot be undone. Its transactions keep their history but lose the account link.")
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    private var summarySection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Net worth")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(netWorth, format: .currency(code: CurrencyFormat.code))
                        .font(NestType.hero)
                        .foregroundStyle(netWorth >= 0 ? Color.primary : Color.negative)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalAssets, format: .currency(code: CurrencyFormat.code))
                            .font(.headline)
                            .foregroundStyle(Color.nestLeafGreen)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Liabilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalLiabilities, format: .currency(code: CurrencyFormat.code))
                            .font(.headline)
                            .foregroundStyle(Color.negative)
                    }
                }
            }
            .padding(.vertical, Space.sm)
        }
    }

    private var sparklineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Label("30-day trend", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nestBrown)
                    Spacer()
                    if let first = netWorthTimeline.first, let last = netWorthTimeline.last {
                        let change = last.worth - first.worth
                        Label(
                            CurrencyFormat.money(abs(change)),
                            systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change >= 0 ? Color.nestLeafGreen : Color.negative)
                    }
                }

                let yDomain = ChartYAxisDomain.range(for: netWorthTimeline.map(\.worth))
                Chart {
                    // Gradient area fill, matching the Metrics tab's net worth chart.
                    ForEach(netWorthTimeline, id: \.date) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Base", yDomain.lowerBound),
                            yEnd: .value("Net worth", point.worth)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.eggBlue.opacity(0.28), Color.eggBlue.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .accessibilityHidden(true)
                    }
                    ForEach(netWorthTimeline, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Net worth", point.worth)
                        )
                        .foregroundStyle(Color.eggBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                        .accessibilityLabel(point.date.formatted(.dateTime.month(.abbreviated).day()))
                        .accessibilityValue(CurrencyFormat.money(point.worth))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis(.hidden)
                // Plot padding keeps the line and the outermost axis labels off the
                // card's edges — without it the trailing date label (e.g. "Jul 12")
                // gets clipped to "J…" by the chart's own frame.
                .chartXScale(range: .plotDimension(padding: 16))
                .chartXAxis {
                    AxisMarks(values: trendSundayMarks) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .frame(height: 96)
            }
            .padding(.vertical, Space.sm)
        }
        .listRowBackground(Color.clear)
    }

    private var assetsSection: some View {
        Section("Assets") {
            Group {
                if assets.isEmpty {
                    Text("No assets added yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assets) { account in
                        NavigationLink {
                            TransactionsListView(
                                initialFilter: transactionFilter(for: account),
                                hideTransfers: false,
                                showUpcoming: false
                            )
                        } label: {
                            AccountRowView(account: account, previousCycleTotal: nil)
                        }
                        .listRowInsets(compactAccountRowInsets)
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") {
                                editingAccount = account
                            }
                            .tint(Color.yolk)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Archive", systemImage: "archivebox") {
                                accountToArchive = account
                            }
                            .tint(Color.twig)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    private var liabilitiesSection: some View {
        Section("Liabilities") {
            Group {
                if liabilities.isEmpty {
                    Text("No liabilities added yet")
                        .foregroundStyle(.secondary)
                } else {
                    let previousCycleTotals = previousBillingCycleTotals
                    ForEach(liabilities) { account in
                        NavigationLink {
                            TransactionsListView(
                                initialFilter: transactionFilter(for: account),
                                hideTransfers: false,
                                showUpcoming: false
                            )
                        } label: {
                            AccountRowView(
                                account: account,
                                previousCycleTotal: account.type == .credit ? previousCycleTotals[account.id] : nil
                            )
                        }
                        .listRowInsets(compactAccountRowInsets)
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") {
                                editingAccount = account
                            }
                            .tint(Color.yolk)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Payoff planner", systemImage: "calendar.badge.clock") {
                                plannerAccount = account
                            }
                            .tint(Color.eggBlue)
                            Button("Archive", systemImage: "archivebox") {
                                accountToArchive = account
                            }
                            .tint(Color.twig)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !archivedAccounts.isEmpty {
            Section("Archived") {
                ForEach(archivedAccounts) { account in
                    AccountRowView(account: account, previousCycleTotal: nil)
                        .opacity(0.55)
                        .listRowInsets(compactAccountRowInsets)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Unarchive", systemImage: "arrow.uturn.backward") {
                                account.isArchived = false
                            }
                            .tint(Color.yolk)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                accountToDelete = account
                            }
                        }
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    @Environment(\.modelContext) private var modelContext

    private var compactAccountRowInsets: EdgeInsets {
        EdgeInsets(top: 2, leading: Space.md, bottom: 2, trailing: Space.md)
    }

    private func rollLiabilityDueDates() {
        for account in accounts where account.isLiability {
            account.rollDueDateIfNeeded()
        }
    }

    private func transactionFilter(for account: Account) -> TransactionFilter {
        TransactionFilter(accountIDs: [account.id])
    }
}

private struct AccountRowView: View {
    let account: Account
    let previousCycleTotal: Double?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill((account.isAsset ? Color.nestLeafGreen : Color.negative).opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: account.type.icon)
                    .font(.caption)
                    .foregroundStyle(account.isAsset ? Color.nestLeafGreen : Color.negative)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: Space.xs) {
                    Text(account.type.rawValue)
                    if let dueDate = account.dueDate {
                        Text("Due \(dueDate, format: .dateTime.month(.abbreviated).day())")
                            .foregroundStyle(Color.warningTone)
                    }
                    if let previousCycleTotal {
                        Text(previousCycleTotal, format: .currency(code: CurrencyFormat.code))
                            .foregroundStyle(Color.negative)
                    }
                    if account.isLiability && !account.includeInNetWorth {
                        Text("Excluded")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(abs(account.balance), format: .currency(code: CurrencyFormat.code))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(account.isAsset ? Color.nestLeafGreen : Color.negative)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NetWorthView()
        .modelContainer(PersistenceController.previewContainer())
}
