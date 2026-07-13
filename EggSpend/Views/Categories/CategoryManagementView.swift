import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \Transaction.date) private var transactions: [Transaction]
    @Query private var categoryRules: [CategoryRule]

    @State private var showAddCategory = false
    @State private var editingCategory: TransactionCategory? = nil
    @State private var categoryToDelete: TransactionCategory? = nil
    @State private var showDeleteConfirmation = false
    @State private var rulePatternToDelete: String? = nil
    @State private var showDeleteRuleConfirmation = false

    // MARK: - Sections

    private var incomeCategories: [TransactionCategory] {
        categories.filter { $0.appliesTo == .income }
    }

    private var expenseCategories: [TransactionCategory] {
        categories.filter { $0.appliesTo == .expense }
    }

    private var bothCategories: [TransactionCategory] {
        categories.filter { $0.appliesTo == nil }
    }

    // MARK: - Helpers

    private func transactionCount(for category: TransactionCategory) -> Int {
        transactions.filter { $0.category?.id == category.id }.count
    }

    /// One row per distinct normalized pattern, showing only the most
    /// recently recorded rule (duplicate rows per pattern are tolerated by
    /// design — see `CategoryRule`'s doc comment).
    private var groupedRules: [(pattern: String, latest: CategoryRule)] {
        Dictionary(grouping: categoryRules, by: \.normalizedPattern)
            .compactMap { pattern, rows in rows.max(by: { $0.createdAt < $1.createdAt }).map { (pattern, $0) } }
            .sorted { $0.pattern < $1.pattern }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            NestBackground()

            Group {
                if categories.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No categories yet")
                        } icon: {
                            Image(systemName: "tag").symbolEffect(.pulse)
                        }
                    } description: {
                        Text("Tap + to create your first category.")
                    }
                } else {
                    List {
                        if !incomeCategories.isEmpty {
                            Section("Income") {
                                ForEach(incomeCategories) { category in
                                    categoryRow(category)
                                        .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !expenseCategories.isEmpty {
                            Section("Expense") {
                                ForEach(expenseCategories) { category in
                                    categoryRow(category)
                                        .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !bothCategories.isEmpty {
                            Section("Both / Uncategorized") {
                                ForEach(bothCategories) { category in
                                    categoryRow(category)
                                        .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !groupedRules.isEmpty {
                            Section {
                                ForEach(groupedRules, id: \.pattern) { entry in
                                    ruleRow(entry)
                                        .listRowBackground(Color.clear)
                                }
                            } header: {
                                Text("Auto-Categorization Rules")
                            } footer: {
                                Text("Rules are learned automatically when you categorize a transaction. Deleting a rule stops future auto-assignment for that payee.")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddCategory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.yolk)
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            AddEditCategoryView()
        }
        .sheet(item: $editingCategory) { category in
            AddEditCategoryView(editingCategory: category)
        }
        .confirmationDialog(
            "Delete Category",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    modelContext.delete(category)
                    categoryToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            if let name = categoryToDelete?.name {
                Text("Delete \"\(name)\"? Transactions in this category will not be deleted, but will lose their category assignment.")
            }
        }
        .confirmationDialog(
            "Delete Rule",
            isPresented: $showDeleteRuleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pattern = rulePatternToDelete {
                    CategoryRuleEngine.deleteAllRules(matching: pattern, in: modelContext)
                    rulePatternToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                rulePatternToDelete = nil
            }
        } message: {
            Text("This payee will no longer be auto-categorized. Future transactions with this payee will start uncategorized again.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func categoryRow(_ category: TransactionCategory) -> some View {
        Button {
            editingCategory = category
        } label: {
            HStack(spacing: 12) {
                // Icon + color badge
                CategoryBadgeView(category: category, compact: true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(category.name)
                            .font(.body)
                            .foregroundStyle(.primary)

                        if category.isArchived {
                            Text("Archived")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.twig, in: Capsule())
                        }
                    }

                    let count = transactionCount(for: category)
                    Text(count == 1 ? "1 transaction" : "\(count) transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Type badge pill
                if let type = category.appliesTo {
                    Text(type == .income ? "Income" : "Expense")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(type == .income ? Color.nestLeafGreen : Color.yolk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (type == .income ? Color.nestLeafGreen : Color.yolk).opacity(0.15),
                            in: Capsule()
                        )
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                category.isArchived.toggle()
            } label: {
                Label(
                    category.isArchived ? "Unarchive" : "Archive",
                    systemImage: category.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .tint(Color.warningTone)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                categoryToDelete = category
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color.negative)

            Button {
                editingCategory = category
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color.info)
        }
    }

    // MARK: - Rule row

    @ViewBuilder
    private func ruleRow(_ entry: (pattern: String, latest: CategoryRule)) -> some View {
        let resolvedCategory = categories.first { $0.id == entry.latest.categoryID }

        HStack(spacing: 12) {
            if let resolvedCategory {
                CategoryBadgeView(category: resolvedCategory, compact: true)
            } else {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Color.twig)
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.pattern)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(resolvedCategory?.name ?? "No category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                rulePatternToDelete = entry.pattern
                showDeleteRuleConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color.negative)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryManagementView()
    }
    .modelContainer(PersistenceController.previewContainer())
}
