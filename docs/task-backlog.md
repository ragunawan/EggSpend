# EggSpend — Prioritized Task Backlog

Derived from `docs/audit-and-roadmap.md` (audit of commit `a5f6a25`, decisions resolved 2026-07-08).
Ordering is execution order: data correctness → import integrity → locale/currency → UX safety → new features → polish.

Conventions: Risk = chance of regression/data damage if done wrong. Effort: S (<½ day), M (½–2 days), L (2+ days). Every task is independently shippable and should keep `xcodebuild test` green.

---

## P0 — Correctness (bug fixes)

### T1. Unify net worth into a shared calculator and fix the liability sign bug ✅ *Ready for implementation*
**Goal:** One net-worth formula everywhere; stop adding debts to net worth in Metrics and Monthly Review.
**Files:** new `EggSpend/Utilities/NetWorthCalculator.swift`; `EggSpend/Views/Metrics/MetricsView.swift` (~line 88); `EggSpend/Utilities/MonthlyReviewCalculator.swift` (~line 112); `EggSpend/Views/Dashboard/DashboardView.swift` (~line 24); `EggSpend/Views/NetWorth/NetWorthView.swift` (~lines 11–17); `generate_project.py`; `EggSpend.xcodeproj/project.pbxproj`; `EggSpendTests/NetWorthCalculationTests.swift`.
**Steps:**
1. Create `NetWorthCalculator` with `static func current(accounts:) -> Double` implementing: skip accounts where `!includeInNetWorth` (liabilities only today, but write it generically), assets add `balance`, liabilities add `-abs(balance)`.
2. Add `static func totals(accounts:) -> (assets: Double, liabilities: Double)` for NetWorthView's summary/chart.
3. Replace the inline formulas in the four call sites; keep `MonthlyReviewCalculator.netWorth(at:)`'s reconstruction shape but delegate the "current" term to the calculator (reconstruction itself is T2).
4. Register the new file in `generate_project.py` and regenerate/update the pbxproj.
5. Tests: negative-balance credit/loan accounts; `includeInNetWorth == false` exclusion; assert Dashboard/NetWorth/Metrics values agree via the calculator.
**Acceptance:** With seed data (assets 75,000; credit −1,800; loan −24,000) every surface shows 49,200 — Metrics no longer disagrees with the Nest Egg tab.
**Manual test:** launch with `--preview-data`, compare the Home header, Nest Egg tab, and Metrics "Current" figure; toggle "Include in Net Worth" off on the loan and confirm all three move identically.
**Risk:** Low (pure refactor + sign fix, well-tested area). **Effort:** S.

