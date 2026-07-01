import SwiftUI
import SwiftData
import Charts

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
                        VStack(spacing: 20) {
                            summaryHeroCard
                            periodPicker.appearRise(delay: 0.05)
                            if !overBudget.isEmpty   { budgetGroup("Over Budget 🚨",   overBudget,   accent: .red).appearRise(delay: 0.1) }
                            if !warningBudgets.isEmpty { budgetGroup("Watch Out ⚠️", warningBudgets, accent: .yolk).appearRise(delay: 0.15) }
                            if !healthyBudgets.isEmpty { budgetGroup("On Track ✓",   healthyBudgets, accent: .nestLeafGreen).appearRise(delay: 0.2) }
                            inactiveBudgetsSection.appearRise(delay: 0.25)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(AnimatedCanopyBackground())
            .navigationTitle("Budget Eggs")
            .toolbar {
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

    // MARK: – Summary hero card

    private var summaryHeroCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Nest Overview", systemImage: "bird.fill")
                        .font(.headline).foregroundStyle(Color.nestBrown)
                    Text(Date.now, format: .dateTime.month(.wide).year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                overallHealthBadge
            }

            // Spent vs budgeted
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent").font(.caption).foregroundStyle(.secondary)
                    Text(totalSpent, format: .currency(code: "USD"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(totalSpent > totalBudgeted ? .red : Color.nestBrown)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Budgeted").font(.caption).foregroundStyle(.secondary)
                    Text(totalBudgeted, format: .currency(code: "USD"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.nestBrown.opacity(0.6))
                }
            }

            // Animated progress bar
            AnimatedProgressBar(progress: overallProgress,
                                color: overallProgressColor)

            HStack {
                Text("\(Int(min(overallProgress, 9.99) * 100))% used")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                let rem = totalBudgeted - totalSpent
                Text(rem >= 0
                     ? "\(rem.formatted(.currency(code: "USD"))) remaining"
                     : "\(abs(rem).formatted(.currency(code: "USD"))) over")
                    .font(.caption2)
                    .foregroundStyle(rem >= 0 ? Color.nestLeafGreen : .red)
            }

            // Mini donut chart of budget health distribution
            if displayed.count > 1 { budgetHealthDonut }
        }
        .padding(16)
        .nestCard()
        .padding(.top, 4)
    }

    private var overallHealthBadge: some View {
        let (label, color) = overallHealthLabel
        return Text(label)
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var overallHealthLabel: (String, Color) {
        if !overBudget.isEmpty   { return ("Over budget",  .red) }
        if !warningBudgets.isEmpty { return ("Watch out", .yolk) }
        return ("Healthy", .nestLeafGreen)
    }

    private var overallProgressColor: Color {
        switch overallProgress {
        case ..<0.7: return .nestLeafGreen
        case ..<0.9: return .yolk
        case ..<1.0: return .orange
        default:     return .red
        }
    }

    private var budgetHealthDonut: some View {
        HStack(spacing: 12) {
            Chart {
                let o = Double(overBudget.count)
                let w = Double(warningBudgets.count)
                let h = Double(healthyBudgets.count)
                let total = max(o + w + h, 1)
                SectorMark(angle: .value("Over",    o / total), innerRadius: .ratio(0.6), angularInset: 2).foregroundStyle(.red)
                SectorMark(angle: .value("Warning", w / total), innerRadius: .ratio(0.6), angularInset: 2).foregroundStyle(Color.yolk)
                SectorMark(angle: .value("Good",    h / total), innerRadius: .ratio(0.6), angularInset: 2).foregroundStyle(Color.nestLeafGreen)
            }
            .frame(width: 52, height: 52)
            .animation(.spring(), value: displayed.count)

            VStack(alignment: .leading, spacing: 3) {
                if !overBudget.isEmpty    { donutLegend("Over budget", count: overBudget.count, color: .red) }
                if !warningBudgets.isEmpty { donutLegend("Warning",    count: warningBudgets.count, color: .yolk) }
                if !healthyBudgets.isEmpty { donutLegend("Healthy",    count: healthyBudgets.count, color: .nestLeafGreen) }
            }
            Spacer()
        }
    }

    private func donutLegend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: – Period picker

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All",      selected: periodFilter == nil) { periodFilter = nil }
                ForEach(BudgetPeriod.allCases, id: \.self) { period in
                    FilterChip(label: period.rawValue, icon: period.icon,
                               selected: periodFilter == period) { periodFilter = period }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: – Budget groups

    private func budgetGroup(_ title: String, _ items: [Budget], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(accent)

            ForEach(items) { budget in
                NavigationLink(destination: BudgetDetailView(budget: budget)) {
                    BudgetRowView(budget: budget, transactions: Array(transactions))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        modelContext.delete(budget)
                    }
                    Button("Edit", systemImage: "pencil") {
                        editingBudget = budget
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button(budget.isActive ? "Pause" : "Resume",
                           systemImage: budget.isActive ? "pause.circle.fill" : "play.circle.fill") {
                        budget.isActive.toggle()
                    }
                    .tint(budget.isActive ? .orange : .nestLeafGreen)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editingBudget = budget }
                    Button(budget.isActive ? "Pause" : "Resume",
                           systemImage: "power") { budget.isActive.toggle() }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        modelContext.delete(budget)
                    }
                }
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
                        NavigationLink(destination: BudgetDetailView(budget: budget)) {
                            BudgetRowView(budget: budget, transactions: Array(transactions))
                                .opacity(0.55)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { modelContext.delete(budget) }
                            Button("Edit", systemImage: "pencil") { editingBudget = budget }.tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Resume", systemImage: "play.circle.fill") { budget.isActive.toggle() }
                                .tint(.nestLeafGreen)
                        }
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
}

// MARK: – Budget row card

struct BudgetRowView: View {
    let budget: Budget
    let transactions: [Transaction]

    private var spent:      Double { budget.spent(from: transactions) }
    private var progress:   Double { budget.progress(from: transactions) }
    private var remaining:  Double { budget.remaining(from: transactions) }
    private var statusColor: Color { budget.statusColor(progress: progress) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                EggProgressView(progress: progress, size: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if let cat = budget.category {
                            Image(systemName: cat.icon).font(.caption).foregroundStyle(cat.color)
                        }
                        Text(budget.name)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 4) {
                        Text(spent, format: .currency(code: "USD"))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("of").font(.caption).foregroundStyle(.secondary)
                        Text(budget.limitAmount, format: .currency(code: "USD"))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: remaining >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption2).foregroundStyle(remaining >= 0 ? Color.nestLeafGreen : .red)
                        Text(remaining >= 0
                             ? "\(remaining, format: .currency(code: "USD")) left"
                             : "\(abs(remaining), format: .currency(code: "USD")) over")
                            .font(.caption)
                            .foregroundStyle(remaining >= 0 ? Color.nestLeafGreen : .red)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: budget.period.icon).font(.caption).foregroundStyle(.secondary)
                    Text(budget.period.rawValue).font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Colour progress bar at bottom of card
            AnimatedProgressBar(progress: progress, color: statusColor, height: 3)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
    }
}

// MARK: – Reusable sub-components

struct AnimatedProgressBar: View {
    let progress: Double
    var color: Color = .nestLeafGreen
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.twig.opacity(0.15))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(progress, 1.0), height: height)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: height)
    }
}

private struct FilterChip: View {
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
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(selected ? Color.nestBrown : Color.nestBrown.opacity(0.08),
                        in: Capsule())
            .foregroundStyle(selected ? .white : Color.nestBrown)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: selected)
    }
}

#Preview {
    BudgetView()
        .modelContainer(PersistenceController.previewContainer())
}
