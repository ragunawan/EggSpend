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
                    HStack {
                        Text(selectedType.isAsset ? "Balance" : "Amount Owed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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
        if let account = editingAccount {
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.type = selectedType
            account.balance = stored
            account.notes = notes
        } else {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: selectedType,
                balance: stored,
                notes: notes
            )
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
    }
}

#Preview {
    AddAccountView()
        .modelContainer(PersistenceController.previewContainer())
}