### T2. Restrict historical net-worth reconstruction to account-linked transactions ✅ *Ready for implementation*
**Goal:** Stop the Metrics timeline and Monthly Review from reversing transactions that never affected any balance (all CSV imports today), which fabricates history.
**Files:** `EggSpend/Utilities/MonthlyReviewCalculator.swift` (`netWorth(accounts:allTransactions:at:)`); `EggSpend/Views/Metrics/MetricsView.swift` (`netWorthTimeline`); `EggSpendTests/NetWorthCalculationTests.swift`, `EggSpendTests/MonthlyReviewCalculatorTests.swift`.
**Steps:**
1. In both reconstruction loops, filter to `$0.account != nil` before reversing signed amounts.
2. Move the shared reconstruction into `NetWorthCalculator.at(date:accounts:transactions:)` so Metrics and MonthlyReview share it (depends on T1's file existing).
3. Add a doc comment stating the invariant: only account-linked transactions move balances, so only they are reversible.
4. Tests: account-less transactions leave the timeline flat; account-linked ones reconstruct correctly; mixed case.
**Acceptance:** Importing a CSV of account-less transactions leaves "Nest Egg Over Time" flat at the current value; monthly review net-worth change is 0 for a month containing only unlinked transactions.
**Manual test:** `--preview-data`, note the timeline; add a large expense with Account = None; confirm today's net worth and the historical curve don't jump.
**Risk:** Low. **Effort:** S. **Depends on:** T1.

### T3. Fix CSV amount and type parsing ✅ *Ready for implementation*
**Goal:** Stop silent misparses: `-` stripped from mid-string, trailing-minus ignored, unknown type values defaulting to income.
**Files:** `EggSpend/Utilities/CSVParser.swift` (`parseAmount` ~line 94, type inference ~line 238); `EggSpendTests/CSVParserTests.swift`.
**Steps:**
1. `parseAmount`: detect sign first (leading `-`/`−`, trailing `-`/`−`, wrapping parens); then strip currency symbols/spaces/parens; after stripping, reject strings still containing `-` or `−`; keep existing thousands-comma handling.
2. Type inference in `parseTransactionRows`: extend expense keywords (`purchase`, `sale`, `payment`, `pos`, `dr`); extend income keywords (`deposit`, `refund`, `credit`, `cr`); when the type string matches neither list, fall back to amount-sign logic instead of defaulting to income.
3. Table-driven tests: `(12.34)`, `12.34-`, `-12.34`, `$1,234.56`, `12-34` (reject), `Purchase`, `Payment`, `Deposit`, `credit`, unknown `xyz` with negative amount.
**Acceptance:** All table cases produce the documented value/type; existing parser tests still pass.
**Manual test:** import a small handcrafted CSV containing a parenthesized amount, a trailing-minus amount, and a `Purchase` type row; verify the preview step shows correct signs and types.
**Risk:** Low (pure function + tests). **Effort:** S.

### T4. Recurring materialization edge cases: ended items and infinite-loop guard
**Goal:** Materialize final occurrences of ended recurring items; never hang if the calendar fails to advance a date.
**Files:** `EggSpend/Models/RecurringTransaction.swift` (lines ~138 and ~108–116/141); `EggSpendTests/RecurringTransactionTests.swift`.
**Steps:**
1. In `processRecurringTransactions`, remove the item-level `if let end = item.endDate, end < now { continue }`; the per-occurrence `if item.nextDueDate > end { break }` already stops correctly.
2. In the `while item.nextDueDate <= now` loop, capture the pre-advance date and `break` (and log) if `advanceNextDueDate()` did not strictly advance.
3. Tests: item with endDate yesterday and an ungenerated due date before it materializes exactly the final occurrence; a stubbed non-advancing case terminates.
**Acceptance:** Ended items generate all occurrences ≤ endDate exactly once; loop provably terminates.
**Manual test:** create a monthly recurring with end date = tomorrow and start last month; relaunch; verify the overdue occurrence appears once in Transactions.
**Risk:** Medium (touches launch-time data generation; duplicate risk if de-dupe logic is disturbed — keep it untouched). **Effort:** S.

### T5. Locale-safe amount entry
**Goal:** Users in comma-decimal locales can enter amounts (today `12,50` → parse failure → Save disabled forever).
**Files:** new `EggSpend/Utilities/AmountParser.swift`; `EggSpend/Views/Transactions/AddTransactionView.swift:62`; `EggSpend/Views/Accounts/AddAccountView.swift:23`; `EggSpend/Views/Budget/AddBudgetView.swift`; `EggSpend/Views/Recurring/AddRecurringTransactionView.swift`; `EggSpend/Views/SavingsGoals/AddSavingsGoalView.swift`; `generate_project.py`; pbxproj; new `EggSpendTests/AmountParserTests.swift`.
**Steps:**
1. `AmountParser.parse(_ text: String, locale: Locale = .current) -> Double?`: try `Double(text)`, then locale decimal-separator normalization (accept both `.` and the locale separator; strip grouping separators).
2. Replace every `Double(someText) ?? 0` amount parse in Add/Edit forms; also use the locale separator when pre-filling `amountText` on edit (`String(format: "%.2f", …)` is `.`-only — use a `FormatStyle` instead).
3. Tests across `en_US`, `fr_FR`, `de_DE` for `12.50`, `12,50`, `1.234,56`, `1,234.56`.
**Acceptance:** Under a `fr_FR` locale/simulator, typing `12,50` enables Save and stores 12.5; editing shows the same string back.
**Manual test:** set simulator region to France, add a transaction with the decimal pad, save, reopen for edit.
**Risk:** Low–Medium (touches every money form; mitigated by shared helper + tests). **Effort:** M.

### T6. Persist and surface save failures in critical paths
**Goal:** Stop swallowing `try?` save errors where financial data is written (import, recurring processing, alert-state mutation).
**Files:** `EggSpend/Views/Import/CSVImportView.swift:403`; `EggSpend/Models/RecurringTransaction.swift:174-181`; `EggSpend/Utilities/BudgetAlertCoordinator.swift` (save after `evaluateAlert` mutations); `EggSpend/Persistence/PersistenceController.swift`.
**Steps:**
1. In `performImport()`, use `do/catch`; on failure set `errorMessage` (existing alert plumbing) and stay on the preview step instead of showing "done".
2. In `processRecurringTransactions`, keep the catch but also post a user-visible flag (simplest: return a `Result`/`Bool` the caller can surface; Dashboard/TransactionsList already call it).
3. `BudgetAlertCoordinator.checkBudgets(context:)`: `try? context.save()` → explicit save with logged failure (alert dedupe state must persist or alerts re-fire).
**Acceptance:** A forced save failure during import shows the error alert and does not report an imported count.
**Manual test:** temporarily throw in a debug hook (or fill-disk simulator trick is impractical — code-inject) to verify the alert path; otherwise rely on unit tests with a read-only container.
**Risk:** Low. **Effort:** S.

---

## P1 — Data integrity & platform hygiene

### T7. Archive accounts instead of deleting (per product decision)
**Goal:** Replace destructive account deletion with archival; keep history intact.
**Files:** `EggSpend/Models/Account.swift` (add `var isArchived: Bool = false` — CloudKit-safe default); `EggSpend/Views/NetWorth/NetWorthView.swift:182-186` (swipe action + confirmation); `EggSpend/Views/Accounts/AccountsView.swift`; account pickers in `AddTransactionView`, `AddRecurringTransactionView`, `AddSavingsGoalView`; `NetWorthCalculator` (skip archived); new archived-accounts list (inside `AccountsView` or a section in NetWorthView); tests.
**Steps:**
1. Add the field; exclude archived accounts from `@Query`-fed pickers, net-worth math, Safe-to-Spend liquid balance (`ForecastEngine.liquidBalance`), and forecast.
2. Swipe action becomes "Archive" with a confirmation dialog explaining effects; archived section shows them greyed with Unarchive and a true Delete (destructive, confirmed) action.
3. Existing transactions keep their `account` link; `TransactionDetailView` still renders the name.
4. Tests: archived account excluded from net worth and liquid balance; unarchive restores.
**Acceptance:** Archiving the checking account removes it from pickers/net worth/forecast without touching its transactions; unarchive fully restores; nothing is deleted without the explicit archived-list delete.
**Manual test:** archive → check all five tabs → unarchive → verify balances unchanged.
**Risk:** Medium (schema addition — verify CloudKit accepts the defaulted field; touch many query sites). **Effort:** M. **Depends on:** T1 (calculator is the single place to exclude archived).

### T8. CSV transaction import: account selection + balance application
**Goal:** Imported transactions can belong to an account and (optionally) update its balance, closing the "two sources of truth" gap.
**Files:** `EggSpend/Views/Import/CSVImportView.swift` (map + preview + `performImport`); `EggSpend/Utilities/CSVParser.swift` (no change expected); `EggSpendTests` (new import-flow test or extend `TransactionAccountTests`).
**Steps:**
1. Add an "Import into account" picker (None + all unarchived accounts) on the mapping step.
2. Add a toggle "Adjust account balance by imported transactions" (default ON when an account is chosen) — applies `AccountBalanceService.apply` per inserted transaction.
3. Show the net balance effect on the preview step ("Will decrease Chase Checking by $412.33").
4. On import, set `tx.account` and apply balances inside the same save.
**Acceptance:** Importing 3 expenses into checking with the toggle ON reduces the balance by their sum; with OFF, balance unchanged but transactions linked.
**Manual test:** import a 3-row CSV into a seeded account; verify balance and the Metrics timeline stay consistent (T2 must be in first).
**Risk:** Medium (balance mutation in bulk; wrong sign would corrupt an account — covered by tests + preview disclosure). **Effort:** M. **Depends on:** T2, T3.

### T9. CSV import duplicate detection
**Goal:** Re-importing the same file (or overlapping exports) imports 0 duplicate rows.
**Files:** `EggSpend/Views/Import/CSVImportView.swift`; possibly `EggSpend/Utilities/CSVParser.swift` for a normalization helper; tests.
**Steps:**
1. Define duplicate key: same calendar day + amount + case/whitespace-normalized title (+ same account when set).
2. Before insert, fetch existing transactions in the file's date range and build a `Set` of keys; mark preview rows already present as "Duplicate — will skip" (reuse the invalid-row styling); count them in `skippedCount` separately ("N duplicates skipped").
3. Tests: same-file re-import yields zero inserts; near-duplicates (different day or amount) still import.
**Acceptance:** Importing the same CSV twice results in no new rows and an explicit duplicate count in the done step.
**Manual test:** import a file twice; check Transactions count and the summary text.
**Risk:** Low. **Effort:** M. **⚠️ Product decision needed:** how strict should matching be (exact same-day vs ±1 day for pending/posted date drift), and should users be able to override per-row? Recommend exact same-day, no override, for v1.

### T10. Account edit must not silently rewrite balance; balance edits become explicit adjustments
**Goal:** Renaming an account can't clobber its balance; deliberate balance changes are recorded as adjustment transactions so history stays reconstructable.
**Files:** `EggSpend/Views/Accounts/AddAccountView.swift:105-151`; `EggSpend/Models/Transaction.swift` (optional `isAdjustment` flag or a reserved title/notes convention); `EggSpendTests/TransactionAccountTests.swift`.
**Steps:**
1. In `populateIfEditing`, capture the loaded balance; on save, if the parsed balance equals the loaded one, don't write `balance` at all.
2. If it differs, create a Transaction titled "Balance adjustment" (`isGenerated = false`, flagged as adjustment) for the delta, linked to the account, and let `AccountBalanceService.apply` produce the new balance — instead of overwriting.
3. Also move `populateIfEditing` from `onAppear` to `.task`/initializer-driven state so sheet re-appearance can't reset edits.
4. Tests: rename-only edit leaves balance and history untouched; balance edit produces one adjustment transaction whose application yields the new balance.
**Acceptance:** Edit name only → balance identical; edit balance 4200→4000 → account shows 4000 and Transactions contains a −200 adjustment.
**Manual test:** as above via UI.
**Risk:** Medium (semantics change; adjustment rows now appear in the ledger). **Effort:** M. **⚠️ Product decision needed:** should adjustment transactions appear in the main ledger and cash-flow metrics, or be excluded from income/expense stats (shown only in the account view)? Recommend: visible in ledger, excluded from cash-flow/savings-rate metrics.

### T11. CI: GitHub Actions test workflow
**Goal:** Every PR runs the full test suite.
**Files:** new `.github/workflows/test.yml`.
**Steps:** macOS runner; pin Xcode version; `xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'`; cache derived data optionally.
**Acceptance:** Workflow green on this branch; a deliberately broken test fails the check.
**Manual test:** push a branch, observe the check.
**Risk:** Low. **Effort:** S.

### T12. Display-currency abstraction (per product decision: display-only)
**Goal:** Replace 76 hard-coded `.currency(code: "USD")` sites and `"$"` literals with one locale-derived currency.
**Files:** `EggSpend/EggSpendTheme.swift` or new `EggSpend/Utilities/CurrencyFormat.swift`; every view/model with `.currency(code: "USD")` (76 sites, mechanical); `MetricsView.swift:6` (`CompactCurrencyAxisFormatter` symbol param); form `$` prefixes in `AddTransactionView`/`AddAccountView`; tests.
**Steps:**
1. Add `CurrencyFormat.code` (from `Locale.current.currency?.identifier ?? "USD"`) and helpers `money(_:)` / `FormatStyle` accessor; keep a single override point for a future settings toggle.
2. Mechanical replacement of call sites; replace literal `$` labels with `Locale.current.currencySymbol`-derived text.
3. Snapshot a few formatting tests under `en_US`, `de_DE`, `ja_JP`.
**Acceptance:** With region Germany, all amounts render as € with German separators; no `"USD"` literal remains outside `CurrencyFormat`.
**Manual test:** switch simulator region, sweep all five tabs + forms + notifications preview.
**Risk:** Low (display-only; no stored-data change). **Effort:** M. **Depends on:** T5 (input side).

### T13. CSV / JSON export
**Goal:** Data portability: users can get everything out.
**Files:** new `EggSpend/Utilities/DataExporter.swift`; new `EggSpend/Views/Settings/SettingsView.swift` (also houses sync status + future AI toggle); `ContentView.swift` or a toolbar entry point; `generate_project.py`; pbxproj; tests.
**Steps:**
1. `DataExporter.transactionsCSV(_:)` (RFC-4180, columns matching the import auto-detector so round-trip works), `accountsCSV(_:)`, and `fullBackupJSON(...)` (all seven models, versioned envelope).
2. Minimal Settings screen with Export buttons using `ShareLink`/`fileExporter`.
3. Round-trip test: export → parse with `CSVParser` → identical rows.
**Acceptance:** Exported transactions CSV re-imports with 100% valid rows and (with T9) 100% duplicates.
**Manual test:** export from Settings, AirDrop/Files, re-import.
**Risk:** Low. **Effort:** M.

---

## P2 — Differentiation features

### T14. BalanceSnapshot model for true net-worth history
**Goal:** Record daily balance snapshots so history charts stop depending on reverse-reconstruction.
**Files:** new `EggSpend/Models/BalanceSnapshot.swift` (accountID: UUID, date: Date, balance: Double — all defaulted for CloudKit); `EggSpendApp.swift` (schema + launch hook writing one snapshot per account per day); `NetWorthCalculator` (prefer snapshots, fall back to reconstruction for pre-snapshot dates); `MetricsView.swift`; `generate_project.py`; pbxproj; new tests.
**Steps:** write-on-launch (and on day rollover via `scenePhase`); dedupe per account+day; timeline reads snapshots where available.
**Acceptance:** After two simulated days, the timeline's last two points come from snapshots and match recorded balances exactly, regardless of unlinked transactions.
**Manual test:** launch on consecutive (simulated) days, compare chart to account balances.
**Risk:** Medium (new synced model; storage growth is trivial ~365 rows/account/yr). **Effort:** M. **Depends on:** T1, T2.

### T15. Forecast/Safe-to-Spend double-count fix
**Goal:** A recurring item due today (already materialized) must not also be projected; reduce documented drift double-counting.
**Files:** `EggSpend/Views/Forecast/ForecastEngine.swift`; `EggSpend/Utilities/RecurringProjection.swift`; `EggSpend/Utilities/SafeSpendCalculator.swift` (consumer, no change expected); `EggSpendTests/CashFlowForecastTests.swift`, `SafeSpendCalculatorTests.swift`.
**Steps:**
1. `RecurringProjection.occurrences`: start strictly after `max(startOfWindow, item.nextDueDate’s last materialized date)` — concretely, begin projecting from `item.nextDueDate` (which processing has already advanced past materialized dates) instead of fast-forwarding from an assumed window start; drop occurrences `<= now` for items processed this launch.
2. Optionally compute drift from non-generated transactions only (`!isGenerated`) and add recurring explicitly — removes the documented double-count; update the ASSUMPTION comments.
3. Tests: item due earlier today already materialized → not in events; drift excludes generated rows.
**Acceptance:** Forecast day-0/day-1 balance for a rent-due-today scenario counts rent exactly once; SafeSpend outflow reserve drops accordingly.
**Manual test:** seed a recurring due today, relaunch, open Forecast and Safe-to-Spend breakdowns.
**Risk:** Medium (numbers everyone sees; guarded by existing test suites). **Effort:** M. **Depends on:** T4.

### T16. Subscription detection + audit screen
**Goal:** Detect recurring-looking spend from history; show annualized cost and price changes; one-tap convert to a tracked RecurringTransaction.
**Files:** new `EggSpend/Utilities/SubscriptionDetector.swift`; new `EggSpend/Views/Subscriptions/SubscriptionAuditView.swift`; entry point from `RecurringTransactionsView` or Home card; `generate_project.py`; pbxproj; new `EggSpendTests/SubscriptionDetectorTests.swift`.
**Steps:** normalize titles (lowercase, strip digits/dates); cluster by title; detect cadence (monthly/weekly/yearly within ±3 days) and amount stability (±10%); flag latest-amount ≠ mode as price change; exclude titles already covered by a RecurringTransaction.
**Acceptance:** Seeded Netflix-like series (3+ monthly charges) is detected with correct cadence and monthly cost; price bump flagged; converting creates a correctly-dated RecurringTransaction and removes it from "undetected."
**Manual test:** import a crafted CSV with two subscription patterns; open the audit screen.
**Risk:** Low (read-only analysis + explicit user action). **Effort:** L. **Depends on:** T3, T9 (clean import data).

### T17. Auto-categorization rules
**Goal:** Learn merchant→category from user behavior; apply on import and quick-add.
**Files:** new `EggSpend/Models/CategoryRule.swift` (pattern, categoryID, createdAt — CloudKit-safe defaults); `EggSpendApp.swift` schema; hook in `AddTransactionView.saveTransaction` (record rule when user sets a category), `CSVImportView.performImport` (apply rules to uncategorized rows); rule management list inside `CategoryManagementView`; tests.
**Steps:** exact-normalized-title rules v1 (no regex); most-recent rule wins; import preview shows auto-assigned category with a distinct badge.
**Acceptance:** Categorize "Blue Bottle Coffee" once; next import auto-assigns Food & Dining and the preview shows it; deleting the rule stops it.
**Manual test:** as above through the import flow.
**Risk:** Low. **Effort:** M. **Depends on:** T8/T9 preferred.

### T18. "What changed this month?" summary card (template-based)
**Goal:** Retention: a plain-English monthly delta digest on Home.
**Files:** new `EggSpend/Utilities/SpendingDeltaCalculator.swift`; new card in `EggSpend/Views/Dashboard/DashboardView.swift`; reuse `MonthlyReviewCalculator`; tests.
**Steps:** compute per-category current-month spend vs trailing-3-month average; rank absolute deltas; render top 3 as template sentences ("Dining is $120 above your usual pace"); link card → MonthlyReviewView.
**Acceptance:** Deterministic sentences for a fixture dataset; card hidden with <1 month of history.
**Manual test:** `--preview-data`, verify card content and navigation.
**Risk:** Low. **Effort:** M.

### T19. On-device AI narrative toggle (per product decision)
**Goal:** Optionally enrich T18/Monthly Review text with an on-device model; toggle visible only when supported; zero network.
**Files:** `SettingsView` (T13); new `EggSpend/Utilities/NarrativeGenerator.swift` gating on framework availability; `DashboardView`/`MonthlyReviewView`.
**Steps:** availability check (`#available` + model-availability API); template output remains the always-works path; AI path rewrites tone only — numbers always come from calculators, never the model.
**Acceptance:** Unsupported device: toggle absent, templates shown. Supported: toggle ON produces narrative containing the exact calculator figures.
**Manual test:** both device classes in simulator where possible.
**Risk:** Medium (model API availability varies; strict fallback required). **Effort:** M–L. **Depends on:** T13, T18. **⚠️ Product decision needed:** none on privacy (resolved: on-device only), but confirm minimum OS target you're willing to raise to if the model framework requires it.

---

## P3 — Polish & trust

### T20. Face ID / Touch ID app lock
**Goal:** Standard finance-app privacy: biometric gate with passcode fallback, toggle in Settings.
**Files:** `SettingsView`; new `EggSpend/Utilities/AppLockController.swift` (`LAContext`); `EggSpendApp.swift`/`ContentView.swift` (locked overlay on launch and on `scenePhase` background→active); `EggSpend/PrivacyInfo.xcprivacy` (Face ID usage string in Info settings).
**Acceptance:** With lock ON, backgrounding and returning shows the blur/lock screen until auth succeeds; OFF restores current behavior; failed biometrics offer device passcode.
**Manual test:** toggle on, background/foreground, simulate failed Face ID.
**Risk:** Low–Medium (lockout UX must never brick access — always allow passcode fallback). **Effort:** M. **Depends on:** T13 (Settings host).

### T21. Transactions grouping performance + localized section headers
**Goal:** Fix O(n²) `grouped` and non-localized `"MMMM d, yyyy"` headers.
**Files:** `EggSpend/Views/Transactions/TransactionsListView.swift:85-97, 414-420`.
**Steps:** group rows by `Calendar.startOfDay` key; sort keys descending; format headers with `Date.FormatStyle().month(.wide).day().year()`.
**Acceptance:** 5k-transaction dataset scrolls smoothly (profile before/after); headers localize with device language.
**Manual test:** seed a large dataset via a debug loop; scroll; switch language.
**Risk:** Low. **Effort:** S.

### T22. Empty states for Metrics and Forecast + first-run onboarding
**Goal:** New users don't see empty axes and flat zero forecasts.
**Files:** `MetricsView.swift`, `CashFlowForecastView.swift`, `SafeToSpendView.swift`; new `Views/Onboarding/OnboardingView.swift` (3 screens: welcome → create first account → optional import/budget), `EggSpendApp.swift` (`@AppStorage` first-run flag); `generate_project.py`; pbxproj.
**Acceptance:** Fresh install shows onboarding once, then CTAs instead of empty charts until ≥1 transaction/account exists.
**Manual test:** delete app, reinstall, walk the flow.
**Risk:** Low. **Effort:** M.

### T23. CloudKit duplicate-sweep for generated recurring transactions
**Goal:** Self-heal duplicates created when two devices materialize the same due date before sync.
**Files:** `EggSpend/Models/RecurringTransaction.swift` (or new `Utilities/DuplicateSweeper.swift`); `EggSpendApp.swift` launch hook after processing; tests.
**Steps:** group generated transactions by `(recurringSourceID, recurringDueDate-day)`; keep the earliest `createdAt`; for each removed duplicate, `AccountBalanceService.reverse` then delete; run after `processRecurringTransactions` and on remote-change notification if available.
**Acceptance:** Seeding two identical generated transactions resolves to one with the balance corrected by exactly one application.
**Manual test:** hard without two devices — rely on unit tests; optionally simulate by inserting a duplicate in debug.
**Risk:** Medium–High (deletes data + mutates balances; must be precisely scoped to `isGenerated` rows with matching keys). **Effort:** M. **Depends on:** T4.

### T24. Accessibility & localization pass
**Goal:** VoiceOver labels for charts/rows, Dynamic Type audit, strings catalog for future localization.
**Files:** broad but shallow: chart views (`MetricsView`, `CashFlowForecastView`, `EggProgressView`), row components, new `Localizable.xcstrings`.
**Acceptance:** VoiceOver completes add-transaction end-to-end; XXL type doesn't clip primary screens; all user-facing strings in the catalog.
**Manual test:** VoiceOver + largest accessibility text size sweep.
**Risk:** Low. **Effort:** L.

---

## Decision checklist (blocking specific tasks)

| Task | Decision needed |
|---|---|
| T9 | Duplicate-match strictness (recommend: exact same-day + amount + normalized title; no per-row override in v1). |
| T10 | Are balance-adjustment transactions visible in the main ledger and included in cash-flow stats? (Recommend: visible in ledger, excluded from income/expense metrics.) |
| T19 | Acceptable minimum iOS target if the on-device model framework requires raising it. |

Everything else is unblocked. Suggested first sprint: **T1 → T2 → T3** (all Ready), then T4–T6.
