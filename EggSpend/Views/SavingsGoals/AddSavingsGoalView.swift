import SwiftUI
import SwiftData

struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]

    var editingGoal: SavingsGoal? = nil

    // MARK: - State

    @State private var name = ""
    @State private var targetAmountText = ""
    @State private var currentAmountText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var linkedAccount: Account? = nil
    @State private var notes = ""
    @State private var selectedIcon = "leaf.fill"
    @State private var selectedColorHex = "D4820A"
    @State private var status: SavingsGoalStatus = .active
    @State private var showValidationError = false
    @State private var validationMessage = ""

    private let suggestedIcons: [String] = [
        "leaf.fill", "umbrella.fill", "airplane", "house.fill", "car.fill",
        "graduationcap.fill", "gift.fill", "heart.fill", "star.fill",
        "banknote", "laptopcomputer", "camera.fill", "ring.circle.fill",
        "figure.2.and.child.holdinghands", "cross.case.fill", "pawprint.fill"
    ]

    private let presetColors: [String] = [
        "D4820A", "5BA4C1", "3D7A3B", "9B59B6", "E74C3C",
        "F1C40F", "1ABC9C", "5C3D1E", "E91E63", "607D8B"
    ]

    // MARK: - Computed

    private var isEditing: Bool { editingGoal != nil }
    private var targetAmount: Double { AmountParser.parse(targetAmountText) ?? 0 }
    private var currentAmount: Double { AmountParser.parse(currentAmountText) ?? 0 }
    private var tracksLinkedAccount: Bool { linkedAccount != nil }
    // Archived accounts are hidden from the picker unless already linked (editing an
    // existing goal), otherwise the picker would render blank.
    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0 == linkedAccount }
    }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Name (e.g. Emergency Fund)", text: $name)
                    HStack {
                        Text("Target").foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormat.symbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $targetAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Picker("Linked Account", selection: $linkedAccount) {
                        Text("None — track manually").tag(Optional<Account>.none)
                        ForEach(availableAccounts) { account in
                            Label(account.name, systemImage: account.type.icon).tag(Optional(account))
                        }
                    }

                    if tracksLinkedAccount {
                        HStack {
                            Text("Current Balance").foregroundStyle(.secondary)
                            Spacer()
                            Text(linkedAccount?.balance ?? 0, format: .currency(code: CurrencyFormat.code))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        HStack {
                            Text("Current Amount").foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormat.symbol).foregroundStyle(.secondary)
                            TextField("0.00", text: $currentAmountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Progress")
                } footer: {
                    Text(tracksLinkedAccount
                         ? "Progress is derived automatically from this account's balance."
                         : "Enter how much you've saved toward this goal so far.")
                }

                Section("Target Date") {
                    Toggle("Set a target date", isOn: $hasTargetDate.animation())
                    if hasTargetDate {
                        DatePicker("Target Date", selection: $targetDate, displayedComponents: .date)
                    }
                }

                iconSection
                colorSection

                Section("Notes") {
                    TextField("Optional note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if isEditing {
                    Section("Status") {
                        Picker("Status", selection: $status) {
                            ForEach(SavingsGoalStatus.allCases, id: \.self) { s in
                                Label(s.rawValue, systemImage: s.icon).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }.disabled(!isValid)
                }
            }
            .alert("Missing Information", isPresented: $showValidationError) {
                Button("OK") {}
            } message: {
                Text(validationMessage)
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Icon & Color sections

    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(suggestedIcons, id: \.self) { symbol in
                    let isSelected = selectedIcon == symbol
                    Button {
                        selectedIcon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.yolk : .primary)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.yolk.opacity(0.15) : Color(.systemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.yolk : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(presetColors, id: \.self) { hex in
                    let isSelected = selectedColorHex == hex
                    Button {
                        selectedColorHex = hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 40, height: 40)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.primary.opacity(0.6) : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Logic

    private func attemptSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationMessage = "Please enter a name for this goal."
            showValidationError = true
            return
        }
        guard targetAmount > 0 else {
            validationMessage = "Please enter a target amount greater than zero."
            showValidationError = true
            return
        }
        save()
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let resolvedDate = hasTargetDate ? targetDate : nil

        if let goal = editingGoal {
            goal.name = trimmedName
            goal.targetAmount = targetAmount
            goal.manualCurrentAmount = max(0, currentAmount)
            goal.targetDate = resolvedDate
            goal.linkedAccount = linkedAccount
            goal.notes = notes
            goal.icon = selectedIcon
            goal.colorHex = selectedColorHex
            goal.status = status
        } else {
            let goal = SavingsGoal(
                name: trimmedName,
                targetAmount: targetAmount,
                currentAmount: currentAmount,
                targetDate: resolvedDate,
                linkedAccount: linkedAccount,
                notes: notes,
                colorHex: selectedColorHex,
                icon: selectedIcon
            )
            modelContext.insert(goal)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let goal = editingGoal else { return }
        name = goal.name
        targetAmountText = goal.targetAmount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
        currentAmountText = goal.manualCurrentAmount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
        if let date = goal.targetDate {
            hasTargetDate = true
            targetDate = date
        }
        linkedAccount = goal.linkedAccount
        notes = goal.notes
        selectedIcon = goal.icon
        selectedColorHex = goal.colorHex
        status = goal.status
    }
}

#Preview("Create") {
    AddSavingsGoalView()
        .modelContainer(PersistenceController.previewContainer())
}

#Preview("Edit") {
    let container = PersistenceController.previewContainer()
    let context = ModelContext(container)
    let goals = (try? context.fetch(FetchDescriptor<SavingsGoal>())) ?? []
    let goal = goals.first ?? SavingsGoal(name: "Emergency Fund", targetAmount: 20_000)
    return AddSavingsGoalView(editingGoal: goal)
        .modelContainer(container)
}
