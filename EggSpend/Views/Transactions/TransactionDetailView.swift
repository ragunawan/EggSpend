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
                        .foregroundStyle(transaction.type == .income ? Color.positive : Color.negative)
                    Text(transaction.amount, format: .currency(code: CurrencyFormat.code))
                        .font(NestType.hero)
                    Text(transaction.type.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, Space.sm)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            detailRow("Date") {
                Text(transaction.date, style: .date)
            }
            if let account = transaction.account {
                detailRow("Account") {
                    HStack(spacing: Space.sm) {
                        Image(systemName: account.type.icon)
                        Text(account.name)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if let category = transaction.category {
                detailRow("Category") {
                    CategoryBadgeView(category: category)
                }
            }
            if transaction.type == .expense, let budget = transaction.budget {
                detailRow("Budget") {
                    Label(budget.name, systemImage: budget.period.icon)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            detailRow("Payee") {
                Text(transaction.title)
                    .lineLimit(1)
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
            detailRow("Added") {
                Text(transaction.createdAt, style: .date)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow<Value: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .center, spacing: Space.md) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: Space.md)
            value()
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 28)
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
