import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [TransactionCategory]
    @Query(sort: \Account.name) private var accounts: [Account]

    var editingTransaction: Transaction? = nil

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var selectedType: TransactionType = .expense
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var selectedAccount: Account? = nil
    @State private var notes = ""
    @State private var showValidationError = false

    private var isEditing: Bool { editingTransaction != nil }

    private var availableCategories: [TransactionCategory] {
        // Archived categories are hidden from the picker — only active categories appear here.
        categories.filter { ($0.appliesTo == nil || $0.appliesTo == selectedType) && !$0.isArchived }
            .sorted { $0.name < $1.name }
    }

    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                typePicker
                detailsSection
                accountSection
                categorySection
                notesSection
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
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
                Text("Please enter a title and an amount greater than zero.")
            }
            .onAppear { populateIfEditing() }
        }
    }

    private var typePicker: some View {
        Section {
            Picker("Type", selection: $selectedType) {
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedType) { _, _ in
                if let cat = selectedCategory, cat.appliesTo != nil, cat.appliesTo != selectedType {
                    selectedCategory = nil
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            HStack {
                Text("$")
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
                Picker("Account", selection: $selectedAccount) {
                    Text("None").tag(Optional<Account>.none)
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.type.icon)
                            .tag(Optional(account))
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            if availableCategories.isEmpty {
                Text("No categories available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(Optional<TransactionCategory>.none)
                    ForEach(availableCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                            .tag(Optional(cat))
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
        if let tx = editingTransaction {
            // Capture old account before any changes so we can reverse its effect.
            let oldAccount = tx.account
            AccountBalanceService.reverse(tx, from: oldAccount)

            tx.title = title.trimmingCharacters(in: .whitespaces)
            tx.amount = amount
            tx.date = date
            tx.type = selectedType
            tx.category = selectedCategory
            tx.account = selectedAccount
            tx.notes = notes

            AccountBalanceService.apply(tx, to: selectedAccount)
        } else {
            let tx = Transaction(
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount,
                date: date,
                type: selectedType,
                category: selectedCategory,
                account: selectedAccount,
                notes: notes
            )
            modelContext.insert(tx)
            AccountBalanceService.apply(tx, to: selectedAccount)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let tx = editingTransaction else { return }
        title = tx.title
        amountText = String(format: "%.2f", tx.amount)
        date = tx.date
        selectedType = tx.type
        selectedCategory = tx.category
        selectedAccount = tx.account
        notes = tx.notes
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(PersistenceController.previewContainer())
}
