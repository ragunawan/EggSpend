# TODO

Priorities are sorted by expected user value, trust impact, and how naturally the work builds on existing EggSpend features.

## P0 - Data Safety And Trust

### Local Data Export And Backup

- [ ] Add local data export and backup.
- Why: personal finance users need confidence that their data is portable and recoverable outside CloudKit sync.
- Requirements:
  - Export transactions, transfers, accounts, categories, budgets, recurring transactions, and savings goals.
  - Support a human-readable CSV export for transactions and transfers.
  - Support a complete JSON backup format for all app-owned data.
  - Include schema version, export date, app version, and build number in backup metadata.
  - Redact nothing by default, but clearly label exports as sensitive financial data before sharing.
  - Add import validation for future backup restore work, even if restore is not implemented in the first pass.
- Verification:
  - Add unit tests for export row counts, required columns, date formatting, decimal formatting, and nil relationship handling.
  - Add tests that backup JSON round-trips through decoding without data loss for representative fixtures.
  - Manually export from a preview-data simulator and inspect the resulting CSV and JSON files.
  - Run `xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'`.

### Account Reconciliation

- [ ] Add account reconciliation.
- Why: helps users compare EggSpend balances against bank balances and identify missing, duplicate, or mistyped transactions.
- Requirements:
  - Add a reconciliation workflow from account detail or account list rows.
  - Let users enter an external statement balance and statement date.
  - Show the difference between EggSpend's computed balance and the statement balance.
  - Surface likely causes: uncleared transactions, duplicate amounts, recent imports, and transactions after the statement date.
  - Let users mark transactions as cleared for a specific account statement.
  - Preserve account balance sign conventions for assets and liabilities.
- Verification:
  - Add tests for balance-at-date calculations across income, expense, transfer, asset, and liability accounts.
  - Add tests for cleared and uncleared transaction filtering.
  - Manually reconcile a checking account, credit card account, and loan account with preview data.
  - Confirm editing or deleting a reconciled transaction updates the reconciliation difference.

## P1 - Core Money Workflows

### Budget Rollover

- [ ] Add a budget rollover option so unused monthly budget amounts can carry into the next period.
- Why: makes budgeting more realistic for categories with uneven spending, such as utilities, gifts, and travel.
- Requirements:
  - Add a per-budget rollover setting with a clear default of off.
  - Carry positive unused budget into the next matching period.
  - Decide and document whether overspending creates negative rollover debt.
  - Show base budget, rollover amount, effective budget, spent, and remaining amount in budget detail.
  - Keep existing category matching behavior, including uncategorized budgets.
  - Avoid changing historical budget calculations for budgets with rollover disabled.
- Verification:
  - Add tests for monthly rollover, disabled rollover, overspent periods, inactive budgets, and uncategorized budgets.
  - Add tests around month boundaries and leap-year February.
  - Manually verify Budget list and Budget detail display the same effective remaining amount.
  - Run the full XCTest suite.

### Recurring Transaction Review

- [ ] Add recurring transaction review before posting overdue items.
- Why: gives users control before the app creates transactions that may have changed amount, date, or category.
- Requirements:
  - Detect overdue recurring transactions on launch without immediately posting them.
  - Present a review queue with skip, edit, post one, and post all actions.
  - Preserve existing duplicate prevention for generated occurrences.
  - Let users edit amount, date, title, category, notes, and account before posting.
  - Advance `nextDueDate` correctly when a user skips or posts an occurrence.
  - Keep a low-friction path for users who still want automatic posting.
- Verification:
  - Add tests for post, post all, skip, edit before post, end date, inactive recurring items, and duplicate prevention.
  - Add account balance tests for reviewed recurring income and expense postings.
  - Manually launch with overdue preview recurring items and verify the queue behavior.
  - Confirm no duplicate transactions are created after relaunch.

### Monthly Closeout Flow

- [ ] Add monthly closeout flow.
- Why: turns metrics into an actionable routine for reviewing overspending, savings progress, and net-worth movement.
- Requirements:
  - Add a month-end review screen reachable from Metrics or Home.
  - Summarize income, expenses, savings rate, top categories, budget overruns, net-worth movement, and goal progress.
  - Highlight uncategorized transactions and missing account assignments.
  - Let users mark a month as reviewed.
  - Store review completion per calendar month.
  - Include a short checklist for common closeout tasks.
- Verification:
  - Extend `MonthlyReviewCalculatorTests` for any new summary fields.
  - Add persistence tests for reviewed-month state.
  - Manually test empty month, positive savings month, overspent month, and month with transfers.
  - Verify transfers do not inflate income, expenses, or savings rate.

