import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]
    @Query(filter: #Predicate<SavingsGoal> { $0.statusRaw == "Active" }, sort: \SavingsGoal.createdAt)
    private var activeGoals: [SavingsGoal]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurring: [RecurringTransaction]

    @State private var netWorthVisible = false
    @State private var headerVisible = false
    @State private var showAddTransaction = false

    @State private var savingsContentWidth: CGFloat = 0
    @State private var savingsVisibleWidth: CGFloat = 0
    @State private var savingsScrollOffset: CGFloat = 0
    @State private var budgetContentWidth: CGFloat = 0
    @State private var budgetVisibleWidth: CGFloat = 0
    @State private var budgetScrollOffset: CGFloat = 0

    private var netWorth: Double {
        NetWorthCalculator.current(accounts: Array(accounts))
    }
    private var monthlyIncome: Double {
        transactions.filter { $0.type == .income && Calendar.current.isDateInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    private var monthlyExpenses: Double {
        transactions.filter { $0.type == .expense && Calendar.current.isDateInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    private var recentTransactions: [Transaction] { Array(transactions.prefix(5)) }
    private var topBudgets: [Budget] { budgets.sorted { $0.name < $1.name } }
    private var topGoals: [SavingsGoal] { activeGoals.sorted { $0.createdAt < $1.createdAt } }
    private var safeSpendResult: SafeSpendResult {
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
        NavigationStack {
            ZStack(alignment: .top) {
                AnimatedCanopyBackground()
                BirdAnimationView().frame(height: 100).frame(maxWidth: .infinity).padding(.top, 60)

                ScrollView {
                    VStack(spacing: 20) {
                        nestHeaderSection
                        netWorthCard
                        safeToSpendCard.appearRise(delay: 0.05)
                        monthlySnapshotRow.appearRise(delay: 0.1)
                        cashFlowForecastCard.appearRise(delay: 0.15)
                        monthlyReviewCard.appearRise(delay: 0.2)
                        savingsGoalsPreviewSection.appearRise(delay: 0.25)
                        if !topBudgets.isEmpty { budgetPreviewSection.appearRise(delay: 0.3) }
                        recentTransactionsSection.appearRise(delay: 0.35)
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EggSpend")
                        .font(.headline).foregroundStyle(Color.nestBrown)
                }
                if case .localOnly = EggSpendApp.syncStatus {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(Color.twig)
                            .help("iCloud sync unavailable — data is stored locally only")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddTransaction = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(Color.yolk)
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) { AddTransactionView() }
        }
    }

    // MARK: - Nest header

    private var nestHeaderSection: some View {
        VStack(spacing: 4) {
            NestHeaderView()
                .frame(width: 250, height: 160)
                .opacity(headerVisible ? 1 : 0)
                .scaleEffect(headerVisible ? 1 : 0.75)
            Text("Your Nest")
                .font(.caption).foregroundStyle(Color.twig)
                .opacity(headerVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                headerVisible = true
            }
        }
    }

    // MARK: - Net worth card

    private var netWorthCard: some View {
        VStack(spacing: 6) {
            Text("Nest Egg Total")
                .font(.subheadline).foregroundStyle(Color.twig)
            Text(netWorthVisible ? netWorth : 0, format: .currency(code: "USD"))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(netWorth >= 0 ? Color.nestBrown : Color.red)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: netWorthVisible)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .nestCard()
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) { netWorthVisible = true }
        }
    }

    // MARK: - Safe to Spend Today card

    private var safeToSpendCard: some View {
        NavigationLink(destination: SafeToSpendView()) {
            VStack(spacing: 10) {
                HStack {
                    Label("Safe to Spend Today", systemImage: "leaf.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nestBrown)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(Color.twig)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(safeSpendResult.safeToSpendToday, format: .currency(code: "USD"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(safeSpendStatusColor)
                    Spacer()
                    Label(safeSpendStatusLabel, systemImage: safeSpendStatusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(safeSpendStatusColor)
                }

                HStack {
                    Text("Keeps \(safeSpendResult.requiredBuffer, format: .currency(code: "USD")) cash buffer")
                    Spacer()
                    Text("Based on next 30 days")
                }
                .font(.caption2)
                .foregroundStyle(Color.twig)
            }
            .padding(14)
            .nestCard()
        }
        .buttonStyle(.plain)
    }

    private var safeSpendStatusLabel: String {
        switch safeSpendResult.status {
        case .onTrack: return "On track"
        case .tight:   return "Tight today"
        case .pause:   return "Pause spending"
        }
    }

    private var safeSpendStatusIcon: String {
        switch safeSpendResult.status {
        case .onTrack: return "checkmark.circle.fill"
        case .tight:   return "exclamationmark.triangle.fill"
        case .pause:   return "hand.raised.fill"
        }
    }

    private var safeSpendStatusColor: Color {
        switch safeSpendResult.status {
        case .onTrack: return .nestLeafGreen
        case .tight:   return .yolk
        case .pause:   return .red
        }
    }

    // MARK: - Monthly snapshot

    private var monthlySnapshotRow: some View {
        HStack(spacing: 12) {
            NestMetricCard(title: "Flowed In",  amount: monthlyIncome,
                           color: .eggBlue,       icon: "arrow.down.circle.fill")
            NestMetricCard(title: "Flowed Out", amount: monthlyExpenses,
                           color: .red,            icon: "arrow.up.circle.fill")
            NestMetricCard(title: "Saved",      amount: monthlyIncome - monthlyExpenses,
                           color: .nestLeafGreen,  icon: "leaf.circle.fill")
        }
    }

    // MARK: - Cash Flow Forecast card

    private var cashFlowForecastCard: some View {
        NavigationLink(destination: CashFlowForecastView()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.eggBlue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(Color.eggBlue)
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cash Flow Forecast")
                        .font(.headline).foregroundStyle(Color.nestBrown)
                    Text("30 · 60 · 90 day projections")
                        .font(.caption).foregroundStyle(Color.twig)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(Color.twig)
            }
            .padding(14)
            .nestCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Review card

    private var monthlyReviewCard: some View {
        NavigationLink(destination: MonthlyReviewView()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.yolk.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.yolk)
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Review")
                        .font(.headline).foregroundStyle(Color.nestBrown)
                    Text("Income, savings rate & budget recap")
                        .font(.caption).foregroundStyle(Color.twig)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(Color.twig)
            }
            .padding(14)
            .nestCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Budget preview

    private var budgetPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Budget Eggs", systemImage: "egg.fill")
                .font(.headline)
                .foregroundStyle(Color.nestBrown)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(topBudgets) { budget in
                        NavigationLink(destination: BudgetDetailView(budget: budget)) {
                            BudgetTileView(budget: budget, transactions: Array(transactions))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ScrollContentWidthKey.self, value: proxy.size.width)
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: -proxy.frame(in: .named("budgetScroll")).minX
                            )
                    }
                )
            }
            .coordinateSpace(name: "budgetScroll")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ScrollVisibleWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ScrollContentWidthKey.self) { budgetContentWidth = $0 }
            .onPreferenceChange(ScrollOffsetKey.self) { budgetScrollOffset = max(0, $0) }
            .onPreferenceChange(ScrollVisibleWidthKey.self) { budgetVisibleWidth = $0 }

            HorizontalScrollProgressBar(
                contentWidth: budgetContentWidth,
                visibleWidth: budgetVisibleWidth,
                scrollOffset: budgetScrollOffset,
                tint: .yolk
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Savings goals preview

    private var savingsGoalsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Savings Goals", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Color.nestBrown)

            if topGoals.isEmpty {
                NavigationLink(destination: SavingsGoalsView()) {
                    Text("No goals yet — tap to add one, like a down payment or vacation fund.")
                        .font(.caption)
                        .foregroundStyle(Color.twig)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(topGoals) { goal in
                            NavigationLink(destination: SavingsGoalsView()) {
                                SavingsGoalTileView(goal: goal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ScrollContentWidthKey.self, value: proxy.size.width)
                                .preference(
                                    key: ScrollOffsetKey.self,
                                    value: -proxy.frame(in: .named("savingsScroll")).minX
                                )
                        }
                    )
                }
                .coordinateSpace(name: "savingsScroll")
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollVisibleWidthKey.self, value: proxy.size.width)
                    }
                )
                .onPreferenceChange(ScrollContentWidthKey.self) { savingsContentWidth = $0 }
                .onPreferenceChange(ScrollOffsetKey.self) { savingsScrollOffset = max(0, $0) }
                .onPreferenceChange(ScrollVisibleWidthKey.self) { savingsVisibleWidth = $0 }

                HorizontalScrollProgressBar(
                    contentWidth: savingsContentWidth,
                    visibleWidth: savingsVisibleWidth,
                    scrollOffset: savingsScrollOffset,
                    tint: .eggBlue
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: TransactionsListView()) {
                HStack {
                    Label("Recent Activity", systemImage: "clock.fill")
                        .font(.headline).foregroundStyle(Color.nestBrown)
                    Spacer()
                    Text("See All").font(.subheadline).foregroundStyle(Color.yolk)
                }
            }
            .buttonStyle(.plain)

            if recentTransactions.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Your nest is empty")
                    } icon: {
                        Image(systemName: "bird").symbolEffect(.pulse)
                    }
                } description: {
                    Text("Add your first transaction with the + button.")
                }
                .frame(height: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentTransactions) { tx in
                        TransactionRowView(transaction: tx)
                        if tx.id != recentTransactions.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Metric chip

private struct NestMetricCard: View {
    let title: String
    let amount: Double
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(amount < 0 ? .red : Color.nestBrown)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .nestCard()
    }
}

private struct BudgetTileView: View {
    let budget: Budget
    let transactions: [Transaction]

    private var spent: Double { budget.spent(from: transactions) }
    private var progress: Double { budget.progress(from: transactions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                EggProgressView(progress: progress, size: 46)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(budget.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(progress * 100))% used")
                    .font(.caption2)
                    .foregroundStyle(progress > 1 ? .red : Color.twig)
                Text("\(formattedTileCurrency(spent)) of \(formattedTileCurrency(budget.limitAmount))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 132, height: 128, alignment: .topLeading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(budget.statusColor(progress: progress).opacity(0.25), lineWidth: 1)
        )
    }
}

private struct SavingsGoalTileView: View {
    let goal: SavingsGoal

    private var goalColor: Color { Color(hex: goal.colorHex) ?? .yolk }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                EggProgressView(progress: goal.progress, size: 46)
                Spacer()
                Image(systemName: goal.icon)
                    .font(.caption)
                    .foregroundStyle(goalColor)
            }

            Text(goal.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.monthlySavingsLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(goal.isGoalMet ? Color.nestLeafGreen : Color.twig)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(formattedTileCurrency(goal.currentAmount)) of \(formattedTileCurrency(goal.targetAmount))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 132, height: 128, alignment: .topLeading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(goal.statusColor.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ScrollContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollVisibleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct HorizontalScrollProgressBar: View {
    let contentWidth: CGFloat
    let visibleWidth: CGFloat
    let scrollOffset: CGFloat
    var tint: Color = .eggBlue
    var height: CGFloat = 4

    private var isOverflowing: Bool { contentWidth > visibleWidth + 1 }

    private var thumbFraction: CGFloat {
        guard contentWidth > 0 else { return 1 }
        return min(max(visibleWidth / contentWidth, 0.08), 1)
    }

    private var thumbOffsetFraction: CGFloat {
        let maxScroll = max(contentWidth - visibleWidth, 1)
        return min(max(scrollOffset, 0), maxScroll) / maxScroll
    }

    var body: some View {
        if isOverflowing {
            GeometryReader { geo in
                let thumbWidth = geo.size.width * thumbFraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.twig.opacity(0.15))
                        .frame(height: height)
                    Capsule()
                        .fill(tint)
                        .frame(width: thumbWidth, height: height)
                        .offset(x: (geo.size.width - thumbWidth) * thumbOffsetFraction)
                }
            }
            .frame(height: height)
            .padding(.horizontal, 2)
            .animation(.easeOut(duration: 0.15), value: thumbOffsetFraction)
        }
    }
}

private func formattedTileCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.usesSignificantDigits = true
    formatter.minimumSignificantDigits = 1
    formatter.maximumSignificantDigits = 3
    return formatter.string(from: NSNumber(value: amount)) ?? amount.formatted(.currency(code: "USD"))
}

#Preview {
    DashboardView()
        .modelContainer(PersistenceController.previewContainer())
}
