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
            BalanceSnapshot.self,
            CategoryRule.self
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
    @State private var appLock = AppLockController()
    @AppStorage(OnboardingView.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(SettingsView.appearanceStorageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Screenshot/preview-data launches should never show onboarding —
        // flip the flag before `body` renders so there's no first-frame flash.
        if ProcessInfo.processInfo.arguments.contains("--preview-data") {
            UserDefaults.standard.set(true, forKey: OnboardingView.hasCompletedOnboardingKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            // Wrapped in `Group` so the onboarding cover attaches to a
            // presentation context distinct from the lock `fullScreenCover`
            // below — two `.fullScreenCover`s on the same node is unreliable.
            // No extra ordering logic is needed between the two covers:
            // lock defaults off at fresh install, so onboarding presents
            // uncontested — and this isn't just a default-value coincidence.
            // The lock toggle lives in `SettingsView`, reachable only via a
            // sheet from `DashboardView`, one of `ContentView`'s tabs; and
            // `ContentView` itself is entirely hidden behind this Group's
            // onboarding cover until `hasCompletedOnboarding` flips true. So
            // there's no UI path to enable the lock while onboarding is
            // showing — the user simply can't reach the toggle to create the
            // conflict this comment is reasoning about.
            Group {
                ContentView()
                    .environment(appLock)
                    .onAppear {
                        let ctx = ModelContext(Self.modelContainer)
                        PersistenceController.seedDefaultCategoriesIfNeeded(modelContainer: Self.modelContainer)
                        if ProcessInfo.processInfo.arguments.contains("--preview-data") {
                            PersistenceController.seedPreviewTransactionsIfNeeded(modelContainer: Self.modelContainer)
                        }
                        // Process any overdue recurring transactions on every launch
                        let recurring = (try? ctx.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
                        processRecurringTransactions(recurring, context: ctx)
                        // Sweep any cross-device duplicate generated transactions after
                        // materialization but before snapshotting, so the day's balance
                        // snapshot reflects the corrected (post-sweep) balance.
                        DuplicateSweeper.sweep(context: ctx)
                        // Snapshot today's balances only after recurring transactions have
                        // been applied above, so the snapshot reflects the settled balance.
                        captureBalanceSnapshots(context: ctx)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        switch newPhase {
                        case .background:
                            // Arms the lock (a no-op when the Settings toggle is off).
                            appLock.sceneDidEnterBackground()
                        case .active:
                            let ctx = ModelContext(Self.modelContainer)
                            captureBalanceSnapshots(context: ctx)
                            Task { await appLock.sceneDidBecomeActive() }
                        case .inactive:
                            // Deliberately no-op: the Face ID system prompt itself
                            // transitions the scene through `.inactive` before
                            // returning to `.active`. Arming or re-checking the
                            // lock here would produce a re-lock loop around the
                            // very prompt meant to clear it (see AppLockController).
                            break
                        @unknown default:
                            break
                        }
                    }
                    // Synchronous backstop for the cold-launch case: `.overlay`
                    // composites in the same SwiftUI transaction as `ContentView`
                    // itself (zero-frame gap), whereas `.fullScreenCover` below
                    // bridges through UIKit `present(_:animated:)` and only
                    // mounts after `ContentView`'s hosting controller exists and
                    // lays out — with the lock armed at cold launch, real
                    // financial content could otherwise composite for a frame
                    // (or more, given `onAppear`'s synchronous data work above)
                    // before the cover appears. No sheet can be open yet at cold
                    // launch, so a plain overlay fully covers that case.
                    .overlay {
                        if appLock.isLocked {
                            LockScreenView(controller: appLock)
                                .onAppear {
                                    Task { await appLock.authenticate() }
                                }
                        }
                    }
                    // Covers the entire app, including any already-open sheet
                    // (e.g. `SettingsView`), whenever the app is locked — the
                    // only pure-SwiftUI mechanism that reliably sits on top of a
                    // sheet already on screen when the scene backgrounds. Not
                    // swipe-dismissible by default; `interactiveDismissDisabled`
                    // makes that explicit so the cover can only clear via a
                    // successful `authenticate()` flipping `isLocked` to false.
                    //
                    // Interplay with the overlay above: at cold launch both the
                    // overlay and this cover can be visible simultaneously
                    // (identical `LockScreenView` content, so no visible
                    // difference) until the cover finishes presenting, after
                    // which it simply sits on top of the overlay. Both mount
                    // their own `onAppear`-triggered `authenticate()` call, but
                    // `AppLockController.authenticate()`'s `authInFlight` guard
                    // is checked and set synchronously on `@MainActor` before
                    // any suspension point, so whichever trigger runs first wins
                    // and the second call returns immediately — no double
                    // system prompt. See `AppLockControllerTests` for coverage
                    // of that guard.
                    //
                    // v1 limitation: the app-switcher snapshot itself may briefly
                    // show a frame of content underneath — this covers the live
                    // return-to-app path (the acceptance bar), not the OS
                    // snapshot. True snapshot privacy would need a separate
                    // UIKit overlay window, out of scope for this task.
                    .fullScreenCover(isPresented: Binding(
                        get: { appLock.isLocked },
                        set: { _ in /* only AppLockController.authenticate() clears the lock */ }
                    )) {
                        LockScreenView(controller: appLock)
                            .interactiveDismissDisabled()
                            .onAppear {
                                Task { await appLock.authenticate() }
                            }
                    }
            }
            // Distinct presentation context from the lock cover above (see
            // comment at the top of this `Group`). The `set` is a no-op —
            // `OnboardingView` itself flips `hasCompletedOnboarding` to
            // dismiss.
            .fullScreenCover(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { _ in }
            )) {
                OnboardingView()
            }
            .preferredColorScheme(selectedAppearance.colorScheme)
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
