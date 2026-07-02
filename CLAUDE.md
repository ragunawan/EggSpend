# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Focus

Work only on the EggSpend codebase in `/Users/ai/Documents/Dev/EggSpend`. Ignore sibling directories unless explicitly asked.

EggSpend is the repository name, Xcode project name, iOS app target, product name, test target, and shared scheme.

## Stack

- Swift 6, SwiftUI, SwiftData
- CloudKit-backed `ModelContainer` with automatic local fallback (no iCloud sign-in required)
- iOS Simulator / Xcode workflow

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
- `--preview-data` — seeds sample transactions, accounts, and budgets on launch
- `--tab <index>` — opens a specific root tab: `0` Home, `1` Transactions, `2` Budget, `3` Nest Egg, `4` Metrics

## Architecture

### Data layer

Five SwiftData `@Model` classes: `Transaction`, `TransactionCategory`, `Account`, `Budget`, `RecurringTransaction`. The schema is declared once in `EggSpendApp.swift` and shared with the `ModelContainer`.

**CloudKit enum pattern.** CloudKit does not support Swift enums as stored properties. All enums (`TransactionType`, `BudgetPeriod`, `RecurrenceFrequency`, `AccountType`) are stored as `String` rawValues (e.g. `typeRaw`, `periodRaw`) with computed wrappers that convert back. Always follow this pattern when adding enum fields to a persistent model.

**Amount sign convention.** `Transaction.amount` is always stored as a positive absolute value. Use `signedAmount` (positive for income, negative for expense) for arithmetic. `AccountBalanceService` relies on this.

### Business logic

Domain logic lives outside views in three locations:

- `EggSpend/Utilities/` — `CSVParser`, `AccountBalanceService`, `MonthlyReviewCalculator`
- `EggSpend/Views/Forecast/ForecastEngine.swift` — forecast math lives here (in Views/, not Utilities/)
- `EggSpend/Models/RecurringTransaction.swift` — `processRecurringTransactions(_:context:)` is a top-level function called from `EggSpendApp.onAppear` every launch; it generates `Transaction` records for every overdue due date and advances `nextDueDate`

**AccountBalanceService.** When creating, editing, or deleting a transaction that is linked to an account, you must call `AccountBalanceService.apply(_:to:)` or `AccountBalanceService.reverse(_:from:)` manually. The model does not auto-update balances.

**Budget category matching.** A `Budget` with `category == nil` matches transactions that also have no category (i.e. uncategorized spend), not all transactions. This is intentional — nil means "catch uncategorized".

**ForecastEngine.** Builds a 30/60/90-day cash-flow projection from: liquid balance (checking + savings only), average daily net flow from the last 60 days of transactions, and explicit upcoming recurring events. The forecast is directional — recurring transactions already materialized into history create mild double-counting with the daily drift. See comments in `ForecastEngine.swift` for the documented assumptions.

### Persistence & seeding

`PersistenceController` (an enum with static methods) handles two concerns:
- `seedDefaultCategoriesIfNeeded` — runs at every launch; idempotent (no-ops if categories exist)
- `previewContainer()` — returns an in-memory `ModelContainer` pre-populated with sample data; used in all `#Preview` blocks

### UI layer

`ContentView` is a `TabView` with five tabs. Each tab root is a `NavigationStack`. Views use `@Query` to subscribe to SwiftData and pass arrays down to utility/model methods for calculations rather than querying inside utilities.

**Theme.** All colors, gradients, and the `.nestCard()` view modifier are in `EggSpendTheme.swift`. Semantic colors: `.nestBrown` (brand), `.yolk` (primary interactive), `.eggBlue` (income/assets), `.nestLeafGreen` (positive), `.twig` (muted secondary), `.nestCream` (background tint). Use these — don't add one-off color literals.

## Development Notes

- When adding Swift files, keep both `EggSpend.xcodeproj/project.pbxproj` and `generate_project.py` in sync.
- Use `Decimal` or currency-safe formatting for any new money logic; avoid `Double` arithmetic for financial totals (the existing codebase uses `Double` — be intentional about extending that pattern).
- Tests use an in-memory `ModelContainer` set up in `setUpWithError` and torn down in `tearDownWithError`. Follow this pattern for new test classes.

## Implementation Backlog

These items are queued for Claude Code to implement. Keep changes scoped and follow the existing SwiftUI patterns in the referenced views.

### Upcoming Transaction Tile Border

Goal: In the Transactions tab, upcoming recurring transactions should be visually distinct with a dashed blue border around the tile.

Implementation plan:
- Locate upcoming row rendering in `EggSpend/Views/Transactions/TransactionsListView.swift`, specifically `LedgerRow.upcoming`, `rowView(for:)`, and the `UpcomingRecurringRowView` component in the same feature area.
- Add the dashed border only to upcoming recurring transaction tiles. Do not affect normal `TransactionRowView` rows or `TransferRowView` rows.
- Use the existing theme color `.eggBlue` for the border.
- Prefer a SwiftUI overlay with `RoundedRectangle(...).stroke(style: StrokeStyle(lineWidth: ..., dash: ...))` so the treatment composes with the existing tile background.
- Match the existing row corner radius and spacing so the border tracks the tile shape.
- Verify the Transactions tab still shows normal transactions, transfers, and upcoming rows correctly, and that delete remains disabled for upcoming rows.

### Home Carousel Scroll Progress

Goal: Add horizontal scroll progress indicators for the Savings Goals and Budget Eggs carousels on the Home view.

Implementation plan:
- Work in `EggSpend/Views/Dashboard/DashboardView.swift`.
- Locate `savingsGoalsPreviewSection` and `budgetPreviewSection`; both use horizontal `ScrollView` plus `HStack` tiles.
- Add a compact horizontal progress bar below each carousel that reflects scroll position across the full horizontal content width.
- Keep the indicator visually subtle and theme-aligned. Use `.eggBlue` for savings goals and `.yolk` or budget status-neutral styling for budget eggs.
- Prefer a reusable local helper view or small local component if both sections share the same mechanics.
- Preserve the existing tile sizes, spacing, section labels, navigation links, and empty state behavior.
- Make sure the progress bar is hidden or inert when content does not overflow horizontally.
- Verify on narrow and wide layouts that the progress indicator does not overlap tiles or add layout jump.

## Naming

- Repository/folder/project: `EggSpend`
- App target/product/scheme: `EggSpend`
- Test target: `EggSpendTests`
- App entry point: `EggSpendApp`
