import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Transfer.date, order: .reverse) private var transfers: [Transfer]
    @Query private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true }, sort: \RecurringTransaction.nextDueDate)
    private var recurring: [RecurringTransaction]
    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var hideTransfers = false
    @State private var showUpcoming = true
    @State private var showAddTransaction = false
    @State private var showQuickAdd = false
    @State private var showFilterSheet = false
    @State private var editingTransaction: Transaction?
    @State private var editingTransfer: Transfer?
    @State private var quickAddDraft: QuickAddDraft?

    init(initialFilter: TransactionFilter = TransactionFilter(), hideTransfers: Bool = false, showUpcoming: Bool = true) {
        _filter = State(initialValue: initialFilter)
        _hideTransfers = State(initialValue: hideTransfers)
        _showUpcoming = State(initialValue: showUpcoming)
    }

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

    private var upcomingCreditCardPayments: [UpcomingPayment] {
        guard showUpcoming else { return [] }
        return Array(accounts).compactMap { account in
            guard !account.isArchived, account.type == .credit, let dueDate = account.nextDueDate else {
                return nil
            }

            let dueDay = Calendar.current.startOfDay(for: dueDate)
            guard defaultCheckingAccount != nil,
                  !hasGeneratedCreditCardPayment(for: account, dueDate: dueDay)
            else { return nil }

            let events = ForecastEngine.creditCardPaymentEvents(
                from: [account],
                transactions: Array(transactions)
            )
            guard let event = events.first else { return nil }

            return UpcomingPayment(
                id: "credit-card-\(account.id.uuidString)-\(Int(event.date.timeIntervalSince1970))",
                title: event.title,
                amount: abs(event.amount),
                dueDate: event.date,
                icon: event.categoryIcon,
                iconColor: .info,
                account: account
            )
        }
        .filter { payment in
            let matchesSearch = searchText.isEmpty
                || payment.title.localizedCaseInsensitiveContains(searchText)
                || (payment.accountName?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesSearch && matchesFilter(payment)
        }
    }

    private func hasGeneratedCreditCardPayment(for account: Account, dueDate: Date) -> Bool {
        transfers.contains { transfer in
            transfer.toAccount?.id == account.id
                && Calendar.current.isDate(transfer.date, inSameDayAs: dueDate)
                && transfer.notes == generatedCreditCardPaymentNotes(for: account)
        }
    }

    private var defaultCheckingAccount: Account? {
        accounts.first { !$0.isArchived && $0.type == .checking && $0.isDefaultChecking }
    }

    private func generatedCreditCardPaymentTransfer(from payment: UpcomingPayment) -> Transfer? {
        guard let creditCard = payment.account,
              let checking = defaultCheckingAccount
        else { return nil }

        let notes = generatedCreditCardPaymentNotes(for: creditCard)
        if let existing = transfers.first(where: {
            $0.toAccount?.id == creditCard.id
                && Calendar.current.isDate($0.date, inSameDayAs: payment.dueDate)
                && $0.notes == notes
        }) {
            return existing
        }

        let transfer = Transfer(
            amount: payment.amount,
            date: payment.dueDate,
            fromAccount: checking,
            toAccount: creditCard,
            notes: notes
        )
        modelContext.insert(transfer)
        TransferBalanceService.apply(transfer)
        try? modelContext.save()
        return transfer
    }

    private func generatedCreditCardPaymentNotes(for account: Account) -> String {
        "Auto-generated from credit card due date: \(account.name)"
    }

    private var rows: [LedgerRow] {
        (
            filteredTransactions.map(LedgerRow.transaction)
            + filteredTransfers.map(LedgerRow.transfer)
            + upcomingRecurring.map(LedgerRow.upcoming)
            + upcomingCreditCardPayments.map(LedgerRow.upcomingPayment)
        )
            .sorted { $0.date > $1.date }
    }

    private var topCategories: [TransactionCategory] {
        let activeCategories = categories.filter { !$0.isArchived }
        let usageCounts = Dictionary(grouping: transactions.compactMap(\.category?.id), by: { $0 })
            .mapValues(\.count)

        return activeCategories
            .sorted {
                let lhsCount = usageCounts[$0.id, default: 0]
                let rhsCount = usageCounts[$1.id, default: 0]
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return $0.sortOrder < $1.sortOrder
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                NestBackground()

                VStack(spacing: 0) {
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

                Button { showQuickAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(Color.yolk, in: Circle())
                        .shadow(color: Color.nestBrown.opacity(0.18), radius: 12, y: 6)
                }
                .accessibilityLabel("Add transaction")
                .padding(.trailing, Space.lg)
                .padding(.bottom, Space.lg)
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search transactions")
            .toolbar {
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
                    } label: {
                        Label("Menu", systemImage: filter.isActive
                            ? "ellipsis.circle.fill"
                            : "ellipsis.circle")
                    }
                    .foregroundStyle(Color.yolk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        quickAddDraft = nil
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                addTransactionSheet
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheet(onMoreOptions: openFullFormFromQuickAdd)
                    .presentationDetents(quickAddDetents)
            }
            .sheet(item: $editingTransaction) { transaction in
                AddTransactionView(editingTransaction: transaction)
            }
            .sheet(item: $editingTransfer) { transfer in
                AddTransactionView(editingTransfer: transfer)
            }
            .sheet(isPresented: $showFilterSheet) {
                TransactionFilterView(filter: $filter, hideTransfers: $hideTransfers)
            }
            .onAppear {
                processRecurringTransactions(Array(recurring), context: modelContext)
            }
        }
    }

    private var quickAddDetents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(460), .large]
    }

    @ViewBuilder
    private var addTransactionSheet: some View {
        if let quickAddDraft {
            AddTransactionView(
                initialEntryKind: quickAddDraft.entryKind,
                initialTitle: quickAddDraft.title,
                initialAmountText: quickAddDraft.amountText,
                initialDate: quickAddDraft.date,
                initialCategory: quickAddDraft.category,
                initialAccount: quickAddDraft.account,
                initialBudget: quickAddDraft.budget
            )
        } else {
            AddTransactionView()
        }
    }

    private func openFullFormFromQuickAdd(_ draft: QuickAddDraft) {
        quickAddDraft = draft
        showQuickAdd = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showAddTransaction = true
        }
    }

    private var transactionList: some View {
        List {
            ForEach(rows) { row in
                rowView(for: row, showsCardBackground: false)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: Space.md))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, Space.md)
        .padding(.top, Space.xs)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                if filter.isActive {
                    TransactionsFilterStatusChip(count: filter.activeCount) {
                        filter.reset()
                    }
                }

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
            .padding(.vertical, Space.xs)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func rowView(for row: LedgerRow, showsCardBackground: Bool = true) -> some View {
        switch row {
        case .transaction(let tx):
            NavigationLink(destination: TransactionDetailView(transaction: tx)) {
                LedgerRowView(row: row, showsMeta: [.category, .account, .date], verticalPadding: Space.xs)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    AccountBalanceService.reverse(tx, from: tx.account)
                    modelContext.delete(tx)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    editingTransaction = tx
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.yolk)

                if !topCategories.isEmpty {
                    Menu {
                        ForEach(topCategoriesFor(tx)) { category in
                            Button {
                                tx.category = category
                            } label: {
                                Label(category.name, systemImage: category.icon)
                            }
                        }
                    } label: {
                        Label("Categorize", systemImage: "tag")
                    }
                    .tint(.info)
                }
            }
        case .transfer(let transfer):
            NavigationLink(destination: TransferDetailView(transfer: transfer)) {
                LedgerRowView(row: row, showsMeta: [.date], verticalPadding: Space.xs)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    TransferBalanceService.reverse(transfer)
                    modelContext.delete(transfer)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    editingTransfer = transfer
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.yolk)
            }
        case .upcoming:
            NavigationLink(destination: RecurringTransactionsView()) {
                LedgerRowView(row: row, style: .upcoming, verticalPadding: Space.xs)
            }
        case .upcomingPayment(let payment):
            Button {
                editingTransfer = generatedCreditCardPaymentTransfer(from: payment)
            } label: {
                LedgerRowView(row: row, style: .upcoming, verticalPadding: Space.xs)
            }
            .buttonStyle(.plain)
        }
    }

    private func topCategoriesFor(_ transaction: Transaction) -> [TransactionCategory] {
        topCategories.filter { $0.appliesTo == nil || $0.appliesTo == transaction.type }
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
            case .upcomingPayment:
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
        if filter.uncategorizedOnly && occurrence.category != nil {
            return false
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

    private func matchesFilter(_ payment: UpcomingPayment) -> Bool {
        if let type = filter.type, type != .expense {
            return false
        }
        if !filter.categoryIDs.isEmpty || filter.uncategorizedOnly {
            return false
        }
        if !filter.accountIDs.isEmpty {
            guard let accountID = payment.account?.id, filter.accountIDs.contains(accountID) else {
                return false
            }
        }
        if let startDate = filter.startDate, payment.dueDate < Calendar.current.startOfDay(for: startDate) {
            return false
        }
        if let endDate = filter.endDate, payment.dueDate > Calendar.current.endOfDay(for: endDate) {
            return false
        }
        if let minAmount = filter.minAmount, payment.amount < minAmount {
            return false
        }
        if let maxAmount = filter.maxAmount, payment.amount > maxAmount {
            return false
        }
        if filter.generatedOnly {
            return false
        }
        return true
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
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Space.sm)
                .frame(height: 32)
                .background(isSelected ? Color.yolk : Color.yolk.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : Color.yolk)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .animation(.quickFade, value: isSelected)
    }
}

private struct TransactionsFilterStatusChip: View {
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Label(count == 1 ? "1 active" : "\(count) active", systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.nestBrown)

            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.yolk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear filters")
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 32)
        .background(Color.yolk.opacity(0.12), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    TransactionsListView()
        .modelContainer(PersistenceController.previewContainer())
}
