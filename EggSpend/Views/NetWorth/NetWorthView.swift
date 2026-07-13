import SwiftUI
import SwiftData
import Charts

struct NetWorthView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var snapshots: [BalanceSnapshot]
    @State private var showAddAccount = false
    @State private var showImport = false
    @State private var editingAccount: Account? = nil
    @State private var plannerAccount: Account? = nil
    @State private var accountToArchive: Account? = nil
    @State private var accountToDelete: Account? = nil

    private var assets: [Account] { accounts.filter { $0.isAsset && !$0.isArchived } }
    private var liabilities: [Account] { accounts.filter { !$0.isAsset && !$0.isArchived } }
    private var includedLiabilities: [Account] { liabilities.filter(\.includeInNetWorth) }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImport = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .foregroundStyle(Color.yolk)
                }
            }
            .sheet(isPresented: $showAddAccount) { AddAccountView() }
            .sheet(isPresented: $showImport) {
                CSVImportView(importType: .accounts)
            }
            .sheet(item: $editingAccount) { account in
                AddAccountView(editingAccount: account)
            }
            .navigationDestination(item: $plannerAccount) { account in
                DebtPayoffPlannerView(account: account)
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

                Chart {
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
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
                        Button { editingAccount = account } label: {
                            AccountRowView(account: account)
                        }
                        .buttonStyle(.plain)
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
                    ForEach(liabilities) { account in
                        Button { editingAccount = account } label: {
                            AccountRowView(account: account)
                        }
                        .buttonStyle(.plain)
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
                    AccountRowView(account: account)
                        .opacity(0.55)
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
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((account.isAsset ? Color.nestLeafGreen : Color.negative).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: account.type.icon)
                    .foregroundStyle(account.isAsset ? Color.nestLeafGreen : Color.negative)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                Text(account.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let dueDate = account.dueDate {
                    Text("Due \(dueDate, format: .dateTime.month(.abbreviated).day())")
                        .font(.caption2)
                        .foregroundStyle(Color.warningTone)
                }
                if account.isLiability && !account.includeInNetWorth {
                    Text("Excluded from net worth")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(abs(account.balance), format: .currency(code: CurrencyFormat.code))
                .font(NestType.amount)
                .foregroundStyle(account.isAsset ? Color.nestLeafGreen : Color.negative)
        }
        .padding(.vertical, Space.sm)
    }
}

#Preview {
    NetWorthView()
        .modelContainer(PersistenceController.previewContainer())
}
