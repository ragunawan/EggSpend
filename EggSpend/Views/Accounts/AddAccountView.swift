import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editingAccount: Account? = nil

    @State private var name = ""
    @State private var selectedType: AccountType = .checking
    @State private var balanceText = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var aprText = ""
    @State private var minimumPaymentText = ""
    @State private var extraPaymentText = ""
    @State private var includeInNetWorth = true
    @State private var showValidationError = false

    private var isEditing: Bool { editingAccount != nil }
    private var balance: Double { Double(balanceText) ?? 0 }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $name)
                    Picker("Type", selection: $selectedType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .onChange(of: selectedType) { _, newType in
                        if newType != .credit && newType != .loan {
                            hasDueDate = false
                            aprText = ""
                            minimumPaymentText = ""
                            extraPaymentText = ""
                            includeInNetWorth = true
                        }
                    }
                    HStack {
                        Text(selectedType.isAsset ? "Balance" : "Amount Owed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if selectedType == .credit || selectedType == .loan {
                        Toggle("Has Due Date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                        }
                        Toggle("Include in Net Worth", isOn: $includeInNetWorth)
                    }
                }

                if selectedType == .credit || selectedType == .loan {
                    Section("Payoff Planning") {
                        HStack {
                            Text("APR")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("0.00", text: $aprText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                        currencyField("Minimum Payment", text: $minimumPaymentText)
                        currencyField("Extra Payment", text: $extraPaymentText)
                    }
                }

                Section("Notes") {
                    TextField("Optional note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
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
                Text("Please enter an account name.")
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func save() {
        guard isValid else {
            showValidationError = true
            return
        }
        let stored = selectedType.isAsset ? abs(balance) : -abs(balance)
        let resolvedDueDate = (selectedType == .credit || selectedType == .loan) && hasDueDate ? dueDate : nil
        if let account = editingAccount {
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.type = selectedType
            account.balance = stored
            account.notes = notes
            account.dueDate = resolvedDueDate
            account.annualPercentageRate = selectedType.isAsset ? nil : Double(aprText)
            account.minimumPayment = selectedType.isAsset ? nil : Double(minimumPaymentText)
            account.plannedExtraPayment = selectedType.isAsset ? nil : Double(extraPaymentText)
            account.includeInNetWorth = selectedType.isAsset ? true : includeInNetWorth
        } else {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: selectedType,
                balance: stored,
                notes: notes
            )
            account.dueDate = resolvedDueDate
            account.annualPercentageRate = selectedType.isAsset ? nil : Double(aprText)
            account.minimumPayment = selectedType.isAsset ? nil : Double(minimumPaymentText)
            account.plannedExtraPayment = selectedType.isAsset ? nil : Double(extraPaymentText)
            account.includeInNetWorth = selectedType.isAsset ? true : includeInNetWorth
            modelContext.insert(account)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let account = editingAccount else { return }
        name = account.name
        selectedType = account.type
        balanceText = String(format: "%.2f", abs(account.balance))
        notes = account.notes
        hasDueDate = account.dueDate != nil
        dueDate = account.dueDate ?? Date.now
        aprText = account.annualPercentageRate.map { String(format: "%.2f", $0) } ?? ""
        minimumPaymentText = account.minimumPayment.map { String(format: "%.2f", $0) } ?? ""
        extraPaymentText = account.plannedExtraPayment.map { String(format: "%.2f", $0) } ?? ""
        includeInNetWorth = account.includeInNetWorth
    }

    private func currencyField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("$")
                .foregroundStyle(.secondary)
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    AddAccountView()
        .modelContainer(PersistenceController.previewContainer())
}
