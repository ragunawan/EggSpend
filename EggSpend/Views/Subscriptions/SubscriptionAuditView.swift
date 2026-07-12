import SwiftUI
import SwiftData

/// Reviews `Transaction` history for subscription-shaped spending
/// (`SubscriptionDetector`) and lets the user one-tap-convert a detected
/// merchant into an explicit `RecurringTransaction`. Detection-only — no
/// balances move here; see `SubscriptionDetector.conversionFields` doc.
struct SubscriptionAuditView: View {
    @Query(sort: \Transaction.date) private var transactions: [Transaction]
    @Query private var recurring: [RecurringTransaction]
    @Environment(\.modelContext) private var modelContext

    /// Keys already converted this session. `detected` re-derives its
    /// exclusion set from `recurring` on every SwiftData change, but that
    /// @Query refresh isn't necessarily synchronous with the tap that
    /// inserts the new `RecurringTransaction` — this is a belt-and-braces
    /// guard against a double-tap inserting two schedules for one cluster
    /// before the query catches up.
    @State private var trackedKeys: Set<String> = []

    /// 36 months of history, filtered in memory rather than via a
    /// `#Predicate` date range (repo precedent — see other windowed
    /// `@Query` call sites). A yearly-cadence subscription needs 3
    /// occurrences to be detected, and the detector's own gap window
    /// allows up to 369 days between charges, so the 1st-to-3rd-occurrence
    /// span can run up to ~24.3 months; 36 months leaves comfortable slack
    /// above that so a real yearly subscription with a slightly late
    /// renewal still clusters.
    private var windowedTransactions: [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -36, to: .now) ?? .distantPast
        return transactions.filter { $0.date >= cutoff }
    }

    /// `recurring` is intentionally NOT windowed — an old-but-still-active
    /// recurring item must keep suppressing re-detection of the same
    /// merchant no matter how long ago it was created.
    private var detected: [SubscriptionDetector.DetectedSubscription] {
        SubscriptionDetector.detect(transactions: windowedTransactions, recurring: recurring)
            .filter { !trackedKeys.contains($0.normalizedKey) }
    }

    var body: some View {
        ZStack {
            NestBackground()

            List {
                if !detected.isEmpty {
                    Section {
                        ForEach(detected) { item in
                            subscriptionRow(item)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("Detected from your transaction history")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Subscriptions")
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay {
            if detected.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Subscriptions Detected")
                    } icon: {
                        Image(systemName: "sparkle.magnifyingglass").symbolEffect(.pulse)
                    }
                } description: {
                    Text("Recurring-looking charges in your transaction history will appear here.")
                }
            }
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ item: SubscriptionDetector.DetectedSubscription) -> some View {
        HStack(spacing: 12) {
            // Everything except the Track button is static info, so it's
            // combined into one VoiceOver element. The Button below is kept
            // as a sibling OUTSIDE this combined element — `.combine` merges
            // descendants into a single non-interactive element and would
            // otherwise swallow the button's independent actionable trait,
            // leaving VoiceOver users with no way to invoke the only action
            // on the row.
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((item.category?.color ?? Color.yolk).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: item.category?.icon ?? item.cadence.icon)
                        .foregroundStyle(item.category?.color ?? Color.yolk)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.body).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Label(item.cadence.rawValue, systemImage: item.cadence.icon)
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.yolk.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.yolk)
                        if item.priceChanged {
                            // `priceChanged` fires for decreases too, not just
                            // increases — pick the icon/label by comparing the
                            // latest charge against the cluster's historical
                            // mode so a cheaper renewal doesn't show an
                            // up-arrow.
                            Label(
                                item.latestAmount > item.modeAmount ? "Price up" : "Price down",
                                systemImage: item.latestAmount > item.modeAmount ? "arrow.up" : "arrow.down"
                            )
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.warningTone.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.warningTone)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.monthlyCost, format: .currency(code: CurrencyFormat.code))
                        .font(.callout).fontWeight(.semibold)
                        .foregroundStyle(Color.nestBrown)
                    Text("≈ \(item.annualizedCost.formatted(.currency(code: CurrencyFormat.code)))/yr")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Button("Track") { track(item) }
                .buttonStyle(.borderedProminent)
                .tint(Color.yolk)
                .accessibilityLabel("Track \(item.title) as recurring")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
    }

    private func track(_ item: SubscriptionDetector.DetectedSubscription) {
        // Synchronous exclusion guard — see `trackedKeys` doc above.
        trackedKeys.insert(item.normalizedKey)

        let fields = SubscriptionDetector.conversionFields(for: item)
        let recurringItem = RecurringTransaction(
            title: fields.title,
            amount: fields.amount,
            type: fields.type,
            frequency: fields.frequency,
            startDate: fields.startDate,
            // `fields.nextDueDate` is intentionally unused — `RecurringTransaction.init`
            // always sets `nextDueDate = startDate`, so the tuple's separate
            // `nextDueDate` (equal to `startDate` here) would be redundant.
            category: item.category,
            // Passing an archived account here is harmless by design: this
            // only creates the schedule, and archiving affects account
            // display/reuse, not relationship validity. The account balance
            // is untouched until a real charge is later materialized.
            account: item.account
        )
        // No `AccountBalanceService` call: creating a recurring schedule
        // doesn't move money by itself (see `SubscriptionDetector.conversionFields`
        // doc) — balances only change once `processRecurringTransactions`
        // materializes a real `Transaction` from this schedule.
        modelContext.insert(recurringItem)
        // No explicit save — SwiftData autosaves, matching
        // `AddRecurringTransactionView`'s convention.
    }
}

#Preview {
    NavigationStack {
        SubscriptionAuditView()
            .modelContainer(for: [Transaction.self, RecurringTransaction.self, TransactionCategory.self], inMemory: true)
    }
}
