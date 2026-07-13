import SwiftUI
import SwiftData

struct QuickAddDraft {
    let amountText: String
    let entryKind: EntryKind
    let title: String
    let category: TransactionCategory?
    let account: Account?
    let date: Date
}

struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var categoryRules: [CategoryRule]

    @AppStorage("lastUsedAccountID") private var lastUsedAccountID = ""

    @State private var amountText = ""
    @State private var entryKind: EntryKind = .expense
    @State private var title = ""
    @State private var selectedCategory: TransactionCategory?
    @State private var selectedAccount: Account?
    @State private var date = Date.now
    @State private var isEnteringTitle = false

    var initialKind: EntryKind = .expense
    var onMoreOptions: ((QuickAddDraft) -> Void)?

    private var amount: Double {
        AmountParser.parse(amountText) ?? 0
    }

    private var draft: QuickAddDraft {
        QuickAddDraft(
            amountText: amountText,
            entryKind: entryKind,
            title: title,
            category: selectedCategory,
            account: selectedAccount,
            date: date
        )
    }

    private var isValid: Bool {
        amount > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestions: [MerchantSuggestion] {
        MerchantSuggestion.build(from: transactions)
    }

    private var availableCategories: [TransactionCategory] {
        guard let type = entryKind.transactionType else { return [] }
        return categories
            .filter { !$0.isArchived && ($0.appliesTo == nil || $0.appliesTo == type) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.md) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 36, height: 5)
                    .accessibilityHidden(true)

                amountDisplay
                typePicker
                suggestionChips

                if isEnteringTitle || suggestions.isEmpty {
                    titleField
                }

                defaultsRow
                CurrencyKeypadView(amountText: $amountText)

                Button {
                    onMoreOptions?(draft)
                    dismiss()
                } label: {
                    Label("More options", systemImage: "chevron.down")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(onMoreOptions == nil)
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Save transaction")
                }
            }
            .onAppear(perform: configureInitialState)
            .onChange(of: entryKind) { _, newKind in
                if let selectedCategory, selectedCategory.appliesTo != nil, selectedCategory.appliesTo != newKind.transactionType {
                    self.selectedCategory = nil
                }
            }
        }
    }

    private var amountDisplay: some View {
        AmountText(amount: amount, type: entryKind.transactionType ?? .expense, style: .hero)
            .contentTransition(.numericText())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var typePicker: some View {
        Picker("Type", selection: $entryKind) {
            Text("Expense").tag(EntryKind.expense)
            Text("Income").tag(EntryKind.income)
        }
        .pickerStyle(.segmented)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                Button {
                    isEnteringTitle = true
                } label: {
                    Label(title.isEmpty ? "Title" : title, systemImage: "text.cursor")
                        .lineLimit(1)
                }
                .buttonStyle(QuickAddChipStyle(isSelected: isEnteringTitle || !title.isEmpty))

                ForEach(suggestions) { suggestion in
                    Button {
                        apply(suggestion)
                    } label: {
                        Text(suggestion.title)
                            .lineLimit(1)
                    }
                    .buttonStyle(QuickAddChipStyle(isSelected: CSVParser.normalizedTitle(title) == suggestion.id))
                    .accessibilityHint("Fills title and category")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var titleField: some View {
        TextField("Title", text: $title)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onSubmit { prefillCategoryForTitle() }
    }

    private var defaultsRow: some View {
        HStack(spacing: Space.sm) {
            Menu {
                Button("None") { selectedCategory = nil }
                ForEach(availableCategories) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
            } label: {
                QuickAddPillLabel(
                    title: selectedCategory?.name ?? "Category",
                    systemImage: selectedCategory?.icon ?? "tag"
                )
            }

            if !availableAccounts.isEmpty {
                Menu {
                    Button("None") { selectedAccount = nil }
                    ForEach(availableAccounts) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            Label(account.name, systemImage: account.type.icon)
                        }
                    }
                } label: {
                    QuickAddPillLabel(
                        title: selectedAccount?.name ?? "Account",
                        systemImage: selectedAccount?.type.icon ?? "creditcard"
                    )
                }
            }

            Menu {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            } label: {
                QuickAddPillLabel(title: date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
        }
    }

    private func configureInitialState() {
        entryKind = initialKind == .income ? .income : .expense
        resolveLastUsedAccount()
    }

    private func resolveLastUsedAccount() {
        guard !lastUsedAccountID.isEmpty, let id = UUID(uuidString: lastUsedAccountID) else {
            selectedAccount = nil
            return
        }
        guard let account = availableAccounts.first(where: { $0.id == id }) else {
            lastUsedAccountID = ""
            selectedAccount = nil
            return
        }
        selectedAccount = account
    }

    private func apply(_ suggestion: MerchantSuggestion) {
        title = suggestion.title
        entryKind = suggestion.type == .income ? .income : .expense
        isEnteringTitle = false
        selectedCategory = resolvedCategory(for: suggestion)
        if let account = suggestion.account, !account.isArchived {
            selectedAccount = account
        }
    }

    private func resolvedCategory(for suggestion: MerchantSuggestion) -> TransactionCategory? {
        let ruleCategory = CategoryRuleEngine.categoryFor(title: suggestion.title, rules: categoryRules, categories: categories)
        return categoryAllowed(ruleCategory) ? ruleCategory : categoryAllowed(suggestion.category) ? suggestion.category : nil
    }

    private func prefillCategoryForTitle() {
        let ruleCategory = CategoryRuleEngine.categoryFor(title: title, rules: categoryRules, categories: categories)
        if categoryAllowed(ruleCategory) {
            selectedCategory = ruleCategory
        }
    }

    private func categoryAllowed(_ category: TransactionCategory?) -> Bool {
        guard let category else { return false }
        guard !category.isArchived else { return false }
        return category.appliesTo == nil || category.appliesTo == entryKind.transactionType
    }

    private func save() {
        guard let type = entryKind.transactionType, isValid else { return }
        TransactionEntryService.createTransaction(
            title: title,
            amount: amount,
            date: date,
            type: type,
            category: selectedCategory,
            account: selectedAccount,
            notes: "",
            context: modelContext
        )
        if let selectedAccount {
            lastUsedAccountID = selectedAccount.id.uuidString
        }
        dismiss()
    }
}

private struct QuickAddPillLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private struct QuickAddChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .background(
                isSelected ? Color.yolk.opacity(0.18) : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.nestBrown : .primary)
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.yolk.opacity(0.5) : Color.primary.opacity(0.08))
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

#Preview {
    QuickAddSheet()
        .modelContainer(PersistenceController.previewContainer())
}
