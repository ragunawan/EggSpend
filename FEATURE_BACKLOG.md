# EggSpend — Feature Backlog

Prioritized feature work lives in `docs/task-backlog.md` (T7–T24) and is tracked in `IMPLEMENTATION_PLAN.md`. This file holds the strategy summary and the unprioritized inbox for ideas discovered during the loop.

## Product direction (decided)
1. **"Cash Calm"** — Safe-to-Spend + Forecast + subscription intelligence as the hero loop (build first).
2. Subscription leakage detection (T16).
3. Plain-English "What changed this month?" (T18), on-device-AI-enrichable (T19).

Constraints (resolved 2026-07-08): Plaid = long-term only; AI = on-device only behind capability-gated toggle; accounts archive, never hard-delete by default; currency display-only.

## Unprioritized inbox
(The Documentation Agent appends here; the Planner promotes items into docs/task-backlog.md + IMPLEMENTATION_PLAN.md.)

- Surface recurring-processing failures in UI (banner/toast) instead of console-only logging — T6 added Bool return tracking but both onAppear callers ignore it; address in next cycle so T6 isn't overstated as fully closed (from T6 code review).
- AccountsView.swift is dead code — unreachable from ContentView, only self-referenced in its own #Preview; candidate for deletion (with generate_project.py/pbxproj update) or wiring up (from T7 repo analysis).
- UX: consider pausing or surfacing recurring transactions on archived accounts (ties to B22 — recurring transactions on archived accounts continue materializing silently, needs product decision or follow-up task) (from T7 code review).
- Rollover budgets; overall monthly budget across categories — superseded by the more detailed spec in `TODO.md` ("Budget Rollover", P1): per-budget opt-in default off, positive-only vs. negative-rollover-debt decision needed, show base/rollover/effective/spent/remaining in budget detail, month-boundary + leap-year tests. User ranked this in TODO.md; not yet promoted to `docs/task-backlog.md`.
- Budget suggestions from 3-month category averages
- Transaction splitting; receipt photo attachments
- Quick-add widget / App Intents shortcut
- Asset classes for net worth (property, vehicle); milestones
- Price-change detection on subscriptions (partially in T16)
- Safe-to-spend morning summary notification (opt-in); goal-milestone celebrations
- Anomaly flags (unusually large transaction for its category)
- Weekly digest notification
- Configurable budget week anchor (see B19)
- Product decision needed: how should a positive-balance liability account (e.g. an overpaid credit card) be treated in net worth — still counted as debt today, pre-existing behavior surfaced during T1 code review
- UX: "Materialized N historical transactions" toast notification when a long-unprocessed recurring item (e.g. fresh CloudKit restore) generates a batch of backlogged occurrences on launch; correct per spec but silent bulk creation could surprise users (from T4 code review).
- UX: CSV import net-effect display (T8) when preview shows "Will increase X by $0.00" — consider suppressing the sentence entirely when the effect rounds to zero to reduce visual clutter (from T8 code review).
- Product decision needed: liability account balance wording in CSV import net-effect display — "Will increase" / "Will decrease" refers to the signed balance (negative = owed), which may read debt-inverted for users (e.g. "increasing" a negative $500 credit-card debt means paying off, decreasing it); verify product intent and consider debt-oriented wording (from T8 code review).
- T9 follow-ups (CSV import duplicate detection):
  - Nil-account dedupe bucket clarification — doc-comment noting that unassigned transactions (account = nil) form their own dedupe bucket and only match other unassigned transactions (not all transactions); the current phrase "same account when set" could be misread as ignore-account-when-none.
  - Double exact-equality in dedupe key — backlog note for Decimal migration (T12+) that the TransactionDuplicateKey will need to be updated to use Decimal instead of Double.
  - Optimization: unfiltered full-table transaction fetch at buildPreview is O(n) per preview render — fine for v1 and consistent with repo precedent, but consider a date-bounded #Predicate if transaction volumes grow to tens of thousands.
