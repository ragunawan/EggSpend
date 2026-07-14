import SwiftUI
import SwiftData

struct RecurringNext30DaysView: View {
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true }, sort: \RecurringTransaction.nextDueDate)
    private var recurring: [RecurringTransaction]

    private var occurrences: [RecurringOccurrence] {
        RecurringProjection.occurrences(from: recurring, start: .now, days: 30)
    }

    private var grouped: [(Date, [RecurringOccurrence])] {
        let calendar = Calendar.current
        let dict = Dictionary(grouping: occurrences) { calendar.startOfDay(for: $0.dueDate) }
        return dict.sorted { $0.key < $1.key }
    }

    private var incomeTotal: Double {
        occurrences.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var expenseTotal: Double {
        occurrences.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            NestBackground()

            List {
                summarySection
                if occurrences.isEmpty {
                    ContentUnavailableView {
                        Label("No Upcoming Recurring Items", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Active recurring transactions due in the next 30 days will appear here.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(grouped, id: \.0) { date, items in
                        Section {
                            ForEach(items) { occurrence in
                                occurrenceRow(occurrence)
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                .foregroundStyle(Color.twig)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Next 30 Days")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                summaryChip("Income", incomeTotal, Color.eggBlue, "arrow.down.circle.fill")
                summaryChip("Expenses", expenseTotal, Color.negative, "arrow.up.circle.fill")
                summaryChip("Net", incomeTotal - expenseTotal, incomeTotal >= expenseTotal ? Color.nestLeafGreen : Color.negative, "equal.circle.fill")
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func summaryChip(_ title: String, _ amount: Double, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(abs(amount), format: .currency(code: CurrencyFormat.code))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.nestBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .nestCard()
    }

    private func occurrenceRow(_ occurrence: RecurringOccurrence) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((occurrence.category?.color ?? Color.yolk).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: occurrence.category?.icon ?? occurrence.source.frequency.icon)
                    .foregroundStyle(occurrence.category?.color ?? Color.yolk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(occurrence.source.frequency.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yolk.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.yolk)
                    if let account = occurrence.account {
                        Label(account.name, systemImage: account.type.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            AmountLabel(amount: occurrence.amount, type: occurrence.type, font: .callout)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
    }
}

#Preview {
    NavigationStack {
        RecurringNext30DaysView()
            .modelContainer(PersistenceController.previewContainer())
    }
}
