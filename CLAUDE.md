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

## Todo

### 1. Optional bill due date for credit card accounts and loans

Goal: `Account` records whose type is `.credit` or `.loan` can store an optional due date, while checking, savings, investment, and other accounts do not show that field.

Implementation plan:
- Update `EggSpend/Models/Account.swift` with a CloudKit-compatible optional `Date?` property, e.g. `var billDueDate: Date?`.
- Update the `Account` initializer to accept `billDueDate: Date? = nil` and assign it.
- In `EggSpend/Views/Accounts/AddAccountView.swift`, add state for `hasBillDueDate` and `billDueDate`.
- Show a bill due date section only when `selectedType` is `.credit` or `.loan`. Use a `Toggle` for enabling the optional value and a `DatePicker` with `.date` components when enabled.
- When `selectedType` changes away from `.credit` or `.loan`, clear the optional due date state so non-bill accounts do not persist stale bill dates.
- In `save()`, write `account.billDueDate = hasBillDueDate ? billDueDate : nil` for credit/loan accounts and always write `nil` for all other types.
- In `populateIfEditing()`, restore the existing optional due date and toggle state for credit/loan accounts.
- Consider displaying the due date in account row/detail UI if there is already a concise place for account metadata, such as account rows in `AccountsView` or `NetWorthView`.
- Add or update account model tests to verify credit/loan accounts can persist a due date and non-bill account saves clear it.

