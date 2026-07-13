import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]
    @Query(filter: #Predicate<SavingsGoal> { $0.statusRaw == "Active" }, sort: \SavingsGoal.createdAt)
    private var activeGoals: [SavingsGoal]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurring: [RecurringTransaction]

    @State private var showAddTransaction = false
    @State private var showQuickAdd = false
    @State private var showSettings = false
    @State private var quickAddDraft: QuickAddDraft?
    @State private var safeSpendResult = DashboardView.emptySafeSpendResult

    // MARK: - AI narrative state (T19b)
    @AppStorage(SettingsView.aiNarrativeStorageKey) private var aiNarrativeEnabled = false
    /// Constructed lazily on first use and reused for the view's lifetime —
    /// `LiveNarrativeModelSession` bakes the system instructions in at init,
    /// and NarrativeGenerator's doc comment marks per-lifetime reuse as
    /// load-bearing (re-creating per call would re-send instructions each turn).
    @State private var narrativeSession: NarrativeModelSession?
    /// Validated AI rewrite of the spending-delta sentences; nil = show the
    /// deterministic template rows (the always-works path).
    @State private var narrative: String?

    private var netWorth: Double {
        NetWorthCalculator.current(accounts: Array(accounts))
    }

    private var monthlyIncome: Double {
        transactions.filter { $0.type == .income && !$0.isAdjustment && Calendar.current.isDateInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthlyExpenses: Double {
        transactions.filter { $0.type == .expense && !$0.isAdjustment && Calendar.current.isDateInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthlySaved: Double {
        monthlyIncome - monthlyExpenses
    }

    private var spendingDeltas: [SpendingDeltaCalculator.CategoryDelta] {
        SpendingDeltaCalculator.calculate(transactions: transactions)
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.prefix(5))
    }

    private var topBudgets: [Budget] {
        Array(budgets.sorted { $0.name < $1.name }.prefix(3))
    }

    private var topGoals: [SavingsGoal] {
        Array(activeGoals.sorted { $0.createdAt < $1.createdAt }.prefix(3))
    }

    private static let emptySafeSpendResult = SafeSpendResult(
        safeToSpendToday: 0,
        liquidBalance: 0,
        requiredBuffer: 0,
        upcomingNetOutflowReserve: 0,
        plannedSavingsReserve: 0,
        cashAvailableAfterObligations: 0,
        budgetDailyAllowance: 0,
        hasActiveBudgets: false,
        unscheduledSavingsGoalNames: [],
        projectedThirtyDayBalance: 0,
        thirtyDayNetWorthDelta: 0,
        status: .pause
    )

    private var safeSpendRefreshKey: Int {
        var hasher = Hasher()
        hasher.combine(accounts.count)
        for account in accounts {
            hasher.combine(account.id)
            hasher.combine(account.balance)
            hasher.combine(account.typeRaw)
            hasher.combine(account.isArchived)
        }
        hasher.combine(transactions.count)
        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date)
            hasher.combine(transaction.typeRaw)
            hasher.combine(transaction.isAdjustment)
            hasher.combine(transaction.account?.id)
            hasher.combine(transaction.category?.id)
        }
        hasher.combine(recurring.count)
        for item in recurring {
            hasher.combine(item.id)
            hasher.combine(item.amount)
            hasher.combine(item.nextDueDate)
            hasher.combine(item.frequencyRaw)
            hasher.combine(item.isActive)
        }
        hasher.combine(budgets.count)
        for budget in budgets {
            hasher.combine(budget.id)
            hasher.combine(budget.limitAmount)
            hasher.combine(budget.periodRaw)
            hasher.combine(budget.isActive)
            hasher.combine(budget.category?.id)
        }
        hasher.combine(activeGoals.count)
        for goal in activeGoals {
            hasher.combine(goal.id)
            hasher.combine(goal.currentAmount)
            hasher.combine(goal.targetAmount)
            hasher.combine(goal.targetDate)
            hasher.combine(goal.statusRaw)
            hasher.combine(goal.linkedAccount?.id)
        }
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                NestBackground()

                ScrollView {
                    VStack(spacing: Space.md) {
                        safeToSpendCard
                        statGrid
                        if !spendingDeltas.isEmpty { insightRow }
                        recentSection
                        progressSection
                        moreSection
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xl * 2)
                }

                Button { showQuickAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(Color.yolk, in: Circle())
                        .shadow(color: Color.nestBrown.opacity(0.18), radius: 12, y: 6)
                }
                .accessibilityLabel("Add transaction")
                .padding(.trailing, Space.lg)
                .padding(.bottom, Space.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EggSpend")
                        .font(.headline)
                        .foregroundStyle(Color.nestBrown)
                }
                if case .localOnly = EggSpendApp.syncStatus {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(Color.textSecondaryWarm)
                            .help("iCloud sync unavailable — data is stored locally only")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        quickAddDraft = nil
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(Color.textSecondaryWarm)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showAddTransaction) { addTransactionSheet }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheet(onMoreOptions: openFullFormFromQuickAdd)
                    .presentationDetents(quickAddDetents)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task(id: safeSpendRefreshKey) {
                refreshSafeSpendResult()
            }
        }
    }

    private var quickAddDetents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(460), .large]
    }

    @ViewBuilder
    private var addTransactionSheet: some View {
        if let quickAddDraft {
            AddTransactionView(
                initialEntryKind: quickAddDraft.entryKind,
                initialTitle: quickAddDraft.title,
                initialAmountText: quickAddDraft.amountText,
                initialDate: quickAddDraft.date,
                initialCategory: quickAddDraft.category,
                initialAccount: quickAddDraft.account,
                initialBudget: quickAddDraft.budget
            )
        } else {
            AddTransactionView()
        }
    }

    private func openFullFormFromQuickAdd(_ draft: QuickAddDraft) {
        quickAddDraft = draft
        showQuickAdd = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showAddTransaction = true
        }
    }

    private func refreshSafeSpendResult() {
        safeSpendResult = SafeSpendCalculator.calculate(
            accounts: Array(accounts),
            transactions: Array(transactions),
            recurring: Array(recurring),
            budgets: Array(budgets),
            savingsGoals: Array(activeGoals),
            horizonDays: 30
        )
    }

    private var safeToSpendCard: some View {
        NavigationLink(destination: SafeToSpendView()) {
            SafeSpendHeroCard(result: safeSpendResult)
        }
        .buttonStyle(.plain)
    }

    private var statGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: Space.sm) {
            StatTile(label: "Net worth", value: netWorth) {
                tabRouter.selectedTab = 3
            }
            StatTile(label: "Saved", value: monthlySaved, trend: "This month", trendPositive: monthlySaved >= 0)
            StatTile(label: "Flowed in", value: monthlyIncome, trend: "Income", trendPositive: true)
            StatTile(label: "Flowed out", value: monthlyExpenses, trend: "Spending", trendPositive: false)
        }
    }

    private var insightRow: some View {
        InsightRow(narrative: narrative, deltas: spendingDeltas)
            // Keyed on the toggle + the rendered sentence text (NOT the array or
            // transaction count): unrelated @Query re-fires that don't change the
            // top-3 sentences must not re-trigger a model call, and flipping the
            // toggle mid-flight cancels the task and clears the narrative.
            .task(id: "\(aiNarrativeEnabled)|\(spendingDeltas.map(\.sentence).joined(separator: "|"))") {
                guard aiNarrativeEnabled, NarrativeGenerator.isAvailable(), !spendingDeltas.isEmpty else {
                    narrative = nil
                    return
                }
                // Clear any previous narrative BEFORE the await: if the underlying
                // data just changed, the old paragraph's figures no longer match
                // the live deltas — the template rows (always derived from current
                // data) must show during the model round-trip, never stale figures.
                narrative = nil
                if narrativeSession == nil {
                    narrativeSession = LiveNarrativeModelSession(instructions: NarrativeGenerator.instructions)
                }
                guard let session = narrativeSession else { return }
                let sentences = spendingDeltas.map {
                    NarrativeGenerator.Sentence(text: $0.sentence, figures: $0.figures)
                }
                let result = await NarrativeGenerator.generate(sentences: sentences, session: session)
                // A cancelled-but-suspended task must not overwrite a newer task's result.
                if !Task.isCancelled { narrative = result }
            }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Recent", trailing: ("See All", { tabRouter.selectedTab = 1 }))

            if recentTransactions.isEmpty {
                EmptyStateView(
                    title: "Your nest is empty",
                    icon: "bird",
                    description: "Add your first transaction with the + button."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recentTransactions) { transaction in
                        LedgerRowView(row: .transaction(transaction), showsMeta: [.category, .account])
                        if transaction.id != recentTransactions.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .nestCard()
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader("Goals & Budgets")

            VStack(spacing: Space.xs) {
                if topGoals.isEmpty && topBudgets.isEmpty {
                    EmptyStateView(
                        title: "No goals or budgets yet",
                        icon: "leaf",
                        description: "Add a savings goal or budget to track progress here.",
                        context: .stack
                    )
                } else {
                    ForEach(topGoals) { goal in
                        CompactProgressRow(
                            name: goal.name,
                            leftAmount: max(goal.targetAmount - goal.currentAmount, 0),
                            progress: goal.progress,
                            statusColor: goal.statusColor
                        ) {
                            SavingsGoalsView()
                        }
                    }

                    ForEach(topBudgets) { budget in
                        let spent = budget.spent(from: Array(transactions))
                        let progress = budget.progress(from: Array(transactions))
                        CompactProgressRow(
                            name: budget.name,
                            leftAmount: budget.limitAmount - spent,
                            progress: progress,
                            statusColor: budget.statusColor(progress: progress)
                        ) {
                            BudgetDetailView(budget: budget)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .nestCard()
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("More")

            VStack(spacing: 0) {
                MoreLink(title: "Forecast", subtitle: "30 · 60 · 90 day projections", icon: "chart.line.uptrend.xyaxis") {
                    CashFlowForecastView()
                }
                Divider().padding(.leading, 52)
                MoreLink(title: "Monthly review", subtitle: "Income, savings rate & budget recap", icon: "calendar.badge.clock") {
                    MonthlyReviewView()
                }
            }
            .nestCard()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
