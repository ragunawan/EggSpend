import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var showAddTransaction = false
    @State private var showImport = false
    @State private var showFilterSheet = false

    private var filtered: [Transaction] {
        transactions.filter { tx in
            let matchesSearch = searchText.isEmpty
                || tx.title.localizedCaseInsensitiveContains(searchText)
                || tx.notes.localizedCaseInsensitiveContains(searchText)
                || (tx.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesSearch && filter.matches(tx)
        }
    }

    private var grouped: [(String, [Transaction])] {
        let formatter = DateFormatter.sectionHeader
        var dict: [String: [Transaction]] = [:]
        for tx in filtered {
            let key = formatter.string(from: tx.date)
            dict[key, default: []].append(tx)
        }
        return dict.sorted { lhs, rhs in
            let d1 = filtered.first { formatter.string(from: $0.date) == lhs.key }?.date ?? .distantPast
            let d2 = filtered.first { formatter.string(from: $0.date) == rhs.key }?.date ?? .distantPast
            return d1 > d2
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nestCanopy.ignoresSafeArea()

                VStack(spacing: 0) {
                    activeFilterBanner

                    Group {
                        if transactions.isEmpty {
                            ContentUnavailableView(
                                "No Transactions",
                                systemImage: "tray",
                                description: Text("Tap + to record your first transaction.")
                            )
                        } else if filtered.isEmpty {
                            if filter.isActive && searchText.isEmpty {
                                ContentUnavailableView {
                                    Label("No Matching Transactions", systemImage: "line.3.horizontal.decrease.circle")
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
                                        ForEach(items) { tx in
                                            NavigationLink(destination: TransactionDetailView(transaction: tx)) {
                                                TransactionRowView(transaction: tx)
                                            }
                                            .listRowBackground(Color.clear)
                                        }
                                        .onDelete { indexSet in
                                            deleteTransactions(items, at: indexSet)
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
                TransactionFilterView(filter: $filter)
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

    private func deleteTransactions(_ items: [Transaction], at offsets: IndexSet) {
        for index in offsets {
            let tx = items[index]
            AccountBalanceService.reverse(tx, from: tx.account)
            modelContext.delete(tx)
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