## P2 - Efficiency And Retention

### CSV Import Mapping Presets

- [ ] Add CSV import mapping presets per bank or card.
- Why: repeat imports should not require remapping columns every time, especially for users with multiple accounts.
- Requirements:
  - Save user-selected column mappings as named presets.
  - Suggest a matching preset when CSV headers match a previous import.
  - Support separate presets for transaction imports and account imports.
  - Let users rename, update, and delete presets.
  - Keep auto-detection as the first-run fallback.
  - Do not import duplicate transactions when a preset is reused.
- Verification:
  - Extend `CSVParserTests` for preset matching, missing columns, renamed columns, and transaction/account preset separation.
  - Add tests for duplicate detection if matching logic changes.
  - Manually import two different CSV layouts and confirm the correct preset is suggested on the second import.
  - Verify invalid preset mappings produce clear validation errors.

### Saved Transaction Filters

- [ ] Add transaction search saved filters.
- Why: users can quickly revisit common views like subscriptions, tax-deductible expenses, or uncategorized spending.
- Requirements:
  - Let users save the current transaction filter with a name.
  - Support saved criteria for type, category, account, amount range, date range, generated-only, and search text if present.
  - Add quick access from the transaction filter UI.
  - Let users rename, update, delete, and clear saved filters.
  - Preserve existing one-off filter behavior.
- Verification:
  - Extend `TransactionFilterTests` for encoding, decoding, applying, updating, and clearing saved filters.
  - Add tests for active-count behavior when a saved filter is applied.
  - Manually create saved filters for uncategorized spending, subscriptions, and a single account.
  - Confirm deleting a category or account does not crash saved filters that referenced it.

### Notification Settings

- [ ] Add notification settings screen.
- Why: budget alerts and recurring reminders are already modeled, but users need one place to review and tune them.
- Requirements:
  - Add a central settings screen for notification permission status, budget alerts, and recurring reminders.
  - Show whether system notification permission is not determined, denied, provisional, or authorized.
  - Let users enable or disable all budget alerts without deleting per-budget configuration.
  - Let users review upcoming recurring reminders.
  - Deep-link or guide users to system settings when permission is denied.
  - Keep existing per-budget and per-recurring controls intact.
- Verification:
  - Extend `NotificationSchedulerTests` for global enablement and disabled-permission behavior.
  - Manually test first permission prompt, denied permission copy, and authorized scheduling on simulator.
  - Confirm disabling global alerts cancels pending budget notifications without deleting user preferences.

## P3 - Guidance And Polish

### Goal Funding Suggestions

- [ ] Add goal funding suggestions.
- Why: savings goals already track progress, and suggested monthly or per-paycheck contributions would make them easier to act on.
- Requirements:
  - Suggest monthly contribution for each active goal with a target date.
  - Add optional per-paycheck suggestions based on weekly, biweekly, semimonthly, or monthly pay cadence.
  - Use linked account balance when a goal is linked to an account.
  - Handle overdue goals, completed goals, no target date, and zero remaining amount gracefully.
  - Show the total suggested goal funding alongside safe-to-spend calculations where useful.
- Verification:
  - Extend `SavingsGoalTests` and `SafeSpendCalculatorTests` for contribution suggestions.
  - Add tests for linked accounts, overdue dates, completed goals, and each pay cadence.
  - Manually verify suggestions on the Savings Goals and Safe to Spend screens.

### Lightweight Onboarding

- [ ] Add lightweight onboarding with sample-data reset.
- Why: first-run setup can guide users through accounts, categories, budgets, and imports without making the app feel empty.
- Requirements:
  - Detect first launch without existing user data.
  - Guide users through account creation, category review, first budget, and optional CSV import.
  - Offer sample data for exploration and a clear reset path before real use.
  - Persist onboarding completion.
  - Avoid blocking users who want to skip setup.
- Verification:
  - Add tests for first-launch detection and onboarding completion persistence.
  - Manually test fresh install, skipped onboarding, completed onboarding, sample-data reset, and relaunch.
  - Confirm default category seeding remains idempotent.

## Later

These ideas are valuable, but should wait until the data-safety and core workflow items above are in place.

- [ ] Backup restore flow.
- [ ] iCloud sync diagnostics screen.
- [ ] App lock with Face ID or passcode.
- [ ] Widgets for safe-to-spend, upcoming bills, and goal progress.
- [ ] Multi-currency support.
- [ ] Receipt photo attachments.
- [ ] Rule-based auto-categorization.
- [ ] Import duplicate review and merge workflow.
