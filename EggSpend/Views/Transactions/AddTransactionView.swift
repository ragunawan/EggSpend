import SwiftUI
import SwiftData

enum EntryKind: String, CaseIterable, Hashable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"

    var transactionType: TransactionType? {
        TransactionType(rawValue: rawValue)
    }
}

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [TransactionCategory]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]

    var editingTransaction: Transaction? = nil
    var editingTransfer: Transfer? = nil
    var initialEntryKind: EntryKind = .expense

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var selectedEntryKind: EntryKind = .expense
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var selectedAccount: Account? = nil
    @State private var selectedBudget: Budget? = nil
    @State private var fromAccount: Account? = nil
    @State private var toAccount: Account? = nil
    @State private var notes = ""
    @State private var showValidationError = false

    private var isEditing: Bool { editingTransaction != nil || editingTransfer != nil }

    // Which segments the type picker offers: all three for a new entry, Income/Expense
    // only when editing an existing Transaction (preserves prior editing behavior), and
    // none when editing an existing Transfer (converting record kinds isn't supported).
    private var pickerCases: [EntryKind] {
        if isEditing {
            return editingTransfer != nil ? [] : [.income, .expense]
        }
        return EntryKind.allCases
    }

    // Archived accounts are hidden from pickers unless already selected (editing an
    // existing transaction/transfer linked to one), otherwise the picker would render blank.
    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0 == selectedAccount }
    }

    private var availableFromAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0 == fromAccount }
    }

    private var availableToAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0 == toAccount }
    }

    private var availableCategories: [TransactionCategory] {
        guard let type = selectedEntryKind.transactionType else { return [] }
        // Archived categories are hidden from the picker — only active categories appear here.
        return categories.filter { ($0.appliesTo == nil || $0.appliesTo == type) && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // Budgets only ever track expense spend, so the selector is expense-only.
    private var availableBudgets: [Budget] {
        budgets.sorted { $0.name < $1.name }
    }

    private var amount: Double { AmountParser.parse(amountText) ?? 0 }

    private var isValid: Bool {
        guard amount > 0 else { return false }
        switch selectedEntryKind {
        case .income, .expense:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .transfer:
            guard let fromAccount, let toAccount else { return false }
            return fromAccount.id != toAccount.id
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                typePicker
                if selectedEntryKind == .transfer {
                    transferDetailsSection
                    transferAccountsSection
                } else {
                    detailsSection
                    accountSection
                    if selectedEntryKind == .expense { budgetSection }
                    categorySection
                }
                notesSection
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Missing Information", isPresented: $showValidationError) {
                Button("OK") {}
            } message: {
                Text(selectedEntryKind == .transfer
                     ? "Please choose two different accounts and an amount greater than zero."
                     : "Please enter a title and an amount greater than zero.")
            }
            .onAppear { populateIfEditing() }
        }
    }

    private var navigationTitleText: String {
        switch (isEditing, selectedEntryKind) {
        case (true, .transfer): return "Edit Transfer"
        case (false, .transfer): return "New Transfer"
        case (true, _): return "Edit Transaction"
        case (false, _): return "New Transaction"
        }
    }

    @ViewBuilder
    private var typePicker: some View {
        if !pickerCases.isEmpty {
            Section {
                Picker("Type", selection: $selectedEntryKind) {
                    ForEach(pickerCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedEntryKind) { _, newKind in
                    if let cat = selectedCategory, cat.appliesTo != nil, cat.appliesTo != newKind.transactionType {
                        selectedCategory = nil
                    }
                    if newKind != .expense { selectedBudget = nil }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            HStack {
                Text(CurrencyFormat.symbol)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var transferDetailsSection: some View {
        Section("Details") {
            HStack {
                Text(CurrencyFormat.symbol)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if accounts.isEmpty {
                Text("No accounts added yet")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Account")
                    Spacer()
                    Menu {
                        Button("None") { selectedAccount = nil }
                        ForEach(availableAccounts) { account in
                            Button {
                                selectedAccount = account
                            } label: {
                                Label(accountSelectionTitle(for: account), systemImage: account.type.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedAccount.map(accountSelectionTitle) ?? "None")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 180, alignment: .trailing)
                }
            }
        }
    }

    private func accountSelectionTitle(for account: Account) -> String {
        "\(account.name) (\(account.balance.formatted(.currency(code: CurrencyFormat.code))))"
    }

    private var transferAccountsSection: some View {
        Section {
            if accounts.count < 2 {
                Text("Add at least two accounts to make a transfer.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("From", selection: $fromAccount) {
                    Text("Select").tag(Optional<Account>.none)
                    ForEach(availableFromAccounts) { account in
                        Label(account.name, systemImage: account.type.icon)
                            .tag(Optional(account))
                    }
                }
                Picker("To", selection: $toAccount) {
                    Text("Select").tag(Optional<Account>.none)
                    ForEach(availableToAccounts) { account in
                        Label(account.name, systemImage: account.type.icon)
                            .tag(Optional(account))
                    }
                }
                if let fromAccount, let toAccount, fromAccount.id == toAccount.id {
                    Label("Choose two different accounts.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Accounts")
        }
    }

    private var budgetSection: some View {
        Section {
            if availableBudgets.isEmpty {
                Text("No budgets added yet")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Budget", selection: $selectedBudget) {
                    Text("None").tag(Optional<Budget>.none)
                    ForEach(availableBudgets) { budget in
                        Text(budget.name).tag(Optional(budget))
                    }
                }
                .onChange(of: selectedBudget) { _, newBudget in
                    if let newBudget { selectedCategory = newBudget.category }
                }
            }
        } header: {
            Text("Budget")
        } footer: {
            Text("Assigns this transaction's category to match the selected budget.")
        }
    }

    private var categorySection: some View {
        Section("Category") {
            if availableCategories.isEmpty {
                Text("No categories available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(availableCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                            .tag(Optional(cat))
                    }
                    Text("None").tag(Optional<TransactionCategory>.none)
                }
                .onChange(of: selectedCategory) { _, newCategory in
                    if let selectedBudget, selectedBudget.category?.id != newCategory?.id {
                        self.selectedBudget = nil
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Add a note (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func save() {
        guard isValid else {
            showValidationError = true
            return
        }
        switch selectedEntryKind {
        case .income, .expense:
            saveTransaction()
        case .transfer:
            saveTransfer()
        }
        dismiss()
    }

    private func saveTransaction() {
        guard let type = selectedEntryKind.transactionType else { return }
        if let tx = editingTransaction {
            // Capture old account before any changes so we can reverse its effect.
            let oldAccount = tx.account
            AccountBalanceService.reverse(tx, from: oldAccount)

            tx.title = title.trimmingCharacters(in: .whitespaces)
            tx.amount = amount
            tx.date = date
            tx.type = type
            tx.category = selectedCategory
            tx.account = selectedAccount
            tx.notes = notes

            AccountBalanceService.apply(tx, to: selectedAccount)
            if let selectedCategory {
                CategoryRuleEngine.recordRule(title: title.trimmingCharacters(in: .whitespaces), category: selectedCategory, context: modelContext)
            }
            BudgetAlertCoordinator.checkBudgets(context: modelContext)
        } else {
            let tx = Transaction(
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount,
                date: date,
                type: type,
                category: selectedCategory,
                account: selectedAccount,
                notes: notes
            )
            modelContext.insert(tx)
            AccountBalanceService.apply(tx, to: selectedAccount)
            if let selectedCategory {
                CategoryRuleEngine.recordRule(title: title.trimmingCharacters(in: .whitespaces), category: selectedCategory, context: modelContext)
            }
            BudgetAlertCoordinator.checkBudgets(context: modelContext)
        }
    }

    private func saveTransfer() {
        if let transfer = editingTransfer {
            // Capture old accounts before any changes so we can reverse their effect.
            TransferBalanceService.reverse(transfer)

            transfer.amount = amount
            transfer.date = date
            transfer.fromAccount = fromAccount
            transfer.toAccount = toAccount
            transfer.notes = notes

            TransferBalanceService.apply(transfer)
        } else {
            let transfer = Transfer(
                amount: amount,
                date: date,
                fromAccount: fromAccount,
                toAccount: toAccount,
                notes: notes
            )
            modelContext.insert(transfer)
            TransferBalanceService.apply(transfer)
        }
    }

    private func populateIfEditing() {
        if let tx = editingTransaction {
            title = tx.title
            amountText = tx.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
            date = tx.date
            selectedEntryKind = tx.type == .income ? .income : .expense
            selectedCategory = tx.category
            selectedAccount = tx.account
            if tx.type == .expense {
                selectedBudget = availableBudgets.first { $0.category?.id == tx.category?.id }
            }
            notes = tx.notes
        } else if let transfer = editingTransfer {
            selectedEntryKind = .transfer
            amountText = transfer.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
            date = transfer.date
            fromAccount = transfer.fromAccount
            toAccount = transfer.toAccount
            notes = transfer.notes
        } else {
            selectedEntryKind = initialEntryKind
        }
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(PersistenceController.previewContainer())
}
