# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Focus

Work only on the EggSpend codebase (this repository). Ignore sibling directories unless explicitly asked.

EggSpend is the repository name, Xcode project name, iOS app target, product name, test target, and shared scheme.

## Stack

- Swift 6, SwiftUI, SwiftData
- CloudKit-backed `ModelContainer` with automatic local fallback (no iCloud sign-in required)
- iOS 26.0+, Xcode 26.6, iPhone 17 simulator workflow

## Common Commands

```bash
# Build
xcodebuild build -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'

# Run all tests
xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'

# Run a single test class
xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EggSpendTests/BudgetTests

# Run a single test method
xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EggSpendTests/BudgetTests/testBudgetSpentCalculation

# Open in Xcode
open EggSpend.xcodeproj
```

Launch arguments (pass in Xcode scheme or via `ProcessInfo`):
- `--preview-data` — seeds sample transactions, accounts, and budgets on launch; also skips onboarding
- `--tab <index>` — opens a specific root tab: `0` Home, `1` Transactions, `2` Budget, `3` Nest Egg, `4` Metrics

## Architecture

### Data layer

Nine SwiftData `@Model` classes: `Transaction`, `TransactionCategory`, `Account`, `Budget`, `RecurringTransaction`, `SavingsGoal`, `Transfer`, `BalanceSnapshot`, `CategoryRule`. The schema is declared once in `EggSpendApp.swift` and shared with the `ModelContainer`.

**UUID references.** `BalanceSnapshot.accountID` and `CategoryRule.categoryID` store raw UUIDs (not `@Relationship`) — deliberate: a deleted or archived `Account`/`TransactionCategory` must not cascade-nullify snapshot history or learned rules. Dangling IDs are tolerated on read (resolve against live rows; no match = no match). Follow this pattern for any new history-preserving reference.

**CloudKit enum pattern.** CloudKit does not support Swift enums as stored properties. All enums (`TransactionType`, `BudgetPeriod`, `RecurrenceFrequency`, `AccountType`) are stored as `String` rawValues (e.g. `typeRaw`, `periodRaw`) with computed wrappers that convert back. Always follow this pattern when adding enum fields to a persistent model.

**Amount sign convention.** `Transaction.amount` is always stored as a positive absolute value. Use `signedAmount` (positive for income, negative for expense) for arithmetic. `AccountBalanceService` relies on this.

### Business logic

Domain logic lives outside views in:

- `EggSpend/Utilities/` — `CSVParser`, `AccountBalanceService`, `MonthlyReviewCalculator`, `NetWorthCalculator`, `SafeSpendCalculator`, `RecurringProjection`, `TransactionFilter`, `AmountParser`, `DebtPayoffCalculator`, `CurrencyFormat`, `DataExporter`, `BalanceSnapshotService`, `SubscriptionDetector`, `CategoryRuleEngine`, `SpendingDeltaCalculator`, `NarrativeGenerator`, `AppLockController`, `TransactionGrouping`, `DuplicateSweeper`, `TransactionEntryService`, `TransferBalanceService`, `BudgetAlertCoordinator`, `NotificationScheduler`
- `EggSpend/Views/Forecast/ForecastEngine.swift` — forecast math lives here (in Views/, not Utilities/)
- `EggSpend/Models/RecurringTransaction.swift` — `processRecurringTransactions(_:context:)` is a top-level function called from `EggSpendApp.onAppear`; it generates `Transaction` records for every overdue due date and advances `nextDueDate`

**Launch sequence.** `EggSpendApp.onAppear` runs: seed default categories → (seed preview data if `--preview-data`) → processRecurringTransactions → DuplicateSweeper.sweep (cloud sync self-heal) → captureBalanceSnapshots. Balance snapshots are also re-captured on every `scenePhase` transition back to `.active`, so day rollovers while backgrounded are caught on foreground.

**AccountBalanceService.** When creating, editing, or deleting a transaction that is linked to an account, you must call `AccountBalanceService.apply(_:to:)` or `AccountBalanceService.reverse(_:from:)` manually. The model does not auto-update balances. `TransferBalanceService.apply/reverse` is the equivalent for `Transfer` (debits fromAccount, credits toAccount).

**TransactionEntryService.** The shared creation path for transactions (used by AddTransactionView and QuickAdd). It trims input, inserts the model, applies the account balance, and runs the budget-alert check — prefer it over inserting `Transaction` directly from a view.

**Budget alerts & notifications.** `BudgetAlertCoordinator.checkBudgets` must be called after any transaction mutation that could move a budget's spend; it fires threshold notifications via `NotificationScheduler`. Notification code depends on `NotificationCenterProtocol` (a testable abstraction over `UNUserNotificationCenter`) — inject it rather than calling the real center in logic/tests.

