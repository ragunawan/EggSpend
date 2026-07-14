import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.name) private var accounts: [Account]

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
    @State private var mortgageOriginalPrincipalText = ""
    @State private var mortgageTermYearsText = ""
    @State private var mortgageFirstPaymentDate = Date.now
    @State private var mortgagePropertyTaxText = ""
    @State private var mortgageInsuranceText = ""
    @State private var mortgagePMIText = ""
    @State private var mortgageEscrowText = ""
    @State private var includeInNetWorth = true
    @State private var isDefaultChecking = false
    @State private var showValidationError = false
    @State private var loadedBalance: Double = 0
    @State private var hasPopulated = false

    private var isEditing: Bool { editingAccount != nil }
    private var balance: Double { AmountParser.parse(balanceText) ?? 0 }
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
                        if !newType.isLiability {
                            hasDueDate = false
                            aprText = ""
                            minimumPaymentText = ""
                            extraPaymentText = ""
                            includeInNetWorth = true
                        }
                        if newType == .checking, !hasOtherDefaultCheckingAccount {
                            isDefaultChecking = true
                        } else if newType != .checking {
                            isDefaultChecking = false
                        }
                        if newType != .mortgage {
                            mortgageOriginalPrincipalText = ""
                            mortgageTermYearsText = ""
                            mortgagePropertyTaxText = ""
                            mortgageInsuranceText = ""
                            mortgagePMIText = ""
                            mortgageEscrowText = ""
                        }
                    }
                    HStack {
                        Text(selectedType.isAsset ? "Balance" : "Amount Owed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormat.symbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if selectedType.isLiability {
                        Toggle("Has Due Date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                        }
                        Toggle("Include in Nest Egg", isOn: $includeInNetWorth)
                    }
                    if selectedType == .checking {
                        Toggle("Default Checking Account", isOn: $isDefaultChecking)
                    }
                }

                if selectedType.isLiability {
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

                if selectedType == .mortgage {
                    Section("Mortgage Details") {
                        currencyField("Original Principal", text: $mortgageOriginalPrincipalText)
                        HStack {
                            Text("Term")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("30", text: $mortgageTermYearsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("years")
                                .foregroundStyle(.secondary)
                        }
                        DatePicker("First Payment", selection: $mortgageFirstPaymentDate, displayedComponents: .date)
                        currencyField("Property Tax / Month", text: $mortgagePropertyTaxText)
                        currencyField("Insurance / Month", text: $mortgageInsuranceText)
                        currencyField("PMI / Month", text: $mortgagePMIText)
                        currencyField("Other Escrow / Month", text: $mortgageEscrowText)
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
            .onAppear {
                guard !hasPopulated else { return }
                populateIfEditing()
                hasPopulated = true
            }
        }
    }

    private func save() {
        guard isValid else {
            showValidationError = true
            return
        }
        let stored = selectedType.isAsset ? abs(balance) : -abs(balance)
        let resolvedDueDate = selectedType.isLiability && hasDueDate ? dueDate : nil
        if let account = editingAccount {
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.type = selectedType
            AccountBalanceService.applyBalanceEdit(oldBalance: loadedBalance, newBalance: stored, to: account, context: modelContext)
            account.notes = notes
            account.dueDate = resolvedDueDate
            account.annualPercentageRate = selectedType.isAsset ? nil : AmountParser.parse(aprText)
            account.minimumPayment = selectedType.isAsset ? nil : AmountParser.parse(minimumPaymentText)
            account.plannedExtraPayment = selectedType.isAsset ? nil : AmountParser.parse(extraPaymentText)
            applyMortgageFields(to: account)
            account.includeInNetWorth = selectedType.isAsset ? true : includeInNetWorth
            applyDefaultCheckingSelection(to: account)
        } else {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: selectedType,
                balance: stored,
                notes: notes
            )
            account.dueDate = resolvedDueDate
            account.annualPercentageRate = selectedType.isAsset ? nil : AmountParser.parse(aprText)
            account.minimumPayment = selectedType.isAsset ? nil : AmountParser.parse(minimumPaymentText)
            account.plannedExtraPayment = selectedType.isAsset ? nil : AmountParser.parse(extraPaymentText)
            applyMortgageFields(to: account)
            account.includeInNetWorth = selectedType.isAsset ? true : includeInNetWorth
            applyDefaultCheckingSelection(to: account)
            modelContext.insert(account)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let account = editingAccount else {
            isDefaultChecking = selectedType == .checking && !hasOtherDefaultCheckingAccount
            return
        }
        name = account.name
        selectedType = account.type
        balanceText = abs(account.balance).formatted(.number.precision(.fractionLength(2)).grouping(.never))
        loadedBalance = account.balance
        notes = account.notes
        hasDueDate = account.dueDate != nil
        dueDate = account.dueDate ?? Date.now
        aprText = account.annualPercentageRate.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        minimumPaymentText = account.minimumPayment.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        extraPaymentText = account.plannedExtraPayment.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        mortgageOriginalPrincipalText = account.mortgageOriginalPrincipal.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        mortgageTermYearsText = account.mortgageTermMonths.map { String($0 / 12) } ?? ""
        mortgageFirstPaymentDate = account.mortgageFirstPaymentDate ?? Date.now
        mortgagePropertyTaxText = account.mortgageMonthlyPropertyTax.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        mortgageInsuranceText = account.mortgageMonthlyInsurance.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        mortgagePMIText = account.mortgageMonthlyPMI.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        mortgageEscrowText = account.mortgageMonthlyEscrow.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        includeInNetWorth = account.includeInNetWorth
        isDefaultChecking = account.type == .checking && account.isDefaultChecking
    }

    private var hasOtherDefaultCheckingAccount: Bool {
        accounts.contains { account in
            account.type == .checking
                && account.isDefaultChecking
                && account.id != editingAccount?.id
        }
    }

    private func applyDefaultCheckingSelection(to account: Account) {
        guard selectedType == .checking, isDefaultChecking else {
            account.isDefaultChecking = false
            return
        }

        for other in accounts where other.id != account.id && other.type == .checking {
            other.isDefaultChecking = false
        }
        account.isDefaultChecking = true
    }

    private func applyMortgageFields(to account: Account) {
        guard selectedType == .mortgage else {
            account.mortgageOriginalPrincipal = nil
            account.mortgageTermMonths = nil
            account.mortgageFirstPaymentDate = nil
            account.mortgageMonthlyPropertyTax = nil
            account.mortgageMonthlyInsurance = nil
            account.mortgageMonthlyPMI = nil
            account.mortgageMonthlyEscrow = nil
            return
        }

        account.mortgageOriginalPrincipal = AmountParser.parse(mortgageOriginalPrincipalText)
        if let years = Int(mortgageTermYearsText.trimmingCharacters(in: .whitespaces)), years > 0 {
            account.mortgageTermMonths = years * 12
        } else {
            account.mortgageTermMonths = nil
        }
        account.mortgageFirstPaymentDate = mortgageFirstPaymentDate
        account.mortgageMonthlyPropertyTax = AmountParser.parse(mortgagePropertyTaxText)
        account.mortgageMonthlyInsurance = AmountParser.parse(mortgageInsuranceText)
        account.mortgageMonthlyPMI = AmountParser.parse(mortgagePMIText)
        account.mortgageMonthlyEscrow = AmountParser.parse(mortgageEscrowText)
    }

    private func currencyField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(CurrencyFormat.symbol)
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
