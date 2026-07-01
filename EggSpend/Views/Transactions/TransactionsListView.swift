import SwiftUI
import SwiftData

enum LedgerRow: Identifiable {
    case transaction(Transaction)
    case transfer(Transfer)

    var id: UUID {
        switch self {
        case .transaction(let tx): return tx.id
        case .transfer(let transfer): return transfer.id
        }
    }

    var date: Date {
        switch self {
        case .transaction(let tx): return tx.date
        case .transfer(let transfer): return transfer.date
        }
    }
}

struct TransactionsListView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Transfer.date, order: .reverse) private var transfers: [Transfer]
    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var hideTransfers = false
    @State private var showAddTransaction = false
    @State private var showImport = false
    @State private var showFilterSheet = false

    private var filteredTransactions: [Transaction] {
        transactions.filter { tx in
            let matchesSearch = searchText.isEmpty
                || tx.title.localizedCaseInsensitiveContains(searchText)
                || tx.notes.localizedCaseInsensitiveContains(searchText)
                || (tx.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesSearch && filter.matches(tx)
        }
    }

    private var filteredTransfers: [Transfer] {
        guard !hideTransfers else { return [] }
        return transfers.filter { transfer in
            searchText.isEmpty
                || transfer.notes.localizedCaseInsensitiveContains(searchText)
                || (transfer.fromAccount?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                || (transfer.toAccount?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var rows: [LedgerRow] {
        (filteredTransactions.map(LedgerRow.transaction) + filteredTransfers.map(LedgerRow.transfer))
            .sorted { $0.date > $1.date }
    }

    private var grouped: [(String, [LedgerRow])] {
        let formatter = DateFormatter.sectionHeader
        var dict: [String: [LedgerRow]] = [:]
        for row in rows {
            let key = formatter.string(from: row.date)
            dict[key, default: []].append(row)
        }
        return dict.sorted { lhs, rhs in
            let d1 = rows.first { formatter.string(from: $0.date) == lhs.key }?.date ?? .distantPast
            let d2 = rows.first { formatter.string(from: $0.date) == rhs.key }?.date ?? .distantPast
            return d1 > d2
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedCanopyBackground()

                VStack(spacing: 0) {
                    activeFilterBanner

                    Group {
                        if transactions.isEmpty && transfers.isEmpty {
                            ContentUnavailableView {
                                Label {
                                    Text("No Transactions")
                                } icon: {
                                    Image(systemName: "tray").symbolEffect(.pulse)
                                }
                            } description: {
                                Text("Tap + to record your first transaction.")
                            }
                        } else if rows.isEmpty {
                            if filter.isActive && searchText.isEmpty {
                                ContentUnavailableView {
                                    Label {
                                        Text("No Matching Transactions")
                                    } icon: {
                                        Image(systemName: "line.3.horizontal.decrease.circle").symbolEffect(.pulse)
                                    }
                                } description: {
                                    Text("Try adjusting or clearing your filters.")
                                } actions: {
                                    Button("Clear Filters") { filter.reset() }
                                }
                            } else {
                                ContentUnavailableView.search(text: searchText)
                            }
                        } else {
                            List {
                                ForEach(grouped, id: \.0) { section, items in
                                    Section {
                                        ForEach(items) { row in
                                            rowView(for: row)
                                                .listRowBackground(Color.clear)
                                        }
                                        .onDelete { indexSet in
                                            deleteRows(items, at: indexSet)
                                        }
                                    } header: {
                                        Text(section)
                                            .font(.headline)
                                            .foregroundStyle(Color.twig)
                                            .textCase(nil)
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: Color.nestBrown.opacity(0.10), radius: 8, x: 0, y: 3)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddTransaction = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.yolk)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        filterButton
                        NavigationLink(destination: RecurringTransactionsView()) {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        NavigationLink(destination: CategoryManagementView()) {
                            Image(systemName: "tag.circle")
                        }
                        Button { showImport = true } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .foregroundStyle(Color.yolk)
                }
            }
            .sheet(isPresented: $showImport) {
                CSVImportView(importType: .transactions)
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showFilterSheet) {
                TransactionFilterView(filter: $filter, hideTransfers: $hideTransfers)
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: LedgerRow) -> some View {
        switch row {
        case .transaction(let tx):
            NavigationLink(destination: TransactionDetailView(transaction: tx)) {
                TransactionRowView(transaction: tx)
            }
        case .transfer(let transfer):
            NavigationLink(destination: TransferDetailView(transfer: transfer)) {
                TransferRowView(transfer: transfer)
            }
        }
    }

    private var filterButton: some View {
        Button { showFilterSheet = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                if filter.isActive {
                    Circle()
                        .fill(Color.yolk)
                        .frame(width: 7, height: 7)
                        .offset(x: 5, y: -3)
                }
            }
        }
    }

    @ViewBuilder
    private var activeFilterBanner: some View {
        if filter.isActive {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(Color.yolk)
                Text(filter.activeCount == 1 ? "1 filter active" : "\(filter.activeCount) filters active")
                    .font(.subheadline)
                    .foregroundStyle(Color.nestBrown)
                Spacer()
                Button("Clear") { filter.reset() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.yolk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .nestCard()
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func deleteRows(_ items: [LedgerRow], at offsets: IndexSet) {
        for index in offsets {
            switch items[index] {
            case .transaction(let tx):
                AccountBalanceService.reverse(tx, from: tx.account)
                modelContext.delete(tx)
            case .transfer(let transfer):
                TransferBalanceService.reverse(transfer)
                modelContext.delete(transfer)
            }
        }
    }
}

extension DateFormatter {
    static let sectionHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()
}

#Preview {
    TransactionsListView()
        .modelContainer(PersistenceController.previewContainer())
}