Verification:
- Build the app with `xcodebuild build -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Run relevant account/model tests, or the full test suite if the schema change touches CloudKit tests.

### 2. Shorten the account field in the edit transaction view

Goal: In `AddTransactionView` while editing a transaction, the account selector should not consume most of the screen width.

Implementation plan:
- Inspect `EggSpend/Views/Transactions/AddTransactionView.swift`, especially `accountSection`.
- Replace the full-width default `Picker("Account", selection:)` presentation with a more compact control. Good options:
  - Apply `.pickerStyle(.menu)` so the row shows a compact menu value instead of expanding visually.
  - Or build an `HStack` with `Text("Account")`, `Spacer()`, and a trailing menu picker constrained with `.frame(maxWidth: 220, alignment: .trailing)` and `.lineLimit(1)`.
- Keep the current `Optional<Account>.none` tag and account tags so SwiftData model selection still works.
- Use the same compact selector for both add and edit modes unless there is a strong reason to special-case editing.
- Confirm long account names truncate instead of pushing other content off screen.

Verification:
- Preview or run `AddTransactionView` with preview data and edit a transaction with a long account name.
- Confirm saving still reverses/applies account balance correctly through the existing `AccountBalanceService` calls.

### 3. Make transactions one scrollable field on the transaction page

Goal: `TransactionsListView` should present the transaction rows inside a single bounded scrollable area instead of letting the list dominate the whole screen.

Implementation plan:
- Work in `EggSpend/Views/Transactions/TransactionsListView.swift`.
- Keep the existing search, filter banner, empty states, grouping by date, navigation links, and swipe-to-delete behavior.
- Wrap the populated transaction list in one visually bounded scroll container/card, using existing theme primitives such as `.nestCard()` and semantic colors.
- Prefer retaining `List` if swipe actions and deletion are important, but constrain it inside a single container with a stable `frame`/layout so it reads as one scrollable field.
- If converting to `ScrollView` + `LazyVStack`, reimplement row actions carefully because SwiftUI `swipeActions` are `List`-oriented. Do not drop delete/edit affordances without replacing them.
- Ensure the filter banner remains outside or above the scrollable transaction field so the list itself is the only scrolling transaction area.
- Check that date section headers still separate grouped transactions clearly.

Verification:
- Test with empty, filtered-empty, and many-transaction preview data.
- Confirm search and filters still update the one scrollable field.
- Confirm delete still reverses account balance via `deleteTransactions(_:at:)`.

### 4. Make budgets one scrollable field on the budget page

Goal: `BudgetView` should present all budget rows inside one scrollable field while keeping the summary and period filter readable.

Implementation plan:
- Work in `EggSpend/Views/Budget/BudgetView.swift`.
- Keep `summaryHeroCard` and `periodPicker` near the top of the page.
- Move the budget groups (`overBudget`, `warningBudgets`, `healthyBudgets`, and inactive budgets) into a single bounded scrollable container/card below the summary/filter.
- Preserve existing grouping headings, navigation to `BudgetDetailView`, edit/delete/pause/resume actions, and inactive budget expansion.
- If the current `ScrollView` remains the outer page scroll, avoid nested unbounded scroll views. Use a fixed or geometry-based height for the budgets field, or make the top-level layout a `VStack` with only the budgets field scrolling.
- Keep the existing `BudgetRowView` styling and avoid adding nested card-on-card visuals.

Verification:
- Test no budgets, only active budgets, mixed status budgets, and inactive budgets expanded.
- Confirm period filtering updates the single scrollable budget field.
- Confirm swipe/context menu actions still work.

### 5. Move happened recurring events into the main transaction list

Goal: When a recurring transaction's `nextDueDate` has happened, create the corresponding single `Transaction` in the main transactions list.

Current behavior:
- `EggSpend/Models/RecurringTransaction.swift` already has `processRecurringTransactions(_:context:)`.
- It generates a `Transaction` for every overdue `nextDueDate`, marks it `isGenerated = true`, inserts it into SwiftData, advances `nextDueDate`, saves, and checks budgets.
- `EggSpendApp.onAppear` calls this processor on launch.

Implementation plan:
- Preserve the existing processor as the source of truth for materializing overdue recurring events.
- Audit whether `processRecurringTransactions(_:context:)` is called often enough. If users can keep the app open across a due date, consider also calling it when `TransactionsListView` appears or when `RecurringTransactionsView` saves/edits a recurring item.
- Add a duplicate-prevention strategy before inserting generated transactions. Options:
  - Add a persisted source identifier/date pair to `Transaction`, such as `recurringSourceID: UUID?` and `recurringDueDate: Date?`.
  - Or query by title, amount, type, generated flag, and same calendar day, though this is weaker.
- If adding source metadata, update `Transaction` initializer with optional defaults and use it in `processRecurringTransactions`.
- If recurring items should affect account balances, add an optional account relationship to `RecurringTransaction`; otherwise leave generated transactions accountless and document that behavior.
- Keep budget checking after insertion because generated expenses should count toward budgets.

Verification:
- Extend `EggSpendTests/RecurringTransactionTests.swift` to assert an overdue item creates one generated transaction dated at the due date and advances `nextDueDate`.
- Add a test that reprocessing the same item does not duplicate an already-generated due occurrence.
- Run recurring transaction tests.

### 6. Show next-week recurring events in the main transaction list with `.eggBlue` outline

Goal: A recurring event due within the next seven days should appear in `TransactionsListView` as a single upcoming transaction row with an `.eggBlue` outline, without being permanently saved as a normal transaction until the due date happens.

Implementation plan:
- Model this as a display projection, not a persisted `Transaction`, to avoid polluting history and budget calculations with future transactions.
- Add a lightweight view model in or near `TransactionsListView`, for example:
  - `TransactionListItem` with cases `.actual(Transaction)` and `.upcoming(RecurringTransaction)`.
  - Computed fields for title, amount, date, type, category, account, notes, and `isUpcoming`.
- Add an `@Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true }, sort: \RecurringTransaction.nextDueDate)` to `TransactionsListView`.
- Build `upcomingRecurring` from recurring items whose `nextDueDate` is after now and no more than seven days from now, respecting `endDate`.
- Merge actual transactions and upcoming projections into one sorted list before applying grouping. Upcoming rows should sort by their due date, so near-future items appear in the correct date section.
- Update filtering/search logic so upcoming rows participate in title, notes, category, account, type, and amount filters as much as the existing `TransactionFilter` API allows. If `TransactionFilter` only accepts `Transaction`, add helper matching logic or create a shared filterable protocol/view model.
- Update `TransactionRowView` to accept an optional presentation flag, e.g. `isUpcoming: Bool = false`, and draw an `.eggBlue` rounded rectangle stroke when true. Keep existing row appearance for actual transactions.
- For upcoming rows, navigate to `RecurringTransactionsView` or an edit recurring detail view rather than `TransactionDetailView`, since no saved `Transaction` exists yet.
- Ensure upcoming projections are not deletable with `deleteTransactions(_:at:)`. If using `List`, separate delete handlers by actual transaction sections/items only.
- When the due date arrives, `processRecurringTransactions` should create the actual transaction and advance `nextDueDate`; after refresh, the upcoming projection for that occurrence should disappear and the actual generated transaction should remain.

Verification:
- Add tests around any pure helper that computes next-week upcoming recurring items.
- Manually verify with preview data: one overdue recurring item, one due in the next seven days, and one due later than seven days.
- Confirm the overdue item appears as an actual generated transaction, the next-week item appears with an `.eggBlue` outline, and the later item does not appear in the main transactions list.

### 7. Add transfer transactions

Goal: Support moving money between two accounts without counting the movement as income or expense.

Implementation plan:
- Extend the transaction model carefully. Options:
  - Add a third `TransactionType.transfer` case and store `fromAccount`/`toAccount` relationships.
  - Or add a dedicated `Transfer` model that creates linked balancing transactions. Prefer the simpler model only if it keeps reports and budgets correct.
- Update `TransactionType`-dependent UI and logic so transfers are excluded from budget spending, income/expense totals, and category requirements.
- Update `AddTransactionView` with a transfer mode that requires source account, destination account, amount, and date.
- Update `AccountBalanceService` to subtract from the source account and add to the destination account, with safe reversal when editing/deleting.
- Update `TransactionRowView`, transaction detail, filters, CSV import assumptions, metrics, monthly review, forecast, and safe-to-spend calculations so transfers do not distort cash flow.
- Add tests for creating, editing, and deleting transfers, including balance reversal and exclusion from budgets.

Verification:
- Run transaction, budget, metrics, monthly review, forecast, and account balance tests.
- Manually verify a transfer changes both account balances but does not appear as spending or income.

### 8. Add recurring transaction account assignment

Goal: Recurring transactions can be linked to an account so generated transactions update the correct account balance.

Implementation plan:
- Add an optional `account: Account?` relationship to `RecurringTransaction`.
- Update `AddRecurringTransactionView` with an account picker matching the transaction account picker pattern.
- When `processRecurringTransactions(_:context:)` generates a `Transaction`, pass `account: item.account`.
- After inserting each generated transaction, call `AccountBalanceService.apply(_:to:)` for the generated transaction's account.
- If duplicate prevention is added for generated recurring transactions, ensure account balance is not applied twice.
- Show the linked account in `RecurringTransactionsView` rows when present.
- Update preview data to include at least one recurring item linked to an account.

Verification:
- Add recurring transaction tests for generated account-linked expenses and income.
- Confirm generated recurring transactions appear in the main list with the account badge and update account balances exactly once.

### 9. Add a next 30 days recurring transactions view

Goal: Add a view that shows upcoming recurring income and expenses for the next 30 days.

Implementation plan:
- Add a new SwiftUI view, e.g. `EggSpend/Views/Recurring/RecurringNext30DaysView.swift`.
- Compute upcoming occurrences for active recurring items from today through 30 days out, respecting frequency and `endDate`.
- Show each occurrence as a dated row with title, amount, type, category, and account if recurring account assignment exists.
- Group rows by date or week for scanability.
- Add summary totals for upcoming income, upcoming expenses, and net impact over the 30-day window.
- Link to this view from `RecurringTransactionsView` and optionally from the transaction toolbar or dashboard.
- Keep this view read-only unless there is a clear edit target; tap rows can navigate to edit the source recurring transaction.
- Add a pure helper for generating upcoming occurrences so it can be tested without UI.

Verification:
- Test daily, weekly, biweekly, monthly, and yearly recurrence projection across a 30-day window.
- Confirm inactive and ended recurring transactions are excluded.

### 10. Add a debt payoff planner

Goal: For credit card and loan accounts, estimate payoff timelines and payment strategies.

Implementation plan:
- Extend `Account` for liability-specific planning fields as needed, such as optional APR, minimum payment, and planned extra payment. Keep them optional and relevant only for `.credit` and `.loan`.
- Add UI in `AddAccountView` to capture liability planning fields for credit card and loan accounts.
- Add a payoff calculator utility that takes balance, APR, monthly payment, and optional extra payment and returns months to payoff, total interest, and payoff date.
- Handle edge cases explicitly: zero APR, missing APR, payment too low to cover interest, and already-paid-off balances.
- Add a `DebtPayoffPlannerView` reachable from account detail/net worth liability sections.
- Consider strategy summaries such as avalanche/snowball only after the single-account calculator is correct.
- Use `Decimal` where practical for payoff calculations, or document why existing `Double` conventions are being followed.

Verification:
- Add unit tests for payoff math, including zero interest, high interest, insufficient payment, and extra payment scenarios.
- Manually verify displayed dates and currency formatting for credit card and loan accounts.

### 11. Add a cash flow calendar

Goal: Show actual transactions, upcoming recurring events, bills, and forecasted daily cash position in a calendar-style view.

Implementation plan:
- Add a calendar view under the forecast or transactions area, e.g. `EggSpend/Views/Forecast/CashFlowCalendarView.swift`.
- Combine actual transactions, recurring projections, account bill due dates, and optional forecast data into one daily timeline.
- Reuse the recurrence occurrence helper from the next 30 days view so upcoming recurring behavior is consistent.
- Show daily net cash flow and a running projected balance using liquid accounts from `ForecastEngine`.
- Use semantic color coding: income/assets in `.eggBlue`, expenses/liabilities in red or existing theme colors, and neutral transfers separately if transfer support exists.
- Add navigation from the dashboard, forecast view, or transaction toolbar.
- Keep the initial version month-based and read-only; editing can route to the underlying transaction, recurring transaction, or account.

Verification:
- Test that actual transactions and upcoming recurring projections appear on the correct dates.
- Confirm transfers are neutral once transfer transactions exist.
- Confirm bill due dates for credit cards and loans appear without changing cash balance unless a payment transaction exists.

### 12. Make homepage savings goals and budget eggs horizontal scroll tiles

Goal: On the homepage, savings goals and budget eggs should be horizontally scrollable tile rows. Remove manage buttons and make each tile navigate to the appropriate manage/detail view.

Implementation plan:
- Work in `EggSpend/Views/Dashboard/DashboardView.swift`.
- Find the existing savings goals and budget preview sections.
- Replace vertical lists or static previews with horizontal `ScrollView(.horizontal)` sections using compact tiles.
- Remove visible manage buttons from those sections.
- Wrap each budget tile in a `NavigationLink` to `BudgetDetailView` or `BudgetView`, depending on whether the tile represents one budget or the full manage view.
- Wrap each savings goal tile in a `NavigationLink` to the savings goal detail/manage view if one exists; otherwise route to `SavingsGoalsView`.
- Keep row height stable and make tiles wide enough for name, progress, target/current amount, and status without text clipping.
- Preserve dashboard empty states and avoid nested card visuals.

Verification:
- Test with zero, one, and several budgets/goals.
- Confirm horizontal scroll works and every tile navigates to the intended manage/detail view.
- Confirm no manage buttons remain in those homepage sections.

### 13. Calculate monthly savings needed for each savings goal

Goal: For each savings goal, calculate how much needs to be saved per month to hit the target by the target date.

Implementation plan:
- Inspect `EggSpend/Models/SavingsGoal.swift`, `SavingsGoalsView`, and `AddSavingsGoalView`.
- Add a computed property or utility function that calculates:
  - remaining amount = max(target amount - current saved amount, 0)
  - months remaining between today and target date
  - required monthly savings = remaining amount / months remaining
- Define month calculation clearly. Prefer calendar-aware month counting, with a minimum divisor of `1` when the target date is in the current month but not yet passed.
- Handle completed goals, missing target dates if allowed, and past target dates.
- Show the monthly required amount on savings goal tiles, savings goal rows, and any goal detail screen.
- Use clear labels such as "Save $X/mo" or "Target reached" for completed goals.
- Add tests for future target date, current-month target date, past target date, and already-complete goal.

Verification:
- Run savings goal tests or add a new focused test class.
- Manually verify dashboard and savings goal list formatting with preview data.

### 14. Refine background animations

Goal: Remove the horizontal scrolling square/light animation and make the background a static gradient from the top to the middle of the screen. Make leaves drift randomly down instead of falling vertically straight down.

Implementation plan:
- Work in `EggSpend/Views/Components/AnimatedCanopyBackground.swift` and `EggSpend/Views/Components/FloatingLeavesView.swift`.
- In `AnimatedCanopyBackground`, remove the `lightOffset` state and the `.onAppear` animation that moves the radial light horizontally.
- Replace the moving radial light patch with a static top-to-middle gradient overlay. Use the existing theme colors, such as `.yolk`, `.nestCream`, `.nestLeafGreen`, or `.nestBrown` with low opacity, rather than adding one-off color literals.
- Ensure the gradient fades out by the middle of the screen so lower content remains visually calm.
- Update comments/previews so they no longer describe a drifting shaft of light or horizontal motion.
- In `FloatingLeavesView`, replace the current deterministic sine sway with a more random-looking drift path.
- Keep the animation subtle and non-interactive. Avoid abrupt jumps when leaves loop from bottom back to top.
- A practical approach is to add per-leaf drift configuration such as `startXFraction`, `endXFraction`, `midpointBias`, `phase`, `swayAmplitude`, and `swayFrequency`, then interpolate x-position over vertical progress with a small sinusoidal wobble.
- Use fixed seeded configurations rather than runtime randomness so previews and tests are stable while still looking random.
- Vary duration, start offset, scale, rotation, opacity, and drift direction per leaf.
- Keep `.allowsHitTesting(false)` and ensure the background remains inexpensive enough for all screens that use `AnimatedCanopyBackground`.

Verification:
- Preview `AnimatedCanopyBackground` and confirm there is no horizontal scrolling square/light patch.
- Preview `FloatingLeavesView` and confirm leaves drift diagonally/randomly rather than straight down in vertical lanes.
- Manually check a few screens using `AnimatedCanopyBackground`, including dashboard, transactions, budget, and savings goals, to ensure contrast remains readable.

## Naming

- Repository/folder/project: `EggSpend`
- App target/product/scheme: `EggSpend`
- Test target: `EggSpendTests`
- App entry point: `EggSpendApp`
