import SwiftUI
import SwiftData

struct SavingsGoalsView: View {
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddGoal = false
    @State private var editingGoal: SavingsGoal? = nil
    @State private var showCompleted = false

    // MARK: - Derived

    private var activeGoals: [SavingsGoal] { goals.filter { $0.status == .active } }
    private var completedGoals: [SavingsGoal] { goals.filter { $0.status == .completed } }

    private var totalTarget: Double { activeGoals.reduce(0) { $0 + $1.targetAmount } }
    private var totalSaved: Double { activeGoals.reduce(0) { $0 + $1.currentAmount } }
    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return min(max(totalSaved / totalTarget, 0), 1.0)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if goals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            summaryHeroCard
                            activeGoalsSection
                            completedGoalsSection
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(AnimatedCanopyBackground())
            .navigationTitle("Savings Goals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddGoal = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(Color.yolk)
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) { AddSavingsGoalView() }
            .sheet(item: $editingGoal) { goal in AddSavingsGoalView(editingGoal: goal) }
        }
    }

    // MARK: - Summary hero card

    @ViewBuilder
    private var summaryHeroCard: some View {
        if !activeGoals.isEmpty {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Nest Eggs in Progress", systemImage: "leaf.fill")
                            .font(.headline).foregroundStyle(Color.nestBrown)
                        Text("\(activeGoals.count) active goal\(activeGoals.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved").font(.caption).foregroundStyle(.secondary)
                        Text(totalSaved, format: .currency(code: "USD"))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.nestBrown)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Target").font(.caption).foregroundStyle(.secondary)
                        Text(totalTarget, format: .currency(code: "USD"))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.nestBrown.opacity(0.6))
                    }
                }

                AnimatedProgressBar(progress: overallProgress, color: .nestLeafGreen)

                Text("\(Int(overallProgress * 100))% of the way there")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .nestCard()
            .padding(.top, 4)
        }
    }

    // MARK: - Active goals

    @ViewBuilder
    private var activeGoalsSection: some View {
        if !activeGoals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(activeGoals) { goal in
                    SavingsGoalRowView(goal: goal)
                        .onTapGesture { editingGoal = goal }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(goal)
                            }
                            Button("Edit", systemImage: "pencil") { editingGoal = goal }
                                .tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Complete", systemImage: "checkmark.seal.fill") {
                                goal.status = .completed
                            }
                            .tint(.nestLeafGreen)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingGoal = goal }
                            Button("Mark Completed", systemImage: "checkmark.seal.fill") {
                                goal.status = .completed
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(goal)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Completed goals (collapsed by default)

    @ViewBuilder
    private var completedGoalsSection: some View {
        if !completedGoals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack {
                        Text("Completed (\(completedGoals.count))")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showCompleted {
                    ForEach(completedGoals) { goal in
                        SavingsGoalRowView(goal: goal)
                            .opacity(0.7)
                            .onTapGesture { editingGoal = goal }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(goal)
                                }
                                Button("Edit", systemImage: "pencil") { editingGoal = goal }.tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Reactivate", systemImage: "arrow.counterclockwise") {
                                    goal.status = .active
                                }
                                .tint(.yolk)
                            }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Savings Goals Yet")
            } icon: {
                Image(systemName: "leaf").symbolEffect(.pulse)
            }
        } description: {
            Text("Hatch a new nest egg.\nTap + to set your first savings goal.")
        } actions: {
            Button { showAddGoal = true } label: {
                Label("Add Goal", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).tint(Color.nestBrown)
        }
    }
}

// MARK: - Savings goal row card

struct SavingsGoalRowView: View {
    let goal: SavingsGoal

    private var goalColor: Color { Color(hex: goal.colorHex) ?? .yolk }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                EggProgressView(progress: goal.progress, size: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: goal.icon).font(.caption).foregroundStyle(goalColor)
                        Text(goal.name)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if goal.isCompleted {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2).foregroundStyle(Color.nestLeafGreen)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(goal.currentAmount, format: .currency(code: "USD"))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("of").font(.caption).foregroundStyle(.secondary)
                        Text(goal.targetAmount, format: .currency(code: "USD"))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        if goal.tracksLinkedAccount, let account = goal.linkedAccount {
                            Label(account.name, systemImage: "link")
                                .font(.caption2).foregroundStyle(Color.eggBlue)
                                .lineLimit(1)
                        }
                        if let daysRemaining = goal.daysRemaining, !goal.isCompleted {
                            Text(dateLabel(for: daysRemaining))
                                .font(.caption2)
                                .foregroundStyle(daysRemaining < 0 ? .red : Color.twig)
                        }
                    }

                    Text(goal.monthlySavingsLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(goal.isGoalMet ? Color.nestLeafGreen : Color.twig)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            AnimatedProgressBar(progress: goal.progress, color: goal.statusColor, height: 3)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(goal.statusColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
    }

    private func dateLabel(for daysRemaining: Int) -> String {
        if daysRemaining < 0 { return "\(-daysRemaining)d overdue" }
        if daysRemaining == 0 { return "Due today" }
        return "\(daysRemaining)d left"
    }
}

#Preview {
    SavingsGoalsView()
        .modelContainer(PersistenceController.previewContainer())
}
