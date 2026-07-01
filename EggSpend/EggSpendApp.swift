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
            SavingsGoal.self
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
                }
        }
        .modelContainer(Self.modelContainer)
    }
}
