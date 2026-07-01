import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \Transaction.date) private var transactions: [Transaction]

    @State private var showAddCategory = false
    @State private var editingCategory: TransactionCategory? = nil
    @State private var categoryToDelete: TransactionCategory? = nil
    @State private var showDeleteConfirmation = false

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

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient.nestCanopy.ignoresSafeArea()

            Group {
                if categories.isEmpty {
                    ContentUnavailableView {
                        Label("No categories yet", systemImage: "tag")
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                categoryToDelete = category
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                editingCategory = category
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryManagementView()
    }
    .modelContainer(PersistenceController.previewContainer())
}