- T10 follow-ups (Balance edits as explicit adjustments):
  - Nil-category matchingTransactions realignment test — add a test case pinning that a categorized real expense is excluded from a nil-category budget's matchingTransactions result (current new test uses a categorized budget, so the nil-category edge case isn't covered).
  - AccountBalanceService.applyBalanceEdit single-caller safety note — currently has only one caller (AddAccountView save path); future second callers must capture oldBalance before any state mutation to avoid double-application of the delta.
  - Unparseable balance text UX hardening — AmountParser.parse ?? 0 previously silent-zeroed the balance on parse failure, now creates a visible full-delta adjustment (improvement in auditability, but new surface for user input errors); consider adding form validation to guard against empty/unparseable balance field and prevent accidental full-balance corrections from typos.
  - Account type-flip ledger entries — product-copy consideration for asset↔liability type changes during edit (e.g. changing a checking account to credit card creates a historical balance-correction transaction); numerically correct but may confuse users; verify desired behavior and update guidance/help text if needed.
- T12 follow-ups (Display-currency abstraction):
  - Settings toggle re-render wiring — when T13/future Settings screen adds a currency-override toggle, it must include @Observable/notification wiring to trigger re-renders across the app; currently CurrencyFormat.override is a bare static var with no SwiftUI dependency edge, so changes require app restart to take effect.
  - SafeToSpendView prose copy localization — the description text contains hard-coded currency examples "$0" and "$500" in algorithm explanations; localize these when full locale-string coverage is desired (currently out of scope for T12).
  - CompactCurrencyAxisFormatter symbol layout accepted v1 imprecision — the axis markers use prefix layout (€123, £456) which works well for EUR/GBP but looks slightly unbalanced for postfix locales like de_DE (€123), ja_JP (¥123), and fr_FR (123€); revisit if metrics localization becomes comprehensive, but acceptable for v1.
  - Optional DRY consistency pass — consider migrating bare .currency(code: CurrencyFormat.code) call sites to use CurrencyFormat.style(_:) / CurrencyFormat.money(_:locale:) helper methods for reduced duplication (Code Reviewer judged current mixed approach reasonable as-is).
- T13a follow-ups (DataExporter engine):
  - Optional: guard csvAmountString against non-finite values (NaN/Infinity) — currently emits non-reparseable "nan" literal; add `guard value.isFinite` if a future export path could produce non-finite amounts (theoretical today, but defensive).
  - Optional: add CSV round-trip test for special characters (commas, quotes) in category and account names — same csvField escaping helper is used uniformly for all columns (low risk), but explicit coverage would match the existing transaction CSV round-trip test for comprehensiveness.
  - Optional: cache fullBackupJSON Bundle.main.infoDictionary per call — currently read fresh each invocation (negligible cost), but if profiling identifies this as a hot-path, consider caching the result to avoid repeated info-dictionary lookups.
- T13b follow-ups (Settings screen + export entry point):
  - Minor consistency nit: three CSV computed properties (transactionsCSV, accountsCSV, transfersCSV in SettingsView) are referenced twice per row (evaluation runs twice per body render) — bind via local let/if-let pattern like the JSON row for clarity and consistency (deterministic/side-effect-free, low priority).
- T14 follow-ups (BalanceSnapshot history model):
  - Add direct test pinning snapshot-path liability sign math for an INCLUDED liability — currently no test verifies that a liability account with balance -5000 yields a snapshot that contributes -5000 to net worth (via -abs() sign logic); this is a second independent implementation of the sign-ternary pattern in money code and deserves explicit coverage for balance-adjustment correctness verification.
  - Add one-line comment at the scenePhase/.active handler in EggSpendApp documenting that onAppear and .onChange(.active) can both fire on foreground transition, and why update-in-place same-day snapshot deduplication is safe (last-launch-wins idempotence self-heals the double-capture race).
