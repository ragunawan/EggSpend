import SwiftUI
import SwiftData

struct TransferDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transfer: Transfer

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            amountSection
            detailsSection
            if !transfer.notes.isEmpty {
                notesSection
            }
            metaSection
        }
        .navigationTitle("Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) { showDeleteConfirmation = true }
            }
        }
        .confirmationDialog("Delete Transfer?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAndDismiss() }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showEdit) {
            AddTransactionView(editingTransfer: transfer)
        }
    }

    private var amountSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.twig)
                    Text(transfer.amount, format: .currency(code: CurrencyFormat.code))
                        .font(NestType.hero)
                    Text("Transfer")
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
            LabeledContent("Date") {
                Text(transfer.date, style: .date)
            }
            LabeledContent("From") {
                if let account = transfer.fromAccount {
                    Label(account.name, systemImage: account.type.icon)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Deleted account").foregroundStyle(.secondary)
                }
            }
            LabeledContent("To") {
                if let account = transfer.toAccount {
                    Label(account.name, systemImage: account.type.icon)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Deleted account").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Text(transfer.notes)
                .foregroundStyle(.secondary)
        }
    }

    private var metaSection: some View {
        Section {
            LabeledContent("Added") {
                Text(transfer.createdAt, style: .date)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteAndDismiss() {
        TransferBalanceService.reverse(transfer)
        modelContext.delete(transfer)
        dismiss()
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    let context = ModelContext(container)
    let checking = Account(name: "Checking", type: .checking, balance: 1000)
    let savings = Account(name: "Savings", type: .savings, balance: 500)
    context.insert(checking)
    context.insert(savings)
    let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings, notes: "Monthly savings top-up.")
    context.insert(transfer)
    return NavigationStack {
        TransferDetailView(transfer: transfer)
    }
    .modelContainer(container)
}
