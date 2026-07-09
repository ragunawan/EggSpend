import SwiftUI
import SwiftData
import UserNotifications

@main
struct EggSpendApp: App {
    static let (modelContainer, syncStatus): (ModelContainer, SyncStatus) = {
        let schema = Schema([
            Transaction.self,
            TransactionCategory.self,
            Account.self,
            Budget.self,
            RecurringTransaction.self,
            SavingsGoal.self,
            Transfer.self,
            BalanceSnapshot.self
        ])
        // Attempt CloudKit sync; fall back to local on failure (e.g. no iCloud sign-in)
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)]
            )
            return (container, .cloudKitActive)
        } catch {
            print("CloudKit ModelContainer init failed, falling back to local-only store: \(error)")
            let fallback = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)]
            )
            return (fallback, .localOnly(reason: error.localizedDescription))
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let ctx = ModelContext(Self.modelContainer)
                    PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: Self.modelContainer)
                    if ProcessInfo.processInfo.arguments.contains("--preview-data") {
                        PersistenceController.seedPreviewTransactionsIfNeeded(modelContainer: Self.modelContainer)
                    }
                    // Process any overdue recurring transactions on every launch
                    let recurring = (try? ctx.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
                    processRecurringTransactions(recurring, context: ctx)
                    // Snapshot today's balances only after recurring transactions have
                    // been applied above, so the snapshot reflects the settled balance.
                    captureBalanceSnapshots(context: ctx)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    let ctx = ModelContext(Self.modelContainer)
                    captureBalanceSnapshots(context: ctx)
                }
        }
        .modelContainer(Self.modelContainer)
    }

    /// Captures today's per-account balance snapshot. Shared by the initial
    /// `onAppear` and every `scenePhase` transition back to `.active`, so a
    /// day-rollover while the app is backgrounded is caught the moment the app
    /// is foregrounded again, not just at process launch.
    private func captureBalanceSnapshots(context: ModelContext) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        BalanceSnapshotService.captureIfNeeded(accounts: accounts, context: context)
    }
}
