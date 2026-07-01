import SwiftUI
import SwiftData
import Charts

struct NetWorthView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showAddAccount = false
    @State private var showImport = false
    @State private var editingAccount: Account? = nil

    private var assets: [Account] { accounts.filter(\.isAsset) }
    private var liabilities: [Account] { accounts.filter { !$0.isAsset } }

    private var totalAssets: Double { assets.reduce(0) { $0 + $1.balance } }
    private var totalLiabilities: Double { liabilities.reduce(0) { $0 + abs($1.balance) } }
    private var netWorth: Double { totalAssets - totalLiabilities }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedCanopyBackground()

                List {
                    summarySection
                    chartSection
                    assetsSection
                    liabilitiesSection
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
                            .font(.title2)
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
                    Text(netWorth, format: .currency(code: "USD"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(netWorth >= 0 ? Color.primary : Color.red)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalAssets, format: .currency(code: "USD"))
                            .font(.headline)
                            .foregroundStyle(Color.nestLeafGreen)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Liabilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalLiabilities, format: .currency(code: "USD"))
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.vertical, 8)
            .appearRise(delay: 0.05)
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

                BarMark(
                    x: .value("Type", "Liabilities"),
                    y: .value("Amount", totalLiabilities)
                )
                .foregroundStyle(.red)
            }
            .frame(height: 180)
            .padding(.vertical, 8)
            .appearRise(delay: 0.1)
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
                    }
                    .onDelete { indexSet in deleteAccounts(assets, at: indexSet) }
                }
            }
            .appearRise(delay: 0.15)
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
                        NavigationLink(destination: DebtPayoffPlannerView(account: account)) {
                            AccountRowView(account: account)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") {
                                editingAccount = account
                            }
                            .tint(Color.yolk)
                        }
                    }
                    .onDelete { indexSet in deleteAccounts(liabilities, at: indexSet) }
                }
            }
            .appearRise(delay: 0.2)
        }
        .listRowBackground(Color.clear)
    }

    @Environment(\.modelContext) private var modelContext

    private func deleteAccounts(_ list: [Account], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((account.isAsset ? Color.nestLeafGreen : Color.red).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: account.type.icon)
                    .foregroundStyle(account.isAsset ? Color.nestLeafGreen : .red)
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
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(abs(account.balance), format: .currency(code: "USD"))
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(account.isAsset ? Color.nestLeafGreen : .red)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NetWorthView()
        .modelContainer(PersistenceController.previewContainer())
}
