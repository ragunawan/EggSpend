import SwiftUI
import SwiftData

/// Compact sheet for the advanced transaction filters (category, account, date
/// range, amount range, and recurring-generated). Edits a local draft and only
/// writes back to `filter` when the user taps Apply.
struct TransactionFilterView: View {
    @Binding var filter: TransactionFilter
    @Binding var hideTransfers: Bool
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TransactionCategory.sortOrder) private var allCategories: [TransactionCategory]
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var draft: TransactionFilter
    @State private var draftHideTransfers: Bool
    @State private var minAmountText: String
    @State private var maxAmountText: String

    init(filter: Binding<TransactionFilter>, hideTransfers: Binding<Bool>) {
        _filter = filter
        _hideTransfers = hideTransfers
        let initial = filter.wrappedValue
        _draft = State(initialValue: initial)
        _draftHideTransfers = State(initialValue: hideTransfers.wrappedValue)
        _minAmountText = State(initialValue: initial.minAmount.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "")
        _maxAmountText = State(initialValue: initial.maxAmount.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "")
    }

    private var activeCategories: [TransactionCategory] {
        allCategories.filter { !$0.isArchived }
    }

    private var hasUnappliedDraft: Bool {
        draft.isActive || draftHideTransfers || !minAmountText.isEmpty || !maxAmountText.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedCanopyBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        typeSection
                        if !activeCategories.isEmpty { categorySection }
                        accountSection
                        dateRangeSection
                        amountRangeSection
                        recurringSection
                        transfersSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("\(draft.activeCount) active")
                .font(.subheadline)
                .foregroundStyle(Color.twig)
            Spacer()
            if hasUnappliedDraft {
                Button("Reset", role: .destructive) {
                    draft.reset()
                    draftHideTransfers = false
                    minAmountText = ""
                    maxAmountText = ""
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.yolk)
            }
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        FilterSectionCard(title: "Type", systemImage: "arrow.left.arrow.right") {
            Picker("Type", selection: $draft.type) {
                Text("All").tag(Optional<TransactionType>.none)
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        FilterSectionCard(title: "Category", systemImage: "tag") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeCategories) { category in
                        FilterOptionChip(
                            label: category.name,
                            icon: category.icon,
                            selected: draft.categoryIDs.contains(category.id)
                        ) {
                            toggle(category.id, in: &draft.categoryIDs)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        FilterSectionCard(title: "Account", systemImage: "building.columns") {
            if accounts.isEmpty {
                Text("No accounts added yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(accounts) { account in
                            FilterOptionChip(
                                label: account.name,
                                icon: account.type.icon,
                                selected: draft.accountIDs.contains(account.id)
                            ) {
                                toggle(account.id, in: &draft.accountIDs)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Date Range

    private var startDateBinding: Binding<Date> {
        Binding(get: { draft.startDate ?? .now }, set: { draft.startDate = $0 })
    }

    private var endDateBinding: Binding<Date> {
        Binding(get: { draft.endDate ?? .now }, set: { draft.endDate = $0 })
    }

    private var startDateEnabled: Binding<Bool> {
        Binding(
            get: { draft.startDate != nil },
            set: { enabled in draft.startDate = enabled ? .now : nil }
        )
    }

    private var endDateEnabled: Binding<Bool> {
        Binding(
            get: { draft.endDate != nil },
            set: { enabled in draft.endDate = enabled ? .now : nil }
        )
    }

    private var dateRangeSection: some View {
        FilterSectionCard(title: "Date Range", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterOptionChip(label: "Last 30 Days", selected: false) { applyQuickRange(daysBack: 30) }
                        FilterOptionChip(label: "Last 90 Days", selected: false) { applyQuickRange(daysBack: 90) }
                        FilterOptionChip(label: "This Month", selected: false) { applyMonthToDateRange() }
                        FilterOptionChip(label: "This Year", selected: false) { applyYearToDateRange() }
                    }
                    .padding(.horizontal, 2)
                }

                Toggle(isOn: startDateEnabled.animation()) {
                    Text("From").font(.subheadline)
                }
                .tint(.yolk)
                if draft.startDate != nil {
                    DatePicker("Start", selection: startDateBinding, displayedComponents: .date)
                        .labelsHidden()
                }

                Toggle(isOn: endDateEnabled.animation()) {
                    Text("To").font(.subheadline)
                }
                .tint(.yolk)
                if draft.endDate != nil {
                    DatePicker("End", selection: endDateBinding, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private func applyQuickRange(daysBack: Int) {
        let end = Date.now
        draft.startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end
        draft.endDate = end
    }

    private func applyMonthToDateRange() {
        draft.startDate = Calendar.current.startOfMonth(for: .now)
        draft.endDate = .now
    }

    private func applyYearToDateRange() {
        let components = Calendar.current.dateComponents([.year], from: .now)
        draft.startDate = Calendar.current.date(from: components) ?? .now
        draft.endDate = .now
    }

    // MARK: - Amount Range

    private var amountRangeSection: some View {
        FilterSectionCard(title: "Amount Range", systemImage: "dollarsign.circle") {
            HStack(spacing: 12) {
                amountField("Min", text: $minAmountText)
                Text("–").foregroundStyle(.secondary)
                amountField("Max", text: $maxAmountText)
            }
        }
    }

    private func amountField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text("$").foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.nestCream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Recurring

    private var recurringSection: some View {
        FilterSectionCard(title: "Source", systemImage: "arrow.clockwise") {
            Toggle(isOn: $draft.generatedOnly) {
                Label("Recurring-generated only", systemImage: "arrow.clockwise.circle")
                    .font(.subheadline)
            }
            .tint(.yolk)
        }
    }

    // MARK: - Transfers

    private var transfersSection: some View {
        FilterSectionCard(title: "Transfers", systemImage: "arrow.left.arrow.right.circle") {
            Toggle(isOn: $draftHideTransfers) {
                Label("Hide transfers", systemImage: "eye.slash")
                    .font(.subheadline)
            }
            .tint(.yolk)
        }
    }

    // MARK: - Helpers

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func apply() {
        draft.minAmount = AmountParser.parse(minAmountText)
        draft.maxAmount = AmountParser.parse(maxAmountText)
        filter = draft
        hideTransfers = draftHideTransfers
        dismiss()
    }
}

// MARK: - Section Card

private struct FilterSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nestBrown)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestCard()
    }
}

// MARK: - Filter Chip

private struct FilterOptionChip: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(label).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.yolk : Color.yolk.opacity(0.12), in: Capsule())
            .foregroundStyle(selected ? .white : Color.yolk)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: selected)
    }
}

#Preview {
    @Previewable @State var filter = TransactionFilter()
    @Previewable @State var hideTransfers = false
    return TransactionFilterView(filter: $filter, hideTransfers: $hideTransfers)
        .modelContainer(PersistenceController.previewContainer())
}
