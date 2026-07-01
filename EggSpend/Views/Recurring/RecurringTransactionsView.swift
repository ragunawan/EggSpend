import SwiftUI
import SwiftData

struct RecurringTransactionsView: View {
    @Query(sort: \RecurringTransaction.nextDueDate) private var items: [RecurringTransaction]
    @Environment(\.modelContext) private var modelContext
    @State private var showAdd = false
    @State private var editingItem: RecurringTransaction? = nil

    private var dueSoon: [RecurringTransaction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return items.filter { $0.isActive && $0.nextDueDate <= cutoff }
    }
    private var active: [RecurringTransaction] { items.filter(\.isActive) }
    private var inactive: [RecurringTransaction] { items.filter { !$0.isActive } }

    var body: some View {
        ZStack {
            AnimatedCanopyBackground()

            List {
                if !dueSoon.isEmpty {
                    Section {
                        ForEach(dueSoon) { item in
                            recurringRow(item, accent: Color.yolk)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Label("Due This Week", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.yolk)
                    }
                }

                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { item in
                            recurringRow(item, accent: Color.nestLeafGreen)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .leading) {
                                    Button("Pause", systemImage: "pause.circle.fill") {
                                        item.isActive = false
                                        NotificationScheduler.syncReminder(for: item)
                                    }
                                    .tint(.orange)
                                }
                        }
                        .onDelete { offsets in delete(from: active, at: offsets) }
                    }
                }

                if !inactive.isEmpty {
                    Section("Paused") {
                        ForEach(inactive) { item in
                            recurringRow(item, accent: .secondary)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .leading) {
                                    Button("Resume", systemImage: "play.circle.fill") {
                                        item.isActive = true
                                        NotificationScheduler.syncReminder(for: item)
                                    }
                                    .tint(.green)
                                }
                        }
                        .onDelete { offsets in delete(from: inactive, at: offsets) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Recurring")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.yolk)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Recurring Transactions")
                    } icon: {
                        Image(systemName: "arrow.clockwise.circle").symbolEffect(.pulse)
                    }
                } description: {
                    Text("Add bills, subscriptions, or regular income.")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddRecurringTransactionView() }
        .sheet(item: $editingItem) { item in AddRecurringTransactionView(editingItem: item) }
    }

    @ViewBuilder
    private func recurringRow(_ item: RecurringTransaction, accent: Color) -> some View {
        Button { editingItem = item } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((item.category?.color ?? (item.type == .income ? Color.eggBlue : Color.yolk)).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: item.category?.icon ?? item.frequency.icon)
                        .foregroundStyle(item.category?.color ?? accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(item.frequency.rawValue)
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(accent)
                        Text("Next: \(item.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let account = item.account {
                        Label(account.name, systemImage: account.type.icon)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                AmountLabel(amount: item.amount, type: item.type, font: .callout)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func delete(from list: [RecurringTransaction], at offsets: IndexSet) {
        for i in offsets {
            NotificationScheduler.cancelReminder(for: list[i].id)
            modelContext.delete(list[i])
        }
    }
}

#Preview {
    NavigationStack {
        RecurringTransactionsView()
            .modelContainer(for: [RecurringTransaction.self, TransactionCategory.self], inMemory: true)
    }
}
