import SwiftUI
import SwiftData

struct MonthlyReviewView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<Budget> { $0.isActive }) private var budgets: [Budget]

    @State private var selectedMonth: Date = Calendar.current.startOfMonth(for: .now)

    // MARK: - Derived data

    private var review: MonthlyReviewData {
        MonthlyReviewCalculator.calculate(
            month: selectedMonth,
            transactions: Array(transactions),
            accounts: Array(accounts),
            budgets: Array(budgets)
        )
    }

    private var isCurrentMonth: Bool {
        Calendar.current.startOfMonth(for: selectedMonth) == Calendar.current.startOfMonth(for: .now)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AnimatedCanopyBackground()

            List {
                monthNavigationSection
                summarySection
                savingsRateSection
                if !review.topCategories.isEmpty { topCategoriesSection }
                if !review.budgetOverruns.isEmpty { budgetOverrunsSection }
                netWorthChangeSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Monthly Review")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Month navigation

    private var monthNavigationSection: some View {
        Section {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.yolk)
                }

                Spacer()

                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .foregroundStyle(Color.nestBrown)
                    .contentTransition(.numericText())

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isCurrentMonth ? Color.twig.opacity(0.4) : Color.yolk)
                }
                .disabled(isCurrentMonth)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedMonth = Calendar.current.startOfMonth(for: newMonth)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                statChip(title: "Income", value: review.income,
                         color: .eggBlue, icon: "arrow.down.circle.fill")
                statChip(title: "Expenses", value: review.expenses,
                         color: .red, icon: "arrow.up.circle.fill")
                statChip(title: "Net Savings", value: review.netSavings,
                         color: review.netSavings >= 0 ? .nestLeafGreen : .red,
                         icon: "leaf.circle.fill")
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func statChip(title: String, value: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(color)
            Text(value, format: .currency(code: CurrencyFormat.code))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .nestCard()
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
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(rate >= 0 ? Color.nestLeafGreen : .red)
                    } else {
                        Text("—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: (review.savingsRate ?? 0) >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.system(size: 30))
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
                            .font(.system(size: 14))
                            .foregroundStyle(Color.yolk)
                    }
                    Text(entry.name)
                        .font(.subheadline)
                    Spacer()
                    Text(entry.amount, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.nestBrown)
                    if review.expenses > 0 {
                        Text("(\(Int((entry.amount / review.expenses * 100).rounded()))%)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.clear)
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
                        Spacer()
                        Text("+\(overrun.overage, format: .currency(code: CurrencyFormat.code))")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    ProgressView(value: min(overrun.progress, 1.5), total: 1.5)
                        .tint(.red)
                    HStack {
                        Text("Spent \(overrun.spent, format: .currency(code: CurrencyFormat.code))")
                        Spacer()
                        Text("Limit \(overrun.limit, format: .currency(code: CurrencyFormat.code))")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        } header: {
            Label("Budget Overruns", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
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
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("Change").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: review.netWorthChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(abs(review.netWorthChange), format: .currency(code: CurrencyFormat.code))
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(review.netWorthChange >= 0 ? Color.nestLeafGreen : .red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("End of Month").font(.caption).foregroundStyle(.secondary)
                    Text(review.netWorthAtEnd, format: .currency(code: CurrencyFormat.code))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.nestBrown)
                }
            }
            .padding(.vertical, 6)
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
