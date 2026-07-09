import SwiftUI
import SwiftData

struct AccountsView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showAddAccount = false
    @State private var showAddTransfer = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountType.allCases) { type in
                    let typeAccounts = accounts.filter { $0.type == type }
                    if !typeAccounts.isEmpty {
                        Section(type.rawValue) {
                            ForEach(typeAccounts) { account in
                                accountRow(account)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddAccount = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAddTransfer = true } label: {
                        Image(systemName: "arrow.left.arrow.right.circle")
                    }
                    .disabled(accounts.count < 2)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView()
            }
            .sheet(isPresented: $showAddTransfer) {
                AddTransactionView(initialEntryKind: .transfer)
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Accounts")
                        } icon: {
                            Image(systemName: "building.columns").symbolEffect(.pulse)
                        }
                    } description: {
                        Text("Add your first account to track net worth.")
                    }
                }
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack {
            Image(systemName: account.type.icon)
                .frame(width: 32)
                .foregroundStyle(account.isAsset ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if !account.notes.isEmpty {
                    Text(account.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(abs(account.balance), format: .currency(code: CurrencyFormat.code))
                .foregroundStyle(account.isAsset ? .green : .red)
                .font(.system(.callout, design: .rounded, weight: .medium))
        }
    }
}

#Preview {
    AccountsView()
        .modelContainer(PersistenceController.previewContainer())
}
