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

### From TODO.md (user-ranked P0–P3 roadmap, committed to `main` 2026-07-08; see IMPLEMENTATION_PLAN.md "TODO.md reconciliation" for the full mapping — these are the items with no existing task ID)

- **Account reconciliation** (TODO.md P0) — compare EggSpend balances against a bank statement balance/date; surface likely causes (uncleared, duplicates, recent imports, post-statement-date transactions); mark transactions cleared per account statement; preserve asset/liability sign conventions.
- **Recurring transaction review queue** (TODO.md P1) — detect overdue recurring items on launch without auto-posting; review queue with skip/edit/post-one/post-all; low-friction opt-out to keep today's auto-posting behavior. Likely subsumes the "surface recurring-processing failures in UI" item above.
- **Monthly closeout flow** (TODO.md P1) — month-end review screen (income/expenses/savings rate/top categories/budget overruns/net-worth movement/goal progress), flags uncategorized transactions and missing account assignments, mark-month-reviewed persistence, reuses `MonthlyReviewCalculator`.
- **CSV import mapping presets** (TODO.md P2) — save/name/reuse column mappings per bank or card, separate transaction vs. account presets, auto-suggest on header match, auto-detection remains first-run fallback. Adjacent to T8/T9/T17.
- **Saved transaction filters** (TODO.md P2) — name and persist the current transaction filter (type/category/account/amount/date/generated-only/search); rename/update/delete; must not crash if a referenced category or account is later deleted.
- **Notification settings screen** (TODO.md P2) — central screen for system permission status (not-determined/denied/provisional/authorized), global on/off for budget alerts without deleting per-budget config, review upcoming recurring reminders, deep-link to system settings when denied. Adjacent to R2 (SyncStatus, batch with T13 Settings) and existing `NotificationScheduler`/`BudgetAlertCoordinator`.
- **Goal funding suggestions** (TODO.md P3) — suggested monthly/per-paycheck contribution per active `SavingsGoal` with a target date, using linked-account balance when set; graceful handling of overdue/completed/no-target-date/zero-remaining goals; optionally surfaced alongside Safe-to-Spend.
- **Backup restore flow** (TODO.md "Later") — explicit T13 follow-on; T13's current spec is export-only, no restore/import-validation path yet.
- **Widgets** (TODO.md "Later") — safe-to-spend, upcoming bills, goal progress.
- **Multi-currency support** (TODO.md "Later") — flagged, not adopted: potential tension with the resolved T12 product decision (currency is display-only, derived from device locale, no per-account currency). Needs an explicit product decision before scoping, separate from T12.
- **Import duplicate review and merge workflow** (TODO.md "Later") — T9 follow-on; T9 (v1) is skip-only with no per-row override or post-import merge UI.
