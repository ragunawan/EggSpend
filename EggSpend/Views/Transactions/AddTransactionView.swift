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
    @Query private var categoryRules: [CategoryRule]
    @Query private var budgets: [Budget]
    @AppStorage("lastUsedAccountID") private var lastUsedAccountID = ""

    var editingTransaction: Transaction? = nil
    var editingTransfer: Transfer? = nil
    var initialEntryKind: EntryKind = .expense
    var initialTitle: String = ""
    var initialAmountText: String = ""
    var initialDate: Date = .now
    var initialCategory: TransactionCategory? = nil
    var initialAccount: Account? = nil
    var initialBudget: Budget? = nil

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

    private var availableBudgets: [Budget] {
        budgets
            .filter { $0.isActive || $0.id == selectedBudget?.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                    categorySection
                    if selectedEntryKind == .expense {
                        budgetSection
                    }
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
                     : "Please enter a payee and an amount greater than zero.")
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
                .accessibilityLabel("Transaction type")
                .onChange(of: selectedEntryKind) { _, newKind in
                    if let cat = selectedCategory, cat.appliesTo != nil, cat.appliesTo != newKind.transactionType {
                        selectedCategory = nil
                    }
                    if newKind != .expense {
                        selectedBudget = nil
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Payee", text: $title)
                .onSubmit { prefillCategoryForTitle() }
            HStack {
                Text(CurrencyFormat.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Amount")
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var transferDetailsSection: some View {
        Section("Details") {
            HStack {
                Text(CurrencyFormat.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Amount")
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
                        .accessibilityHidden(true)
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Account")
                    .accessibilityValue(selectedAccount?.name ?? "None")
                }
                .frame(minHeight: 44)
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
                        .foregroundStyle(Color.negative)
                }
            }
        } header: {
            Text("Accounts")
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
            }
        }
    }

    private var budgetSection: some View {
        Section("Budget") {
            if availableBudgets.isEmpty {
                Text("No active budgets")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Budget", selection: $selectedBudget) {
                    Text("Unbudgeted").tag(Optional<Budget>.none)
                    ForEach(availableBudgets) { budget in
                        Label(budget.name, systemImage: budget.period.icon)
                            .tag(Optional(budget))
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
            TransactionEntryService.updateTransaction(
                tx,
                title: title,
                amount: amount,
                date: date,
                type: type,
                category: selectedCategory,
                account: selectedAccount,
                budget: selectedBudget,
                notes: notes,
                context: modelContext
            )
        } else {
            TransactionEntryService.createTransaction(
                title: title,
                amount: amount,
                date: date,
                type: type,
                category: selectedCategory,
                account: selectedAccount,
                budget: selectedBudget,
                notes: notes,
                context: modelContext
            )
        }
        rememberSelectedAccount()
    }

    private func saveTransfer() {
        if let transfer = editingTransfer {
            TransactionEntryService.updateTransfer(
                transfer,
                amount: amount,
                date: date,
                fromAccount: fromAccount,
                toAccount: toAccount,
                notes: notes
            )
        } else {
            TransactionEntryService.createTransfer(
                amount: amount,
                date: date,
                fromAccount: fromAccount,
                toAccount: toAccount,
                notes: notes,
                context: modelContext
            )
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
            selectedBudget = tx.type == .expense ? tx.budget : nil
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
            title = initialTitle
            amountText = initialAmountText
            date = initialDate
            selectedCategory = initialCategory
            selectedAccount = initialAccount
            selectedBudget = initialEntryKind == .expense ? initialBudget : nil
            if let selectedCategory, !categoryMatchesSelectedType(selectedCategory) {
                self.selectedCategory = nil
            }
            applyLastUsedAccountDefault()
        }
    }

    private func prefillCategoryForTitle() {
        guard let category = CategoryRuleEngine.categoryFor(title: title, rules: categoryRules, categories: categories),
              categoryMatchesSelectedType(category)
        else { return }
        selectedCategory = category
    }

    private func categoryMatchesSelectedType(_ category: TransactionCategory) -> Bool {
        guard let type = selectedEntryKind.transactionType else { return false }
        return !category.isArchived && (category.appliesTo == nil || category.appliesTo == type)
    }

    private func applyLastUsedAccountDefault() {
        guard !isEditing,
              initialAccount == nil,
              selectedAccount == nil,
              selectedEntryKind != .transfer,
              !lastUsedAccountID.isEmpty
        else { return }

        guard let id = UUID(uuidString: lastUsedAccountID) else {
            lastUsedAccountID = ""
            return
        }

        guard let account = accounts.first(where: { $0.id == id && !$0.isArchived }) else {
            lastUsedAccountID = ""
            return
        }

        selectedAccount = account
    }

    private func rememberSelectedAccount() {
        guard let selectedAccount else { return }
        lastUsedAccountID = selectedAccount.id.uuidString
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(PersistenceController.previewContainer())
}
