import SwiftUI
import SwiftData

struct MonthlyReviewView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]

    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var review: MonthlyReviewData = .empty

    // MARK: - Derived data

    private var isCurrentMonth: Bool {
        Calendar.current.startOfMonth(for: selectedMonth) == Calendar.current.startOfMonth(for: .now)
    }

    private var reviewInputSignature: Int {
        var hasher = Hasher()
        hasher.combine(selectedMonth.timeIntervalSinceReferenceDate)
        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date.timeIntervalSinceReferenceDate)
            hasher.combine(transaction.typeRaw)
            hasher.combine(transaction.isAdjustment)
            hasher.combine(transaction.category?.id)
            hasher.combine(transaction.account?.id)
        }
        for account in accounts {
            hasher.combine(account.id)
            hasher.combine(account.balance)
            hasher.combine(account.typeRaw)
            hasher.combine(account.includeInNetWorth)
            hasher.combine(account.isArchived)
        }
        for budget in budgets {
            hasher.combine(budget.id)
            hasher.combine(budget.name)
            hasher.combine(budget.limitAmount)
            hasher.combine(budget.periodRaw)
            hasher.combine(budget.isActive)
            hasher.combine(budget.category?.id)
        }
        return hasher.finalize()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            NestBackground()

            List {
                if hasMonthActivity {
                    summarySection
                    savingsRateSection
                    if !review.topCategories.isEmpty { topCategoriesSection }
                    if !review.budgetOverruns.isEmpty { budgetOverrunsSection }
                } else {
                    noActivitySection
                }
                netWorthChangeSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Monthly Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            monthNavigationBar
        }
        .onAppear(perform: refreshReview)
        .onChange(of: reviewInputSignature) { _, _ in
            withAnimation(.easeInOut(duration: 0.16)) {
                refreshReview()
            }
        }
    }

    private var hasMonthActivity: Bool {
        review.income > 0 || review.expenses > 0
    }

    // MARK: - Month navigation

    private var monthNavigationBar: some View {
        HStack(spacing: 12) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.yolk)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .accessibilityLabel("Previous month")

            Spacer(minLength: 8)

            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nestBrown)
                .contentTransition(.numericText())
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrentMonth ? Color.twig.opacity(0.4) : Color.yolk)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .frame(width: 32, height: 32)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(.thinMaterial)
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedMonth = Calendar.current.startOfMonth(for: newMonth)
        }
    }

    private func refreshReview() {
        review = MonthlyReviewCalculator.calculate(
            month: selectedMonth,
            transactions: Array(transactions),
            accounts: Array(accounts),
            budgets: Array(budgets)
        )
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                statChip(title: "Income", value: review.income,
                         color: .eggBlue, icon: "arrow.down.circle.fill")
                statChip(title: "Expenses", value: review.expenses,
                         color: Color.negative, icon: "arrow.up.circle.fill")
                statChip(title: "Net Savings", value: review.netSavings,
                         color: review.netSavings >= 0 ? .nestLeafGreen : Color.negative,
                         icon: "leaf.circle.fill")
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func statChip(title: String, value: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // .titleAndIcon guards against .automatic collapsing to icon-only
            // under the narrow width three equal chips propose at larger
            // Dynamic Type sizes (the same failure mode fixed in the Metrics
            // chart callouts).
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.caption2).foregroundStyle(color)
                .lineLimit(1)
            Text(value, format: .currency(code: CurrencyFormat.code))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(height: 72, alignment: .topLeading)
        .nestCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state

    private var noActivitySection: some View {
        Section {
            EmptyStateView(
                title: "No Activity",
                icon: "moon.zzz.fill",
                description: "No income or expenses were recorded this month.",
                context: .listRow
            )
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Savings rate

    private var savingsRateSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Savings Rate")
                        .font(.subheadline).foregroundStyle(Color.twig)
                    if let rate = review.savingsRate {
                        Text("\(Int((rate * 100).rounded()))%")
                            .font(NestType.hero)
                            .foregroundStyle(rate >= 0 ? Color.nestLeafGreen : Color.negative)
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .font(NestType.hero)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: (review.savingsRate ?? 0) >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.title)
                    .foregroundStyle(Color.yolk.opacity(0.7))
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Top categories

    private var topCategoriesSection: some View {
        Section {
            ForEach(review.topCategories) { entry in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.yolk.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: entry.icon)
                            .font(.caption)
                            .foregroundStyle(Color.yolk)
                    }
                    Text(entry.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.amount, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.nestBrown)
                        .contentTransition(.numericText())
                    if review.expenses > 0 {
                        Text("(\(Int((entry.amount / review.expenses * 100).rounded()))%)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Label("Top Spending Categories", systemImage: "chart.pie.fill")
                .foregroundStyle(Color.twig)
        }
    }

    // MARK: - Budget overruns

    private var budgetOverrunsSection: some View {
        Section {
            ForEach(review.budgetOverruns) { overrun in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(overrun.name)
                            .font(.subheadline).foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(overrun.overage, format: .currency(code: CurrencyFormat.code))")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.negative)
                            .contentTransition(.numericText())
                    }
                    ProgressView(value: min(overrun.progress, 1.5), total: 1.5)
                        .tint(Color.negative)
                    HStack {
                        Text("Spent \(overrun.spent, format: .currency(code: CurrencyFormat.code))")
                        Spacer()
                        Text("Limit \(overrun.limit, format: .currency(code: CurrencyFormat.code))")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Label("Budget Overruns", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.negative)
        }
    }

    // MARK: - Net worth change

    private var netWorthChangeSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start of Month").font(.caption).foregroundStyle(.secondary)
                    Text(review.netWorthAtStart, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.nestBrown)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("Change").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: review.netWorthChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(abs(review.netWorthChange), format: .currency(code: CurrencyFormat.code))
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(review.netWorthChange >= 0 ? Color.nestLeafGreen : Color.negative)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("End of Month").font(.caption).foregroundStyle(.secondary)
                    Text(review.netWorthAtEnd, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.nestBrown)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } header: {
            Label("Nest Egg Change", systemImage: "chart.pie.fill")
                .foregroundStyle(Color.twig)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview {
    NavigationStack {
        MonthlyReviewView()
            .modelContainer(PersistenceController.previewContainer())
    }
}
