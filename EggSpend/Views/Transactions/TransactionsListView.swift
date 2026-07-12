import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Transfer.date, order: .reverse) private var transfers: [Transfer]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true }, sort: \RecurringTransaction.nextDueDate)
    private var recurring: [RecurringTransaction]
    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var hideTransfers = false
    @State private var showUpcoming = true
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
        guard filter.type == nil && !hideTransfers else { return [] }
        return transfers.filter { transfer in
            searchText.isEmpty
                || transfer.notes.localizedCaseInsensitiveContains(searchText)
                || (transfer.fromAccount?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                || (transfer.toAccount?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var upcomingRecurring: [RecurringOccurrence] {
        guard showUpcoming else { return [] }
        return RecurringProjection.occurrences(from: recurring, start: .now, days: 7)
            .filter { $0.dueDate > Date.now }
            .filter { occurrence in
                let matchesSearch = searchText.isEmpty
                    || occurrence.title.localizedCaseInsensitiveContains(searchText)
                    || occurrence.notes.localizedCaseInsensitiveContains(searchText)
                    || (occurrence.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (occurrence.account?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                return matchesSearch && matchesFilter(occurrence)
            }
    }

    private var rows: [LedgerRow] {
        (
            filteredTransactions.map(LedgerRow.transaction)
            + filteredTransfers.map(LedgerRow.transfer)
            + upcomingRecurring.map(LedgerRow.upcoming)
        )
            .sorted { $0.date > $1.date }
    }

    private var grouped: [(day: Date, rows: [LedgerRow])] {
        TransactionGrouping.groupByDay(rows)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NestBackground()

                VStack(spacing: 0) {
                    activeFilterBanner
                    filterChipsRow

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
                            transactionList
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Transactions")
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                    Menu {
                        Button {
                            showFilterSheet = true
                        } label: {
                            Label("Filter...", systemImage: filter.isActive
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                        }

                        NavigationLink(destination: RecurringTransactionsView()) {
                            Label("Recurring", systemImage: "arrow.clockwise.circle")
                        }

                        NavigationLink(destination: CategoryManagementView()) {
                            Label("Categories", systemImage: "tag.circle")
                        }

                        Button { showImport = true } label: {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Menu", systemImage: filter.isActive
                            ? "ellipsis.circle.fill"
                            : "ellipsis.circle")
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
            .onAppear {
                processRecurringTransactions(Array(recurring), context: modelContext)
            }
        }
    }

    private var transactionList: some View {
        List {
            ForEach(grouped, id: \.day) { section in
                let items = section.rows
                let groupable = items.filter { !$0.isUpcoming }
                let upcoming = items.filter { $0.isUpcoming }

                Section {
                    ForEach(Array(groupable.enumerated()), id: \.element.id) { index, row in
                        let isFirst = index == 0
                        let isLast = index == groupable.count - 1
                        rowView(for: row, showsCardBackground: false)
                            .listRowBackground(mergedRowBackground(isFirst: isFirst, isLast: isLast))
                            .listRowSeparator(.hidden)
                            .overlay(alignment: .bottom) {
                                if !isLast {
                                    Rectangle()
                                        .fill(Color.twig.opacity(0.15))
                                        .frame(height: 0.5)
                                        .padding(.leading, Space.xl * 2 + Space.lg)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        deleteRows(groupable, at: indexSet)
                    }

                    ForEach(upcoming) { row in
                        rowView(for: row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack {
                        Text(section.day, format: Date.FormatStyle().month(.wide).day().year())
                            .font(.headline)
                            .foregroundStyle(Color.twig)
                        Spacer()
                        if !groupable.isEmpty {
                            let total = dailyNetTotal(groupable)
                            Text(total, format: .currency(code: CurrencyFormat.code).sign(strategy: .always()))
                                .font(.caption.weight(.semibold))
                                .fontDesign(.rounded)
                                .foregroundStyle(total >= 0 ? Color.positive : Color.negative)
                        }
                    }
                    .textCase(nil)
                }
                .listSectionSeparator(.visible)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, Space.md)
        .padding(.top, Space.sm)
    }

    @ViewBuilder
    private func mergedRowBackground(isFirst: Bool, isLast: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Radius.card : 0,
            bottomLeadingRadius: isLast ? Radius.card : 0,
            bottomTrailingRadius: isLast ? Radius.card : 0,
            topTrailingRadius: isFirst ? Radius.card : 0,
            style: .continuous
        )
        .fill(.regularMaterial)
    }

    private func dailyNetTotal(_ items: [LedgerRow]) -> Double {
        items.reduce(0) { total, row in
            if case .transaction(let tx) = row { return total + tx.signedAmount }
            return total
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                TransactionsFilterChip(
                    label: "All",
                    systemImage: "tray.full",
                    isSelected: filter.type == nil && !hideTransfers && showUpcoming
                ) {
                    filter.type = nil
                    hideTransfers = false
                    showUpcoming = true
                }

                TransactionsFilterChip(
                    label: "Expenses",
                    systemImage: TransactionType.expense.systemImage,
                    isSelected: filter.type == .expense
                ) {
                    filter.type = filter.type == .expense ? nil : .expense
                }

                TransactionsFilterChip(
                    label: "Income",
                    systemImage: TransactionType.income.systemImage,
                    isSelected: filter.type == .income
                ) {
                    filter.type = filter.type == .income ? nil : .income
                }

                TransactionsFilterChip(
                    label: "Transfers",
                    systemImage: "arrow.left.arrow.right",
                    isSelected: filter.type == nil && !hideTransfers
                ) {
                    if filter.type != nil || hideTransfers {
                        filter.type = nil
                        hideTransfers = false
                    } else {
                        hideTransfers = true
                    }
                }

                TransactionsFilterChip(
                    label: "Upcoming",
                    systemImage: "calendar.badge.clock",
                    isSelected: showUpcoming
                ) {
                    showUpcoming.toggle()
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func rowView(for row: LedgerRow, showsCardBackground: Bool = true) -> some View {
        switch row {
        case .transaction(let tx):
            NavigationLink(destination: TransactionDetailView(transaction: tx)) {
                TransactionRowView(transaction: tx, showsCardBackground: showsCardBackground)
            }
        case .transfer(let transfer):
            NavigationLink(destination: TransferDetailView(transfer: transfer)) {
                TransferRowView(transfer: transfer, showsCardBackground: showsCardBackground)
            }
        case .upcoming(let occurrence):
            NavigationLink(destination: RecurringTransactionsView()) {
                UpcomingRecurringRowView(occurrence: occurrence)
            }
        }
    }

    @ViewBuilder
    private var activeFilterBanner: some View {
        if filter.isActive {
            HStack(spacing: Space.sm) {
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
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.md)
            .nestCard()
            .padding(.horizontal)
            .padding(.top, Space.sm)
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
            case .upcoming:
                continue
            }
        }
    }

    private func matchesFilter(_ occurrence: RecurringOccurrence) -> Bool {
        if let type = filter.type, occurrence.type != type {
            return false
        }
        if !filter.categoryIDs.isEmpty {
            guard let categoryID = occurrence.category?.id, filter.categoryIDs.contains(categoryID) else {
                return false
            }
        }
        if !filter.accountIDs.isEmpty {
            guard let accountID = occurrence.account?.id, filter.accountIDs.contains(accountID) else {
                return false
            }
        }
        if let startDate = filter.startDate, occurrence.dueDate < Calendar.current.startOfDay(for: startDate) {
            return false
        }
        if let endDate = filter.endDate, occurrence.dueDate > Calendar.current.endOfDay(for: endDate) {
            return false
        }
        if let minAmount = filter.minAmount, occurrence.amount < minAmount {
            return false
        }
        if let maxAmount = filter.maxAmount, occurrence.amount > maxAmount {
            return false
        }
        if filter.generatedOnly {
            return false
        }
        return true
    }
}

private struct UpcomingRecurringRowView: View {
    let occurrence: RecurringOccurrence

    var body: some View {
        HStack(spacing: Space.md) {
            ZStack {
                Circle()
                    .fill((occurrence.category?.color ?? Color.eggBlue).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: occurrence.category?.icon ?? occurrence.source.frequency.icon)
                    .font(.body)
                    .foregroundStyle(occurrence.category?.color ?? Color.eggBlue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: Space.sm) {
                    Text("Upcoming")
                        .font(.caption)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(Color.eggBlue.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.eggBlue)
                    if let category = occurrence.category {
                        CategoryBadgeView(category: category, compact: true)
                    }
                    Text(occurrence.dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            AmountLabel(amount: occurrence.amount, type: occurrence.type, font: .callout)
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, Space.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.eggBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
        }
    }
}

private struct TransactionsFilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(isSelected ? Color.yolk : Color.yolk.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : Color.yolk)
        }
        .buttonStyle(.plain)
        .animation(.quickFade, value: isSelected)
    }
}

#Preview {
    TransactionsListView()
        .modelContainer(PersistenceController.previewContainer())
}
