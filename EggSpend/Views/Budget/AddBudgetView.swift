import SwiftUI
import SwiftData

struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [TransactionCategory]

    var editingBudget: Budget? = nil

    @State private var name = ""
    @State private var amountText = ""
    @State private var period: BudgetPeriod = .monthly
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var isActive = true
    @State private var alertsEnabled = false
    @State private var createAsSavingsGoal = false
    @State private var showValidationError = false

    private var isEditing: Bool { editingBudget != nil }
    private var amount: Double { AmountParser.parse(amountText) ?? 0 }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budget Details") {
                    TextField("Name (e.g. Groceries)", text: $name)
                    HStack {
                        Text(CurrencyFormat.symbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad)
                    }
                    if !createAsSavingsGoal {
                        Picker("Period", selection: $period) {
                            ForEach(BudgetPeriod.allCases, id: \.self) { p in
                                Label(p.rawValue, systemImage: p.icon).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if !isEditing {
                    Section {
                        Toggle("Create as Savings Goal", isOn: $createAsSavingsGoal.animation())
                    } footer: {
                        Text("Savings goals track progress toward a target instead of spending against a limit.")
                    }
                }

                if !createAsSavingsGoal {
                    Section {
                        Toggle("Alert Near Limit & When Exceeded", isOn: $alertsEnabled)
                            .onChange(of: alertsEnabled) { _, newValue in
                                if newValue {
                                    NotificationScheduler.requestAuthorizationIfNeeded { granted in
                                        DispatchQueue.main.async {
                                            if !granted { alertsEnabled = false }
                                        }
                                    }
                                }
                            }
                    } footer: {
                        Text("Notifies you at 80% and 100% of this budget's limit.")
                    }

                    Section("Category (optional)") {
                        Picker("Category", selection: $selectedCategory) {
                            Text("All Expenses").tag(Optional<TransactionCategory>.none)
                            ForEach(categories.filter { $0.appliesTo == nil || $0.appliesTo == .expense }.sorted { $0.sortOrder < $1.sortOrder }) { cat in
                                Label(cat.name, systemImage: cat.icon).tag(Optional(cat))
                            }
                        }
                    }
                }

                if isEditing {
                    Section {
                        Toggle("Active", isOn: $isActive)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Budget" : (createAsSavingsGoal ? "New Savings Goal" : "New Budget Egg"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .alert("Missing Information", isPresented: $showValidationError) {
                Button("OK") {}
            } message: {
                Text("Please enter a name and an amount greater than zero.")
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func save() {
        guard isValid else { showValidationError = true; return }
        if let b = editingBudget {
            b.name = name.trimmingCharacters(in: .whitespaces)
            b.limitAmount = amount
            b.period = period
            b.category = selectedCategory
            b.isActive = isActive
            b.alertsEnabled = alertsEnabled
        } else if createAsSavingsGoal {
            let goal = SavingsGoal(
                name: name.trimmingCharacters(in: .whitespaces),
                targetAmount: amount,
                colorHex: selectedCategory?.colorHex ?? "D4820A",
                icon: selectedCategory?.icon ?? "leaf.fill"
            )
            modelContext.insert(goal)
        } else {
            let budget = Budget(
                name: name.trimmingCharacters(in: .whitespaces),
                limitAmount: amount,
                period: period,
                category: selectedCategory,
                colorHex: selectedCategory?.colorHex ?? "D4820A"
            )
            budget.alertsEnabled = alertsEnabled
            modelContext.insert(budget)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let b = editingBudget else { return }
        name = b.name
        amountText = b.limitAmount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
        period = b.period
        selectedCategory = b.category
        isActive = b.isActive
        alertsEnabled = b.alertsEnabled
    }
}

#Preview {
    AddBudgetView()
        .modelContainer(for: [Budget.self, SavingsGoal.self, TransactionCategory.self], inMemory: true)
}
