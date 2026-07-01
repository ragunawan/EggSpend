import SwiftUI
import SwiftData

struct AddEditCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCategories: [TransactionCategory]

    var editingCategory: TransactionCategory? = nil

    // MARK: - State

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var customIconName: String = ""
    @State private var selectedColorHex: String = "E67E22"
    @State private var customColorHex: String = ""
    @State private var typeFilterSelection: TypeFilterOption = .both
    @State private var isArchived: Bool = false

    // Alerts
    @State private var showDuplicateWarning = false
    @State private var showValidationError = false
    @State private var validationMessage = ""

    // MARK: - Constants

    private let suggestedIcons: [String] = [
        "fork.knife", "car.fill", "house.fill", "cart.fill", "creditcard",
        "gift.fill", "airplane", "bolt.fill", "tv.fill", "music.note",
        "book.fill", "cross.fill", "pawprint.fill", "dumbbell.fill", "leaf.fill",
        "briefcase.fill", "banknote", "chart.line.uptrend.xyaxis", "building.columns",
        "graduationcap.fill", "tshirt.fill", "fuelpump.fill", "bus.fill", "phone.fill",
        "wifi", "doc.fill", "wrench.fill", "dollarsign.circle.fill", "heart.fill", "star.fill"
    ]

    private let presetColors: [String] = [
        "E67E22", "27AE60", "3498DB", "9B59B6", "E74C3C",
        "F1C40F", "1ABC9C", "34495E", "E91E63", "FF5722",
        "795548", "607D8B", "D4820A", "2ECC71", "8E44AD"
    ]

    // MARK: - Computed

    private var isEditing: Bool { editingCategory != nil }

    private var effectiveIcon: String {
        let custom = customIconName.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? selectedIcon : custom
    }

    private var effectiveColorHex: String {
        let custom = customColorHex.trimmingCharacters(in: .whitespaces)
        return isValidHex(custom) ? custom : selectedColorHex
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !effectiveIcon.isEmpty
            && isValidHex(effectiveColorHex)
    }

    private func isValidHex(_ hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: .whitespaces).uppercased()
        guard cleaned.count == 6 else { return false }
        return cleaned.allSatisfy { $0.isHexDigit }
    }

    private func hasDuplicate() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let targetTypeFilter = typeFilterSelection.transactionType?.rawValue
        return allCategories.contains { cat in
            // Exclude self when editing
            if let editing = editingCategory, editing.id == cat.id { return false }
            return cat.name.caseInsensitiveCompare(trimmedName) == .orderedSame
                && cat.typeFilter == targetTypeFilter
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                iconSection
                colorSection
                typeSection
                if isEditing {
                    archiveSection
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!isFormValid)
                        .fontWeight(.semibold)
                }
            }
            .alert("Missing Information", isPresented: $showValidationError) {
                Button("OK") {}
            } message: {
                Text(validationMessage)
            }
            .alert("Duplicate Category", isPresented: $showDuplicateWarning) {
                Button("Save Anyway", role: .none) { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A category with this name and type already exists. Do you want to save it anyway?")
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Category name", text: $name)
                .autocorrectionDisabled(false)
                .textInputAutocapitalization(.words)
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            // Grid of suggested icons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(suggestedIcons, id: \.self) { symbol in
                    let isSelected = selectedIcon == symbol && customIconName.trimmingCharacters(in: .whitespaces).isEmpty
                    Button {
                        selectedIcon = symbol
                        customIconName = ""
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

            // Custom SF Symbol name field
            HStack {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                TextField("Custom SF Symbol name", text: $customIconName)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

                if !customIconName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Image(systemName: customIconName.trimmingCharacters(in: .whitespaces))
                        .foregroundStyle(Color.yolk)
                        .transition(.opacity)
                }
            }

            // Preview of effective icon
            if !effectiveIcon.isEmpty {
                HStack {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: effectiveIcon)
                        .font(.title2)
                        .foregroundStyle(Color(hex: effectiveColorHex) ?? Color.yolk)
                        .padding(8)
                        .background(
                            (Color(hex: effectiveColorHex) ?? Color.yolk).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Color") {
            // Color palette circles
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(presetColors, id: \.self) { hex in
                    let isSelected = selectedColorHex == hex && customColorHex.trimmingCharacters(in: .whitespaces).isEmpty
                    Button {
                        selectedColorHex = hex
                        customColorHex = ""
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

            // Custom hex entry
            HStack {
                Text("#")
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
                TextField("RRGGBB", text: $customColorHex)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.characters)
                    .font(.body.monospaced())
                    .onChange(of: customColorHex) { _, newValue in
                        // Clamp to 6 chars and strip non-hex
                        let filtered = newValue.uppercased().filter { $0.isHexDigit }
                        if filtered != newValue.uppercased() || newValue.count > 6 {
                            customColorHex = String(filtered.prefix(6))
                        }
                    }

                if isValidHex(customColorHex) {
                    Circle()
                        .fill(Color(hex: customColorHex) ?? .clear)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color(.systemFill), lineWidth: 1))
                        .transition(.opacity)
                } else if !customColorHex.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
    }

    private var typeSection: some View {
        Section("Applies To") {
            Picker("Type", selection: $typeFilterSelection) {
                ForEach(TypeFilterOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var archiveSection: some View {
        Section {
            Toggle("Archived", isOn: $isArchived)
                .tint(Color.twig)
        } header: {
            Text("Status")
        } footer: {
            Text("Archived categories are hidden from the transaction picker but their transaction history is preserved.")
        }
    }

    // MARK: - Logic

    private func populateIfEditing() {
        guard let cat = editingCategory else { return }
        name = cat.name
        selectedIcon = cat.icon
        selectedColorHex = cat.colorHex
        isArchived = cat.isArchived

        if let type = cat.appliesTo {
            typeFilterSelection = type == .income ? .incomeOnly : .expenseOnly
        } else {
            typeFilterSelection = .both
        }
    }

    private func attemptSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationMessage = "Please enter a name for the category."
            showValidationError = true
            return
        }
        guard !effectiveIcon.isEmpty else {
            validationMessage = "Please select or enter an icon."
            showValidationError = true
            return
        }
        guard isValidHex(effectiveColorHex) else {
            validationMessage = "Please enter a valid 6-character hex color code."
            showValidationError = true
            return
        }

        if hasDuplicate() {
            showDuplicateWarning = true
        } else {
            save()
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let typeFilter = typeFilterSelection.transactionType

        if let cat = editingCategory {
            // Edit mode: update in place
            cat.name = trimmedName
            cat.icon = effectiveIcon
            cat.colorHex = effectiveColorHex.uppercased()
            cat.typeFilter = typeFilter?.rawValue
            cat.isArchived = isArchived
        } else {
            // Create mode — append new categories after existing ones.
            let nextSortOrder = (allCategories.map(\.sortOrder).max() ?? -1) + 1
            let newCategory = TransactionCategory(
                name: trimmedName,
                icon: effectiveIcon,
                colorHex: effectiveColorHex.uppercased(),
                typeFilter: typeFilter,
                sortOrder: nextSortOrder
            )
            modelContext.insert(newCategory)
        }

        dismiss()
    }
}

// MARK: - TypeFilterOption

private enum TypeFilterOption: String, CaseIterable {
    case both       = "Both"
    case incomeOnly = "Income Only"
    case expenseOnly = "Expense Only"

    var label: String { rawValue }

    var transactionType: TransactionType? {
        switch self {
        case .both:        return nil
        case .incomeOnly:  return .income
        case .expenseOnly: return .expense
        }
    }
}

// MARK: - Preview

#Preview("Create") {
    AddEditCategoryView()
        .modelContainer(PersistenceController.previewContainer())
}

#Preview("Edit") {
    let container = PersistenceController.previewContainer()
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<TransactionCategory>()
    let categories = (try? context.fetch(descriptor)) ?? []
    let category = categories.first ?? TransactionCategory(
        name: "Food & Dining",
        icon: "fork.knife",
        colorHex: "E67E22",
        typeFilter: .expense
    )
    return AddEditCategoryView(editingCategory: category)
        .modelContainer(container)
}
