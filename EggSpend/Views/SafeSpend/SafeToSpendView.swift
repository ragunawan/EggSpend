import SwiftUI
import SwiftData

struct SafeToSpendView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurring: [RecurringTransaction]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]
    @Query(filter: #Predicate<SavingsGoal> { $0.statusRaw == "Active" })
    private var activeGoals: [SavingsGoal]

    @State private var showAssumptions = false
    @State private var showAddAccount = false
    private var result: SafeSpendResult {
        SafeSpendCalculator.calculate(
            accounts: Array(accounts),
            transactions: Array(transactions),
            recurring: Array(recurring),
            budgets: Array(budgets),
            savingsGoals: Array(activeGoals),
            horizonDays: 30
        )
    }

    var body: some View {
        ZStack {
            NestBackground()

            List {
                if accounts.isEmpty {
                    noAccountsSection
                } else {
                    headlineSection
                    breakdownSection
                    budgetSection
                    if !result.unscheduledSavingsGoalNames.isEmpty { unscheduledGoalsSection }
                    projectionSection
                    assumptionsSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Safe to Spend")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddAccount) {
            AddAccountView()
        }
    }

    // MARK: - Empty state

    private var noAccountsSection: some View {
        Section {
            EmptyStateView(
                title: "No Accounts Yet",
                icon: "banknote",
                description: "Add an account so EggSpend can calculate what's safe to spend today.",
                action: ("Add Account", { showAddAccount = true }),
                context: .listRow
            )
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Headline

    private var headlineSection: some View {
        Section {
            VStack(spacing: 8) {
                Text("Safe to Spend Today")
                    .font(.subheadline).foregroundStyle(Color.twig)
                Text(result.safeToSpendToday, format: .currency(code: CurrencyFormat.code))
                    .font(NestType.hero)
                    .foregroundStyle(statusColor)
                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
    }

    private var statusLabel: String {
        switch result.status {
        case .onTrack: return "On track"
        case .tight:   return "Tight today"
        case .pause:   return "Pause spending"
        }
    }

    private var statusIcon: String {
        switch result.status {
        case .onTrack: return "checkmark.circle.fill"
        case .tight:   return "exclamationmark.triangle.fill"
        case .pause:   return "hand.raised.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .onTrack: return .nestLeafGreen
        case .tight:   return .yolk
        case .pause:   return Color.negative
        }
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        Section {
            breakdownRow(label: "Liquid cash", value: result.liquidBalance, color: .eggBlue)
            breakdownRow(label: "Upcoming 30-day bills", value: -result.upcomingNetOutflowReserve, color: Color.negative)
            breakdownRow(label: "Cash buffer", value: -result.requiredBuffer, color: .yolk)
            breakdownRow(label: "Savings goal reserve", value: -result.plannedSavingsReserve, color: .nestLeafGreen)
            breakdownRow(label: "Cash available after obligations", value: result.cashAvailableAfterObligations,
                         color: Color.nestBrown, isTotal: true)
        } header: {
            Label("Cash-Based Calculation", systemImage: "banknote.fill")
                .foregroundStyle(Color.twig)
        }
    }

    private var budgetSection: some View {
        Section {
            if result.hasActiveBudgets {
                breakdownRow(label: "Budget allowance remaining today", value: result.budgetDailyAllowance,
                             color: Color.nestBrown, isTotal: true)
            } else {
                Text("No active budgets — spending isn't capped by a budget allowance.")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            breakdownRow(label: "Safe to spend today", value: result.safeToSpendToday,
                         color: statusColor, isTotal: true)
        } header: {
            Label("Budget-Based Calculation", systemImage: "chart.pie.fill")
                .foregroundStyle(Color.twig)
        } footer: {
            Text("Safe to spend is the more conservative of the cash-based and budget-based amounts, never below $0.")
                .font(.caption2)
        }
    }

    private var unscheduledGoalsSection: some View {
        Section {
            ForEach(result.unscheduledSavingsGoalNames, id: \.self) { name in
                HStack {
                    Text(name).font(.subheadline)
                    Spacer()
                    Text("Not scheduled").font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
        } header: {
            Label("Goals Without a Target Date", systemImage: "calendar.badge.exclamationmark")
                .foregroundStyle(Color.twig)
        } footer: {
            Text("These active goals have no target date, so no daily contribution is reserved for them yet.")
                .font(.caption2)
        }
    }

    private func breakdownRow(label: String, value: Double, color: Color, isTotal: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isTotal ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(isTotal ? Color.nestBrown : .primary)
            Spacer()
            Text(value, format: .currency(code: CurrencyFormat.code))
                .font(.system(.callout, design: .rounded, weight: isTotal ? .bold : .medium))
                .foregroundStyle(color)
        }
        .padding(.vertical, isTotal ? 4 : 2)
        .listRowBackground(Color.clear)
    }

    // MARK: - Projection

    private var projectionSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("30-Day Projected Balance").font(.caption).foregroundStyle(.secondary)
                    Text(result.projectedThirtyDayBalance, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.nestBrown)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("30-Day Change").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: result.thirtyDayNetWorthDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(abs(result.thirtyDayNetWorthDelta), format: .currency(code: CurrencyFormat.code))
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(result.thirtyDayNetWorthDelta >= 0 ? Color.nestLeafGreen : Color.negative)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Label("Based on Next 30 Days", systemImage: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.twig)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Assumptions

    private var assumptionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAssumptions) {
                VStack(alignment: .leading, spacing: 10) {
                    assumptionRow("banknote.fill",
                        "Checking and savings are treated as spendable cash. Investments are counted in net worth but not available cash.")
                    assumptionRow("arrow.clockwise",
                        "Active recurring income and expenses due in the next 30 days are included.")
                    assumptionRow("shield.fill",
                        "A cash buffer is reserved, based on recent spending pace with a $500 floor.")
                    assumptionRow("leaf.fill",
                        "Active savings goals with a target date are protected by reserving their daily required contribution. Goals without a target date aren't reserved for.")
                    assumptionRow("chart.pie.fill",
                        "Active budgets are protected too: each budget's remaining amount is spread across the days left in its period, and an over-budget category contributes $0 rather than going negative.")
                    assumptionRow("exclamationmark.triangle",
                        "Safe to spend is the more conservative of the cash-based and budget-based amounts, and never goes below $0.")
                }
                .padding(.vertical, 6)
            } label: {
                Label("Assumptions", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(Color.twig)
            }
            .tint(Color.yolk)
        }
        .listRowBackground(Color.clear)
    }

    private func assumptionRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.twig)
                .frame(width: 18)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        SafeToSpendView()
            .modelContainer(PersistenceController.previewContainer())
    }
}
