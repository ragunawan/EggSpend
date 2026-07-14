import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let budget: Budget
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var eggVisible = false

    // MARK: – Period math

    private var periodStart: Date {
        let cal = Calendar.current
        let now = Date.now
        switch budget.period {
        case .weekly:  return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly: return cal.startOfMonth(for: now)
        case .yearly:  return cal.dateInterval(of: .year, for: now)?.start ?? now
        }
    }

    private var periodEnd: Date {
        let cal = Calendar.current
        switch budget.period {
        case .weekly:  return cal.date(byAdding: .day,   value: 7,  to: periodStart) ?? .now
        case .monthly: return cal.date(byAdding: .month, value: 1,  to: periodStart) ?? .now
        case .yearly:  return cal.date(byAdding: .year,  value: 1,  to: periodStart) ?? .now
        }
    }

    private var daysInPeriod: Int {
        max(1, Calendar.current.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 1)
    }

    private var daysElapsed: Int {
        max(1, Calendar.current.dateComponents([.day], from: periodStart, to: min(Date.now, periodEnd)).day ?? 1)
    }

    private var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date.now, to: periodEnd).day ?? 0)
    }

    // MARK: – Transaction filtering

    private var periodTransactions: [Transaction] {
        // Delegates to Budget's shared predicate so this list can never drift from
        // the hero spent/progress/remaining figures (also `Budget.spent(from:)`-derived).
        budget.matchingTransactions(from: allTransactions, start: periodStart, end: periodEnd)
    }

    // MARK: – Computed metrics

    private var spent: Double    { budget.spent(from: allTransactions) }
    private var progress: Double { budget.progress(from: allTransactions) }
    private var remaining: Double { budget.remaining(from: allTransactions) }

    private var dailyAverage: Double { spent / Double(daysElapsed) }
    private var projectedTotal: Double { dailyAverage * Double(daysInPeriod) }
    private var projectedProgress: Double {
        guard budget.limitAmount > 0 else { return 0 }
        return projectedTotal / budget.limitAmount
    }
    private var isOnTrack: Bool { projectedTotal <= budget.limitAmount }

    // Daily spending for chart
    private var dailySpending: [(date: Date, amount: Double)] {
        let cal = Calendar.current
        var dict: [Date: Double] = [:]
        for tx in periodTransactions {
            let day = cal.startOfDay(for: tx.date)
            dict[day, default: 0] += tx.amount
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.date < $1.date }
    }

    // Running cumulative spending for trend line. Seeded with a (periodStart, 0)
    // point so the series always has ≥2 points — Charts can't draw a line/area
    // from a single point, which left the "Actual spend" trace invisible for
    // budgets with only one transaction this period.
    private var cumulativeSpending: [(date: Date, cumulative: Double)] {
        var running = 0.0
        var points = [(date: periodStart, cumulative: 0.0)]
        points.append(contentsOf: dailySpending.map { point in
            running += point.amount
            return (point.date, running)
        })
        return points
    }

    // Ideal pace: a straight line from 0 on periodStart to limit on periodEnd,
    // spanning the whole budget period (not just the days elapsed so far) so it
    // reads as a fixed reference line rather than a ramp that dead-ends today.
    private var paceLine: [(date: Date, pace: Double)] {
        let daily = budget.limitAmount / Double(daysInPeriod)
        return (0...daysInPeriod).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: periodStart) else { return nil }
            return (date, daily * Double(offset))
        }
    }

    // MARK: – Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                eggHeroSection
                statsGrid
                if !dailySpending.isEmpty { spendingChartSection }
                transactionsSection
            }
            .padding(.horizontal)
            .padding(.bottom, Space.xl)
        }
        .background(NestBackground())
        .navigationTitle(budget.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil")        { showEdit = true }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete \"\(budget.name)\"?",
                            isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(budget)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showEdit) {
            AddBudgetView(editingBudget: budget)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.15)) {
                eggVisible = true
            }
        }
    }

    // MARK: – Egg hero

    private var eggProgressAccessibilityValue: String {
        let base = "\(Int(progress * 100))% used, \(CurrencyFormat.money(spent)) of \(CurrencyFormat.money(budget.limitAmount))"
        return progress > 1 ? base + ", over budget" : base
    }

    private var eggHeroSection: some View {
        VStack(spacing: 16) {
            // Large animated egg
            EggProgressView(progress: progress, size: 120, showsPercentage: false)
                .scaleEffect(eggVisible ? 1 : 0.6)
                .opacity(eggVisible ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(budget.name)
                .accessibilityValue(eggProgressAccessibilityValue)

            VStack(spacing: 4) {
                // Status headline
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(statusHeadline)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                }

                // Spent / limit
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(spent, format: .currency(code: CurrencyFormat.code))
                        .font(NestType.hero)
                        .foregroundStyle(Color.nestBrown)
                    Text("/ \(budget.limitAmount, format: .currency(code: CurrencyFormat.code))")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Period badge
                HStack(spacing: Space.sm) {
                    Label(budget.period.rawValue, systemImage: budget.period.icon)
                        .foregroundStyle(Color.twig)
                        .padding(.horizontal, Space.md).padding(.vertical, Space.xs)
                        .background(Color.twig.opacity(0.12), in: Capsule())

                    if let category = budget.category {
                        Label(category.name, systemImage: category.icon)
                            .foregroundStyle(category.color)
                            .padding(.horizontal, Space.md).padding(.vertical, Space.xs)
                            .background(category.color.opacity(0.12), in: Capsule())
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.sm)
    }

    private var statusIcon: String {
        switch progress {
        case ..<0.7:  return "checkmark.circle.fill"
        case ..<0.9:  return "exclamationmark.circle.fill"
        case ..<1.0:  return "exclamationmark.triangle.fill"
        default:      return "xmark.circle.fill"
        }
    }

    private var statusColor: Color { budget.statusColor(progress: progress) }
    private var statusHeadline: String {
        switch progress {
        case ..<0.7:  return "On Track"
        case ..<0.9:  return "Heads Up"
        case ..<1.0:  return "Almost Full"
        default:      return "Over Budget"
        }
    }

    // MARK: – Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Remaining",
                     value: remaining >= 0
                        ? remaining.formatted(.currency(code: CurrencyFormat.code))
                        : abs(remaining).formatted(.currency(code: CurrencyFormat.code)) + " over",
                     icon: "banknote",
                     color: remaining >= 0 ? .positive : .negative)

            StatCard(title: "Daily Avg",
                     value: dailyAverage.formatted(.currency(code: CurrencyFormat.code)),
                     icon: "chart.line.uptrend.xyaxis",
                     color: .eggBlue)

            StatCard(title: "Projected",
                     value: projectedTotal.formatted(.currency(code: CurrencyFormat.code)),
                     icon: isOnTrack ? "arrow.up.right.circle.fill" : "exclamationmark.arrow.up.right.circle.fill",
                     color: isOnTrack ? .nestLeafGreen : .yolk,
                     subtitle: isOnTrack ? "Under limit" : "Exceeds limit")

            StatCard(title: "Days Left",
                     value: "\(daysRemaining)",
                     icon: "calendar",
                     color: .twig,
                     subtitle: "of \(daysInPeriod) total")
        }
    }

    // MARK: – Spending chart

    private var spendingChartAccessibilityValue: String {
        "Spent \(CurrencyFormat.money(spent)) of \(CurrencyFormat.money(budget.limitAmount)), projected \(CurrencyFormat.money(projectedTotal)), "
        + (isOnTrack ? "on track" : "exceeds limit")
    }

    private var spendingChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Trajectory")
                .font(.headline).foregroundStyle(Color.nestBrown)

            Chart {
                // Pace target area (shaded region under ideal line)
                // Uses "Pace Day"/"Pace Base" (not "Day"/"Base") so Swift Charts
                // doesn't fold this series' style into the actual-spend series below —
                // marks that share value-label strings across ForEach loops can be
                // treated as one style domain, which previously made the actual-spend
                // line render with the pace line's green dashed style.
                ForEach(paceLine, id: \.date) { point in
                    AreaMark(
                        x: .value("Pace Day", point.date),
                        yStart: .value("Pace Base", 0),
                        yEnd:   .value("Pace", point.pace)
                    )
                    .foregroundStyle(Color.nestLeafGreen.opacity(0.08))
                    .interpolationMethod(.linear)
                }

                // Pace target line
                ForEach(paceLine, id: \.date) { point in
                    LineMark(
                        x: .value("Pace Day", point.date),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(Color.nestLeafGreen.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .interpolationMethod(.linear)
                }

                // Actual cumulative spend area
                ForEach(cumulativeSpending, id: \.date) { point in
                    AreaMark(
                        x: .value("Spend Day", point.date),
                        yStart: .value("Spend Base", 0),
                        yEnd:   .value("Spent", point.cumulative)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [statusColor.opacity(0.25), statusColor.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Actual cumulative spend line
                ForEach(cumulativeSpending, id: \.date) { point in
                    LineMark(
                        x: .value("Spend Day", point.date),
                        y: .value("Spent", point.cumulative)
                    )
                    .foregroundStyle(statusColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                    .symbolSize(24)
                    .interpolationMethod(.catmullRom)
                }

                // Budget limit rule
                RuleMark(y: .value("Limit", budget.limitAmount))
                    .foregroundStyle(Color.negative.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(budget.limitAmount, format: .currency(code: CurrencyFormat.code).precision(.fractionLength(0)))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.negative)
                            .chartDetailCalloutStyle()
                    }
            }
            .chartYAxis {
                AxisMarks(format: .currency(code: CurrencyFormat.code).precision(.fractionLength(0)))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 200)
            // Summarize the trend as one stop rather than exposing every mark —
            // the individual daily points aren't independently meaningful here.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spending trajectory")
            .accessibilityValue(spendingChartAccessibilityValue)

            // Legend
            HStack(spacing: 20) {
                legendChip(color: statusColor, label: "Actual spend")
                legendChip(color: .nestLeafGreen.opacity(0.5), dashed: true, label: "Target pace")
            }
            .font(.caption2)
        }
        .padding()
        .nestCard()
    }

    private func legendChip(color: Color, dashed: Bool = false, label: String) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(color).frame(width: 5, height: 2)
                        Rectangle().fill(Color.clear).frame(width: 3, height: 2)
                    }
                }
                .frame(width: 22)
            } else {
                RoundedRectangle(cornerRadius: Radius.control).fill(color).frame(width: 22, height: 3)
            }
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: – Transaction list

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Period")
                    .font(.headline).foregroundStyle(Color.nestBrown)
                Spacer()
                Text("\(periodTransactions.count) transactions")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if periodTransactions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No transactions yet this \(budget.period.rawValue.lowercased())")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Space.xl)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(periodTransactions) { tx in
                        LedgerRowView(row: .transaction(tx), showsMeta: [.category, .account, .date])
                        if tx.id != periodTransactions.last?.id {
                            Divider().padding(.leading, Space.xl * 2 + Space.xs)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
            }
        }
    }
}

// MARK: – Stat card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                    .font(.subheadline)
                Spacer()
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.nestBrown)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let sub = subtitle {
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    let context   = ModelContext(container)
    let cat = TransactionCategory(name: "Food & Dining", icon: "fork.knife",
                                  colorHex: "E67E22", typeFilter: .expense)
    context.insert(cat)
    let budget = Budget(name: "Groceries", limitAmount: 400, period: .monthly,
                        category: cat, colorHex: "E67E22")
    context.insert(budget)
    let cal = Calendar.current
    for i in 0..<14 {
        let date = cal.date(byAdding: .day, value: -i, to: .now) ?? .now
        context.insert(Transaction(title: "Grocery \(i)", amount: Double.random(in: 15...80),
                                   date: date, type: .expense, category: cat))
    }
    try? context.save()
    return NavigationStack {
        BudgetDetailView(budget: budget)
    }
    .modelContainer(container)
}
