import SwiftUI
import SwiftData
import Charts

struct NetWorthView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showAddAccount = false
    @State private var showImport = false
    @State private var editingAccount: Account? = nil
    @State private var accountToArchive: Account? = nil
    @State private var accountToDelete: Account? = nil

    private var assets: [Account] { accounts.filter { $0.isAsset && !$0.isArchived } }
    private var liabilities: [Account] { accounts.filter { !$0.isAsset && !$0.isArchived } }
    private var includedLiabilities: [Account] { liabilities.filter(\.includeInNetWorth) }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    private var totalAssets: Double { NetWorthCalculator.totals(accounts: Array(accounts)).assets }
    private var totalLiabilities: Double { NetWorthCalculator.totals(accounts: Array(accounts)).liabilities }
    private var netWorth: Double { totalAssets - totalLiabilities }

    var body: some View {
        NavigationStack {
            ZStack {
                NestBackground()

                List {
                    summarySection
                    chartSection
                    assetsSection
                    liabilitiesSection
                    archivedSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Net Worth")
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
                    Text("Net Worth")
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

    private var chartSection: some View {
        Section {
            Chart {
                BarMark(
                    x: .value("Type", "Assets"),
                    y: .value("Amount", totalAssets)
                )
                .foregroundStyle(Color.nestLeafGreen)
                .accessibilityLabel("Assets")
                .accessibilityValue(CurrencyFormat.money(totalAssets))

                BarMark(
                    x: .value("Type", "Liabilities"),
                    y: .value("Amount", totalLiabilities)
                )
                .foregroundStyle(Color.negative)
                .accessibilityLabel("Liabilities")
                .accessibilityValue(CurrencyFormat.money(totalLiabilities))
            }
            .frame(height: 180)
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
                        HStack(spacing: 8) {
                            NavigationLink(destination: DebtPayoffPlannerView(account: account)) {
                                AccountRowView(account: account)
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingAccount = account
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(Color.yolk)
                                    .accessibilityLabel("Edit \(account.name)")
                            }
                            .buttonStyle(.plain)
                        }
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
