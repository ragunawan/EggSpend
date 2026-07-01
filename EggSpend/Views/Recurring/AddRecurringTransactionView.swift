import SwiftUI
import SwiftData

struct AddRecurringTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [TransactionCategory]

    var editingItem: RecurringTransaction? = nil

    @State private var title = ""
    @State private var amountText = ""
    @State private var selectedType: TransactionType = .expense
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now.addingTimeInterval(60 * 60 * 24 * 365)
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var notes = ""
    @State private var isActive = true
    @State private var reminderEnabled = false
    @State private var reminderDaysBefore = 1
    @State private var showValidationError = false

    private var isEditing: Bool { editingItem != nil }
    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    private var availableCategories: [TransactionCategory] {
        categories.filter { $0.appliesTo == nil || $0.appliesTo == selectedType }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, _ in
                        if let cat = selectedCategory, cat.appliesTo != nil, cat.appliesTo != selectedType {
                            selectedCategory = nil
                        }
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad)
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                            Label(freq.rawValue, systemImage: freq.icon).tag(freq)
                        }
                    }
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Has End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate,
                                   in: startDate..., displayedComponents: .date)
                    }
                }

                Section("Reminder") {
                    Toggle("Remind Me", isOn: $reminderEnabled)
                        .onChange(of: reminderEnabled) { _, newValue in
                            if newValue {
                                NotificationScheduler.requestAuthorizationIfNeeded { granted in
                                    DispatchQueue.main.async {
                                        if !granted { reminderEnabled = false }
                                    }
                                }
                            }
                        }
                    if reminderEnabled {
                        Stepper(
                            "\(reminderDaysBefore) day\(reminderDaysBefore == 1 ? "" : "s") before",
                            value: $reminderDaysBefore,
                            in: 1...14
                        )
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(availableCategories) { cat in
                            Label(cat.name, systemImage: cat.icon).tag(Optional(cat))
                        }
                        Text("None").tag(Optional<TransactionCategory>.none)
                    }
                }

                Section("Notes") {
                    TextField("Optional note", text: $notes, axis: .vertical).lineLimit(2...4)
                }

                if isEditing {
                    Section { Toggle("Active", isOn: $isActive) }
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
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
                Text("Please enter a title and an amount greater than zero.")
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func save() {
        guard isValid else { showValidationError = true; return }
        let item: RecurringTransaction
        if let editingItem {
            item = editingItem
            item.title = title.trimmingCharacters(in: .whitespaces)
            item.amount = amount
            item.type = selectedType
            item.frequency = frequency
            item.startDate = startDate
            item.endDate = hasEndDate ? endDate : nil
            item.category = selectedCategory
            item.notes = notes
            item.isActive = isActive
        } else {
            item = RecurringTransaction(
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount,
                type: selectedType,
                frequency: frequency,
                startDate: startDate,
                category: selectedCategory,
                notes: notes
            )
            item.endDate = hasEndDate ? endDate : nil
            modelContext.insert(item)
        }
        item.reminderEnabled = reminderEnabled
        item.reminderDaysBefore = reminderDaysBefore
        NotificationScheduler.syncReminder(for: item)
        dismiss()
    }

    private func populateIfEditing() {
        guard let item = editingItem else { return }
        title = item.title
        amountText = String(format: "%.2f", item.amount)
        selectedType = item.type
        frequency = item.frequency
        startDate = item.startDate
        hasEndDate = item.endDate != nil
        endDate = item.endDate ?? Date.now.addingTimeInterval(60 * 60 * 24 * 365)
        selectedCategory = item.category
        notes = item.notes
        isActive = item.isActive
        reminderEnabled = item.reminderEnabled
        reminderDaysBefore = item.reminderDaysBefore
    }
}

#Preview {
    AddRecurringTransactionView()
        .modelContainer(for: [RecurringTransaction.self, TransactionCategory.self], inMemory: true)
}