- T15 follow-ups (Forecast/SafeSpend double-count fix):
  - Optional: one-clause comment addendum at ForecastEngine.averageDailyNetFlow noting that user-edited generated transactions (e.g. a user manually changes a materialized recurring charge's amount) remain excluded from the drift baseline—they're still marked isGenerated, so filtering preserves the intended invariant (recurring paid out explicitly as events, not implicitly via drift).
- T16a follow-ups (Subscription detection engine):
  - Document outlier-poisoning limitation in SubscriptionDetector doc comments: detection uses unbounded transaction history; a single anomalous charge (e.g. trial price 0.99 appearing mid-history) causes the entire cluster to be rejected via allSatisfy stability gate, resulting in false-negatives (missed subscriptions); this is a limitation of the read-only detector engine, not a blocker — T16b's call-site wiring can address via recency windowing or outlier filtering.
  - T16b call-site decision: when passing transaction history to SubscriptionDetector, choose between (1) recency-windowed input slice (e.g. 12–24 months of recent transactions) to naturally exclude trial-price and old-bump anomalies, or (2) outlier-tolerant historical gate that ignores first/last outliers (all-but-one or all-but-highest/lowest) before computing mode/stability. The windowing vs. filtering decision should be documented in T16b's SubscriptionAuditView or associated logic.
  - Pin trial-price and mid-history-bump test cases once the T16b windowing/filtering direction is picked: test both the false-negative scenario (real subscription rejected on one-off trial charge) and the suppression (false positive where an unrelated high-value charge shouldn't poison the cluster).

### From TODO.md (user-ranked P0–P3 roadmap, committed to `main` 2026-07-08; see IMPLEMENTATION_PLAN.md "TODO.md reconciliation" for the full mapping — these are the items with no existing task ID)

- **Account reconciliation** (TODO.md P0) — compare EggSpend balances against a bank statement balance/date; surface likely causes (uncleared, duplicates, recent imports, post-statement-date transactions); mark transactions cleared per account statement; preserve asset/liability sign conventions.
- **Recurring transaction review queue** (TODO.md P1) — detect overdue recurring items on launch without auto-posting; review queue with skip/edit/post-one/post-all; low-friction opt-out to keep today's auto-posting behavior. Likely subsumes the "surface recurring-processing failures in UI" item above.
- **Monthly closeout flow** (TODO.md P1) — month-end review screen (income/expenses/savings rate/top categories/budget overruns/net-worth movement/goal progress), flags uncategorized transactions and missing account assignments, mark-month-reviewed persistence, reuses `MonthlyReviewCalculator`.
- **CSV import mapping presets** (TODO.md P2) — save/name/reuse column mappings per bank or card, separate transaction vs. account presets, auto-suggest on header match, auto-detection remains first-run fallback. Adjacent to T8/T9/T17.
- **Saved transaction filters** (TODO.md P2) — name and persist the current transaction filter (type/category/account/amount/date/generated-only/search); rename/update/delete; must not crash if a referenced category or account is later deleted.
- **Notification settings screen** (TODO.md P2) — central screen for system permission status (not-determined/denied/provisional/authorized), global on/off for budget alerts without deleting per-budget config, review upcoming recurring reminders, deep-link to system settings when denied. Adjacent to existing `NotificationScheduler`/`BudgetAlertCoordinator` and could share SettingsView with R2 (SyncStatus surfacing) and R9 (currency-override re-render wiring), both awaiting their own tasks with SettingsView as the dedicated host.
- **Goal funding suggestions** (TODO.md P3) — suggested monthly/per-paycheck contribution per active `SavingsGoal` with a target date, using linked-account balance when set; graceful handling of overdue/completed/no-target-date/zero-remaining goals; optionally surfaced alongside Safe-to-Spend.
- **Backup restore flow** (TODO.md "Later") — explicit follow-on to T13 (T13a engine + T13b export UI); T13a's validateBackup provides schema-version groundwork (lossless round-trip validation, version-gating), but applying decoded backup data back into ModelContext is out of scope; restore/import-validation path (including conflict resolution and selective restore per-model) to be designed as separate task.
- **Widgets** (TODO.md "Later") — safe-to-spend, upcoming bills, goal progress.
- **Multi-currency support** (TODO.md "Later") — flagged, not adopted: potential tension with the resolved T12 product decision (currency is display-only, derived from device locale, no per-account currency). Needs an explicit product decision before scoping, separate from T12.
- **Import duplicate review and merge workflow** (TODO.md "Later") — T9 follow-on; T9 (v1) is skip-only with no per-row override or post-import merge UI.
