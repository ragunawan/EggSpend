import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            amountSection
            detailsSection
            if !transaction.notes.isEmpty {
                notesSection
            }
            metaSection
        }
        .navigationTitle(transaction.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) { showDeleteConfirmation = true }
            }
        }
        .confirmationDialog("Delete Transaction?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAndDismiss() }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showEdit) {
            AddTransactionView(editingTransaction: transaction)
        }
    }

    private var amountSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: transaction.type.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(transaction.type == .income ? .green : .red)
                    Text(transaction.amount, format: .currency(code: "USD"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(transaction.type.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Date") {
                Text(transaction.date, style: .date)
            }
            if let account = transaction.account {
                LabeledContent("Account") {
                    Label(account.name, systemImage: account.type.icon)
                        .foregroundStyle(.secondary)
                }
            }
            if let category = transaction.category {
                LabeledContent("Category") {
                    CategoryBadgeView(category: category)
                }
            }
            LabeledContent("Title") {
                Text(transaction.title)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Text(transaction.notes)
                .foregroundStyle(.secondary)
        }
    }

    private var metaSection: some View {
        Section {
            LabeledContent("Added") {
                Text(transaction.createdAt, style: .date)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteAndDismiss() {
        AccountBalanceService.reverse(transaction, from: transaction.account)
        modelContext.delete(transaction)
        BudgetAlertCoordinator.checkBudgets(context: modelContext)
        dismiss()
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    let context = ModelContext(container)
    let tx = Transaction(title: "Coffee", amount: 5.50, type: .expense, notes: "Morning brew at Blue Bottle.")
    context.insert(tx)
    return NavigationStack {
        TransactionDetailView(transaction: tx)
    }
    .modelContainer(container)
}
