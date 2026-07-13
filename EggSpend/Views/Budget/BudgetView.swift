import SwiftUI
import SwiftData

struct BudgetView: View {
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddBudget  = false
    @State private var editingBudget: Budget? = nil
    @State private var periodFilter: BudgetPeriod? = nil

    // MARK: – Derived

    private var displayed: [Budget] {
        let active = budgets.filter(\.isActive)
        if let p = periodFilter { return active.filter { $0.period == p } }
        return active
    }

    private var overBudget: [Budget] {
        displayed.filter { $0.progress(from: transactions) > 1.0 }
    }

    private var warningBudgets: [Budget] {
        displayed.filter {
            let p = $0.progress(from: transactions)
            return p >= 0.8 && p <= 1.0
        }
    }

    private var healthyBudgets: [Budget] {
        displayed.filter { $0.progress(from: transactions) < 0.8 }
    }

    private var totalBudgeted: Double { displayed.reduce(0) { $0 + $1.limitAmount } }
    private var totalSpent: Double    { displayed.reduce(0) { $0 + $1.spent(from: transactions) } }
    private var overallProgress: Double {
        guard totalBudgeted > 0 else { return 0 }
        return totalSpent / totalBudgeted
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            Group {
                if budgets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Budget Eggs")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)
                                .padding(.top, Space.xs)

                            summaryStrip

                            VStack(spacing: 16) {
                                if displayed.isEmpty && periodFilter != nil {
                                    filteredEmptyState

                                } else {
                                    if !overBudget.isEmpty   { budgetGroup("Over Budget",   overBudget,   accent: .negative) }
                                    if !warningBudgets.isEmpty { budgetGroup("Watch Out", warningBudgets, accent: .yolk) }
                                    if !healthyBudgets.isEmpty { budgetGroup("On Track",   healthyBudgets, accent: .nestLeafGreen) }
                                    inactiveBudgetsSection
                                }
                            }
                            .padding(Space.md)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, Space.xl)
                }
            }
            .background(NestBackground())
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            periodFilter = nil
                        } label: {
                            Label("All Periods", systemImage: periodFilter == nil ? "checkmark" : "line.3.horizontal.decrease.circle")
                        }
                        ForEach(BudgetPeriod.allCases, id: \.self) { period in
                            Button {
                                periodFilter = period
                            } label: {
                                Label(period.rawValue, systemImage: periodFilter == period ? "checkmark" : period.icon)
                            }
                        }
                    } label: {
                        Label(periodFilter?.rawValue ?? "All Periods", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddBudget = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(Color.yolk)
                    }
                }
            }
            .sheet(isPresented: $showAddBudget) { AddBudgetView() }
            .sheet(item: $editingBudget) { budget in AddBudgetView(editingBudget: budget) }
        }
    }

    // MARK: – Summary strip

    private var overallProgressColor: Color {
        switch overallProgress {
        case ..<0.7: return .nestLeafGreen
        case ..<0.9: return .yolk
        case ..<1.0: return .warningTone
        default:     return .negative
        }
    }

    private var summaryStrip: some View {
        BudgetSummaryStrip(
            spent: totalSpent,
            budgeted: totalBudgeted,
            progress: overallProgress,
            progressColor: overallProgressColor,
            periodLabel: periodFilter?.rawValue ?? "All periods",
            overCount: overBudget.count,
            warningCount: warningBudgets.count,
            healthyCount: healthyBudgets.count
        )
        .padding(.top, Space.xs)
    }

    // MARK: – Budget groups

    private func budgetGroup(_ title: String, _ items: [Budget], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(accent)

            ForEach(items) { budget in
                budgetRowLink(for: budget)
            }
        }
    }

    // MARK: – Inactive budgets (collapsed by default)

    @State private var showInactive = false

    private var inactiveBudgets: [Budget] { budgets.filter { !$0.isActive } }

    @ViewBuilder
    private var inactiveBudgetsSection: some View {
        if !inactiveBudgets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showInactive.toggle()
                    }
                } label: {
                    HStack {
                        Text("Inactive (\(inactiveBudgets.count))")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Image(systemName: showInactive ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showInactive {
                    ForEach(inactiveBudgets) { budget in
                        budgetRowLink(for: budget)
                            .opacity(0.55)
                    }
                }
            }
        }
    }

    // MARK: – Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Budgets Yet")
            } icon: {
                Image(systemName: "bird").symbolEffect(.pulse)
            }
        } description: {
            Text("Build your nest egg wisely.\nTap + to set your first budget.")
        } actions: {
            Button { showAddBudget = true } label: {
                Label("Add Budget", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).tint(Color.nestBrown)
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label {
                Text(filteredEmptyTitle)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        } description: {
            Text("There are no active budgets for the selected filter.")
        } actions: {
            Button("Show All Budgets") { periodFilter = nil }
                .buttonStyle(.borderedProminent)
                .tint(Color.nestBrown)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var filteredEmptyTitle: String {
        if let periodFilter {
            return "No \(periodFilter.rawValue) Budgets"
        }
        return "No Budgets"
    }

    private func budgetRowLink(for budget: Budget) -> some View {
        CompactProgressRow(
            name: budget.name,
            leftAmount: budget.remaining(from: transactions),
            progress: budget.progress(from: transactions),
            statusColor: budget.statusColor(progress: budget.progress(from: transactions))
        ) {
            BudgetDetailView(budget: budget)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingBudget = budget }
            Button(budget.isActive ? "Pause" : "Resume",
                   systemImage: budget.isActive ? "pause.circle.fill" : "play.circle.fill") {
                budget.isActive.toggle()
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(budget)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(budget)
            }
            Button("Edit", systemImage: "pencil") {
                editingBudget = budget
            }
            .tint(.info)
        }
        .swipeActions(edge: .leading) {
            Button(budget.isActive ? "Pause" : "Resume",
                   systemImage: budget.isActive ? "pause.circle.fill" : "play.circle.fill") {
                budget.isActive.toggle()
            }
            .tint(budget.isActive ? .warningTone : .positive)
        }
    }
}

// MARK: – Summary strip

private struct BudgetSummaryStrip: View {
    let spent: Double
    let budgeted: Double
    let progress: Double
    let progressColor: Color
    let periodLabel: String
    let overCount: Int
    let warningCount: Int
    let healthyCount: Int

    private var remaining: Double { budgeted - spent }
    private var statusCaption: String {
        [
            overCount > 0 ? "\(overCount) over" : nil,
            warningCount > 0 ? "\(warningCount) watch" : nil,
            healthyCount > 0 ? "\(healthyCount) on track" : nil
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.md) {
            EggProgressView(progress: progress, size: 44, showsPercentage: false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(spent, format: .currency(code: CurrencyFormat.code))
                        .font(NestType.amount)
                        .foregroundStyle(spent > budgeted ? Color.negative : Color.nestBrown)
                    Text("of \(budgeted, format: .currency(code: CurrencyFormat.code)) · \(periodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                ThinProgressBar(progress: progress, color: progressColor)

                Text(statusCaption.isEmpty ? "No active budgets" : statusCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget summary")
        .accessibilityValue("\(CurrencyFormat.money(spent)) of \(CurrencyFormat.money(budgeted)), \(Int(progress * 100))% used, \(remaining >= 0 ? CurrencyFormat.money(remaining) + " remaining" : CurrencyFormat.money(abs(remaining)) + " over")")
    }
}

// MARK: – Reusable sub-components

struct AnimatedProgressBar: View {
    let progress: Double
    var color: Color = .positive
    var height: CGFloat = 4

    var body: some View {
        ThinProgressBar(progress: progress, color: color, height: height)
    }
}

#Preview {
    BudgetView()
        .modelContainer(PersistenceController.previewContainer())
}