**Budget category matching.** A `Budget` with `category == nil` matches transactions that also have no category (i.e. uncategorized spend), not all transactions. This is intentional — nil means "catch uncategorized".

**ForecastEngine.** Builds a 30/60/90-day cash-flow projection from: liquid balance (checking + savings only), average daily net flow from the last 60 days of transactions, and explicit upcoming recurring events. The forecast is directional — recurring transactions already materialized into history create mild double-counting with the daily drift. See comments in `ForecastEngine.swift` for the documented assumptions.

### Persistence & seeding

`PersistenceController` (an enum with static methods) handles two concerns:
- `seedDefaultCategoriesIfNeeded` — runs at every launch; idempotent (no-ops if categories exist)
- `previewContainer()` — returns an in-memory `ModelContainer` pre-populated with sample data; used in all `#Preview` blocks

**@AppStorage keys.** Settings and onboarding state keys are owned by their feature files: `SettingsView.aiNarrativeStorageKey`, `SettingsView.appLockStorageKey`, `SettingsView.appearanceStorageKey`, `OnboardingView.hasCompletedOnboardingKey`.

### UI layer

`ContentView` is a `TabView` with five tabs. Each tab root is a `NavigationStack`. Views use `@Query` to subscribe to SwiftData and pass arrays down to utility/model methods for calculations rather than querying inside utilities.

**Theme.** All colors, gradients, and the `.nestCard()` view modifier are in `EggSpendTheme.swift`. Semantic colors: `.nestBrown` (brand), `.yolk` (primary interactive), `.eggBlue` (income/assets), `.nestLeafGreen` (positive), `.twig` (muted secondary), `.nestCream` (background tint). Use these — don't add one-off color literals.

**Redesign structure.** The five-tab UI is Home, Transactions, Budget, Nest Egg, and Metrics. `LedgerRowView` is the single ledger row component for transactions, transfers, and upcoming recurring occurrences. The old standalone `AccountsView.swift` root screen was retired; account and liability management now lives under Nest Egg plus Settings -> Manage links.

## Development Notes

- When adding Swift files, keep both `EggSpend.xcodeproj/project.pbxproj` and `generate_project.py` in sync (now also registers resources: PrivacyInfo.xcprivacy, Localizable.xcstrings).
- Use `Decimal` or currency-safe formatting for any new money logic; avoid `Double` arithmetic for financial totals (the existing codebase uses `Double` — be intentional about extending that pattern).
- Tests use an in-memory `ModelContainer` set up in `setUpWithError` and torn down in `tearDownWithError`. Follow this pattern for new test classes. Test suite has ~500 XCTest cases across 31 files; every test file includes the 9-model schema list.
- Loop/agent working docs live at the repo root (`IMPLEMENTATION_PLAN.md`, `AGENT_LOOP_LOG.md`, `BUGS_AND_RISKS.md`, `FEATURE_BACKLOG.md`, `CHANGELOG.md`, `TODO.md`) — keep them updated when completing tracked tasks.

## Running & Screenshots

There is no XCUITest UI target and no `idb`/`cliclick` in this environment,
so Simulator interaction goes through `xcrun simctl` directly (build, install,
`simctl launch ... --preview-data --tab <n>`, `simctl io ... screenshot`).
This can launch into any tab and screenshot it, but **cannot tap, type, or
scroll** — synthetic input (AppleScript UI scripting or `CGEventPost`) is
blocked without an interactive Accessibility permission grant.

Use `xcrun simctl ui <udid> content_size <category>` (e.g. `accessibility-extra-extra-extra-large`) to verify Dynamic Type rendering on this Xcode version.

`scripts/capture_screenshots.sh <simulator-udid> <output-dir> [w h]` rebuilds
the app, installs it on the given simulator, and captures the five primary
App Store screenshots (Home/Transactions/Budget/Nest Egg/Metrics) via the
`--tab` launch argument, optionally resizing to exact target pixel
dimensions. Used to regenerate `screenshots/iphone-6.3/` and
`screenshots/ipad-13/` — see `screenshots/README.md` for the device/size
mapping. The `alternates-*` screenshot variants in that directory were
captured under some other, undocumented text/accessibility setting; don't
try to regenerate those without confirming what that setting was first.

## Naming

- Repository/folder/project: `EggSpend`
- App target/product/scheme: `EggSpend`
- Test target: `EggSpendTests`
- App entry point: `EggSpendApp`
