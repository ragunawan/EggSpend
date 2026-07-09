# EggSpend — Implementation Plan (living document)

Owned by the Planner Agent. Detailed specs live in `docs/task-backlog.md` (T1–T24); audit context in `docs/audit-and-roadmap.md`. This file tracks execution state only.

**Loop protocol:** Planner selects → Repo Analyst inspects → Implementer changes → QA verifies → Code Review approves → Docs update → commit. A task advances only on QA pass + review approval. Stop conditions: destructive migration, missing product decision, credentials required, risky financial-data mutation, or unrelated build/test failure.

**Environment constraint:** this session runs on a real Mac with Xcode 26.6 + iPhone 17 simulators. `xcodebuild test` now runs locally; full test suite ran successfully this loop (TEST SUCCEEDED, 299 test cases, 0 failures), retroactively runtime-verifying all Phase 0 loops (T1–T6, T11) that previously carried "PASS-WITH-CI-CAVEAT".

## Status board

| ID | Task | Priority | Status | Depends on | Approval needed |
|----|------|----------|--------|------------|-----------------|
| T1 | Shared NetWorthCalculator + liability sign fix | P0-1 | done (2026-07-08, commit pending) | — | no |
| T2 | Restrict net-worth reconstruction to account-linked transactions | P0-2 | done (2026-07-08, commit pending) | T1 | no |
| T3 | CSV amount/type parsing fixes | P0-3 | done (2026-07-08, commit pending) | — | no |
| T4 | Recurring end-date + infinite-loop guards | P0-4 | done (2026-07-08, commit pending) | — | no |
| T5 | Locale-safe amount entry | P0-5 | done (2026-07-08, commit pending) | — | no |
| T6 | Surface save failures in critical paths | P0-6 | done (2026-07-08, commit pending) | — | no |
| T7 | Archive accounts instead of delete | P1-1 | done (2026-07-08, commit pending) | T1 | no (decision resolved: archive) |
| T8 | CSV import: account selection + balance application | P1-2 | pending | T2, T3 | no |
| T9 | CSV import duplicate detection | P1-3 | pending | T8 | **yes — dedupe strictness** |
| T10 | Balance edits as explicit adjustments | P1-4 | pending | — | **yes — ledger/metrics visibility** |
| T11 | CI: GitHub Actions test workflow — **pulled forward by user 2026-07-08** (ahead of T2; container has no Swift toolchain, CI closes the verification gap for all subsequent loops) | P1-5 | done (2026-07-08, commit pending) | — | no |
| T12 | Display-currency abstraction | P1-6 | pending | T5 | no (decision resolved: display-only) |
| T13 | CSV/JSON export + Settings screen | P1-7 | pending | — | no |
| T14 | BalanceSnapshot history model | P2-1 | pending | T1, T2 | no (additive schema) |
| T15 | Forecast/SafeSpend double-count fix | P2-2 | pending | T4 | no |
| T16 | Subscription detection + audit screen | P2-3 | pending | T3, T9 | no |
| T17 | Auto-categorization rules | P2-4 | pending | T8, T9 | no |
| T18 | "What changed this month?" card | P2-5 | pending | — | no |
| T19 | On-device AI narrative toggle | P2-6 | pending | T13, T18 | **yes — min iOS target** |
| T20 | Face ID app lock | P3-1 | pending | T13 | no |
| T21 | Transactions grouping perf + localized headers | P3-2 | pending | — | no |
| T22 | Empty states + onboarding | P3-3 | pending | — | no |
| T23 | CloudKit duplicate-sweep (generated transactions) | P3-4 | pending | T4 | **yes — deletes data, confirm before running** |
| T24 | Accessibility & localization pass | P3-5 | pending | — | no |

**Next up:** T8 (CSV import: account selection + balance application).

## Completed

- T1 — Shared NetWorthCalculator + liability sign fix — done 2026-07-08. Added `EggSpend/Utilities/NetWorthCalculator.swift` (`current`, `totals`); adopted at all four call sites (DashboardView, NetWorthView, MetricsView:89, MonthlyReviewCalculator:113); extended `NetWorthCalculationTests`. QA pass-with-CI-caveat (no Swift toolchain in container); code review approved with zero required fixes.
- T2 — Restrict net-worth reconstruction to account-linked transactions — done 2026-07-08. Added `NetWorthCalculator.at(date:accounts:transactions:)`; deleted `MonthlyReviewCalculator.netWorth` and related calculate() delegation; MetricsView.netWorthTimeline delegates per bucket. Updated 2 existing tests (rewired to linked accounts) and added 3 new tests (unlinked-flat, excluded-liability-not-reversed, mixed exact arithmetic) in `MonthlyReviewCalculatorTests`. QA pass-with-CI-caveat; code review approved with zero required fixes (two follow-ups: trim stale comment in MetricsView, track transfer-boundary limitation as named risk item).
- T3 — CSV amount/type parsing fixes — done 2026-07-08. Rewrote `parseAmount` with sign-first detection (paren, leading, trailing, U+2212); embedded-minus → nil rejection; thousands/decimal logic unchanged. Type inference now uses expense/income keyword lists with amount-sign fallback for unknown types. Added table-driven test cases (16 type, 13 amount). QA round 1: FAIL — caught "pos" substring-colliding inside "deposit", misclassifying Deposit as expense; loop returned to implementer per protocol. Implementer revision: whole-word token matching for short keywords (split on non-alphanumerics); tests extended with Direct Deposit/DR/CR pins. QA round 2: PASS-WITH-CI-CAVEAT — Python-oracle-verified all 16 type cases + 13 amount cases; parseAmount unchanged from earlier pass; scope clean. Code review approved with zero required fixes. Follow-up: long keywords still substring-match (e.g. "sale" in "wholesale", "payment" in "Payment Received") — pre-existing pattern, revisit if real exports misfire.
- T4 — Recurring end-date + infinite-loop guards — done 2026-07-08. Removed item-level `endDate < now` skip in `processRecurringTransactions`; added `previousDueDate` capture + print-and-break guard when `advanceNextDueDate()` fails to strictly advance (safeguards infinite loop if Calendar.nextDate returns nil). Added 3 new tests (final-occurrence-for-ended-item, ended-item idempotent across relaunch, deep-backlog terminates with pinned 401 count). QA round 1: FAIL — test fixture off-by-one: 5-week-stale monthly item + endDate yesterday generated TWO occurrences, breaking count-1 assertion and introducing date flakiness. Loop returned to implementer per protocol. Implementer revision: fixture changed to nextDueDate = now−14 days, deterministic for all month lengths (monthly advance ≥28d overshoots now by ≥14d). QA round 2: PASS-WITH-CI-CAVEAT — fixture provably deterministic; production file byte-identical; scope surgical. Code review approved with zero required fixes. Follow-ups: (1) consider making Calendar injectable so non-advancing guard branch becomes testable (RecurringProjection already accepts a calendar); (2) UX note — long-unprocessed item (e.g. fresh CloudKit restore) can now materialize a batch of historical transactions silently; correct per spec but consider a "materialized N transactions" toast.
- T5 — Locale-safe amount entry — done 2026-07-08. New `EggSpend/Utilities/AmountParser.swift` (fast-path `Double(text)` fallback, then position-validated grouping with single decimal separator, non-empty all-digit fraction, and grouping candidates {., comma, space U+00A0 U+202F} minus decimalSep; first group 1–3 digits, subsequent exactly 3; rejects trailing separators). Swapped all `Double(text)` parse sites and `String(format:)` pre-fill sites in 6 views (AddTransactionView, AddAccountView with four fields, TransactionFilterView). Registered new file in `generate_project.py` + regenerated pbxproj. Added `AmountParserTests.swift` with 17 test cases. QA round 1: FAIL-WITH-TWO-FINDINGS — (a) fr_FR test assumed dot grouping but real ICU uses narrow no-break space (U+202F) causing test failure in CI; (b) 100x hazard: en_US paste "12,50" with old `Double(text)` → 12.50 (safe rejection), but if grouping fallback mistakenly strips comma → 1250 (wrong). Loop returned to implementer per protocol. Implementer revision: position-validated grouping logic rejects "12,50" in en_US (no grouping separator, so trailing comma invalid; fraction would be "50" but "5" is position 4 from decimal so not exactly 3-digit group); tests re-pinned (en_US "12,50" → nil, fr_FR space/U+202F/dot-grouping cases all pass). QA round 2: PASS — full matrix machine-checked via Python port (17 cases), both defects resolved (no false-positive grouping, fr_FR test correct), no regression for negatives (fast path still handles "-12.50", fallback rejects "-12,50" same as old code). Code review approved with zero required fixes. Follow-ups: (1) doc note or test pinning that locale fallback rejects signed input ("-12,50" → nil; fail-safe, unreachable from decimal pads today); (2) optional de_DE/negative round-trip test.
- T6 — Surface save failures in critical paths — done 2026-07-08. (1) CSVImportView: added do/catch in import logic (previously advanced to .done regardless of save outcome), now displays errorMessage on save failure and allows retry from .preview state without duplicate inserts (targeted rollback of only this import's tracked inserts on catch). (2) BudgetAlertCoordinator: explicit save after alert-dedupe state mutations (previously never persisted state). (3) processRecurringTransactions: added @discardableResult Bool return tracking success/failure (previously returned Void, failures reached console only via print). (4) PersistenceController.seedDefaultCategoriesIfNeeded: added @discardableResult Bool with explicit save (previously logged to console on error only). Added 2 tests: alert-state persists across a fresh ModelContext, and recurring success-path returns true. QA round 1: FAIL — found newly-reachable data-integrity gap: failed save keeps user on .preview state, retry would double-insert rows (previously unreachable since UI always advanced to .done). Loop returned to implementer per protocol. Implementer round 2: added modelContext.rollback() in the catch. Code Review: REQUEST CHANGES — blanket rollback() on shared main context could silently discard unrelated unsaved edits from other screens. Loop returned to implementer per protocol. Implementer round 3: replaced rollback with targeted deletes of only this import's tracked inserts (insertedTransactions/insertedAccounts locals), a safe no-op for untracked objects. Code Review re-verdict: APPROVE. Confirmed full insert-path coverage and that deleting inserted-but-unsaved objects is safe. Follow-ups: (1) processRecurringTransactions Bool return still unread by both onAppear callers — recurring failures reach console only; file explicit backlog item "surface recurring-processing failures in UI" so T6 isn't overstated as fully closed; (2) optional shared logging helper instead of print (stylistic)."

- T7 — Archive accounts instead of delete — done 2026-07-08. Added `Account.isArchived` Bool flag (CloudKit-safe default false); `NetWorthCalculator.current` and `NetWorthCalculator.totals` exclude archived accounts; `ForecastEngine.liquidBalance` excludes archived (covers SafeSpendCalculator transitively); `CashFlowCalendarView.bills` filter excludes archived; `NetWorthView` presents archive swipe with confirmation dialog, archived section with grayed rows (no DebtPayoffPlannerView link), Unarchive action, and separately-confirmed true Delete; removed deleteAccounts helper; four pickers (`AddRecurringTransactionView`, `AddSavingsGoalView`, `TransactionDetailView`, `CategoryBudgetDetailView`) filter `accounts.filter { !$0.isArchived || $0 == currentSelection }` to support keep-selected pattern; `TransactionFilterView` deliberately left unfiltered (can view history of archived accounts); added 5 new tests (`testArchivedAccountExcludedFromCurrentAndTotals`, `testArchivedLiabilityExcludedFromCurrentAndTotals`, `testUnarchivingAccountRestoresPreviousTotals` in NetWorthCalculationTests; `testNetWorthAtDateIgnoresTransactionsOnArchivedAccount` in MonthlyReviewCalculatorTests; `testLiquidBalanceExcludesArchivedCheckingAccount` in CashFlowForecastTests). No new files; `generate_project.py` regeneration byte-identical. QA: PASS (static trace of all filters, consumer sweep, picker bindings, dialog state); two nits: swipe ordering, recurring-on-archived forecast gap (see follow-ups). Environment milestone: first real `xcodebuild test` run available — full suite TEST SUCCEEDED, 299 tests, all 5 new tests pass. Code Review round 1: REQUEST CHANGES — archived-row trailing swipe listed destructive Delete first, full swipe would trigger delete confirmation; escalated QA's swipe-ordering nit to required, citing CategoryManagementView leading/trailing-swipe precedent and financial-data mis-tap risk. Implementer round 2: Unarchive → leading edge (allowsFullSwipe: true), Delete alone on trailing (allowsFullSwipe: false). Code Review re-verdict: APPROVE (verified via file diff + swiftc -parse). Test suite re-run after fix: TEST SUCCEEDED. Follow-ups: (1) Medium risk: recurring transactions linked to archived accounts keep materializing and mutating its balance silently via processRecurringTransactions (RecurringTransaction.swift:144-173) — deliberate T7 scope cut, needs product decision or follow-up task; (2) Low risk: forecast upcoming events / calendar recurring occurrences not filtered by archived account (ForecastEngine.swift:61-74, CashFlowCalendarView.swift:24-25), inconsistent with bills filter; (3) AccountsView.swift is dead code (unreachable from ContentView, only self-referenced in its own #Preview) — candidate for deletion (with generate_project.py/pbxproj update) or wiring up; (4) UX: consider pausing or surfacing recurring transactions on archived accounts.

## Discovered follow-ups / new tickets

- NetWorthView calls `NetWorthCalculator.totals()` twice — minor cleanup opportunity (from T1 code review).
- Product question: a positive-balance liability account (e.g. an overpaid credit card) is still counted as debt everywhere — pre-existing behavior, needs a product decision eventually (from T1 code review).
- `NetWorthCalculator.totals` and `.current` could share one predicate/helper to reduce duplication (from T1 code review).
- Trim stale comment above MetricsView.netWorthTimeline pointing at deleted MonthlyReviewCalculator.netWorth documentation (from T2 code review).
- Track transfer-boundary limitation as a named register item: transfers between included and excluded accounts change net worth but are invisible to historical reconstruction (from T2 code review).
- CSV type inference: long keywords still substring-match (e.g. "sale" in "wholesale", "payment" in "Payment Received") — pre-existing pattern, revisit if real exports misfire (from T3 code review).
- Locale-safe amount entry: doc note or test pinning that locale fallback rejects signed input ("-12,50" → nil; fail-safe, unreachable from decimal pads today) (from T5 code review).
- Locale-safe amount entry: optional de_DE/negative round-trip test to expand coverage beyond en_US/fr_FR (from T5 code review).
- Surface recurring-processing failures in UI instead of console-only: T6 added Bool return tracking but both onAppear callers ignore it; follow-up: display a banner/toast when recurring materialization fails (from T6 code review).
- Optional shared logging helper in lieu of bare print() calls (from T6 code review).
- T11 follow-ups (CI workflow):
  1. Add `permissions: contents: read` hardening to GitHub Actions workflow.
  2. Tighter step-level timeout for simulator-boot hangs.
  3. Confirm `macos-26` runner label validity at merge time.
  4. Add `*.xcresult` to .gitignore.

## Milestone: ALL P0 TASKS (T1–T6) COMPLETE

As of 2026-07-08, all P0-priority correctness and stability fixes have been implemented and approved:
- T1: Net worth calculation and liability sign bugs fixed; shared NetWorthCalculator adopted app-wide.
- T2: Historical net worth now respects account-linked filters consistently.
- T3: CSV parsing sign detection and type inference fixed; whole-word token matching for short keywords.
- T4: Recurring end-date and infinite-loop guards added; failed date advances log and break safely.
- T5: Locale-safe amount entry with position-validated grouping fallback across all form fields.
- T6: Save failures now surface instead of silently swallowing data; import rollback prevents double-inserts; alert dedupe state explicitly persisted; recurring failures logged to console (UI surfacing deferred to T7+ cycle).

Next task: T7 (Archive accounts instead of delete).

## Blockers awaiting user decision

- T9: duplicate-match strictness (recommend exact same-day + amount + normalized title).
- T10: are balance-adjustment transactions visible in ledger / included in cash-flow stats? (Recommend visible in ledger, excluded from metrics.)
- T19: minimum iOS target acceptable if on-device model framework requires raising it.

## TODO.md reconciliation (loop 8, 2026-07-08)

The user committed `TODO.md` (repo root) directly to `main` (commits 77ade03, 80a5357) — a separate P0–P3 roadmap sorted by expected user value. It is informational input for future prioritization passes; it does **not** reorder the already-committed T7–T13 queue this loop. Mapping:

- TODO P0 "Local Data Export And Backup" → aligns with **T13** (CSV/JSON export). TODO.md's more detailed requirements — versioned JSON backup with schema version/export date/app version/build number, export of *every* app-owned entity including `Transfer` and `SavingsGoal` (not just the five models in T13's current file list), CSV round-trip tests, and import-validation groundwork for a future restore flow — should be folded into T13's spec when T13 is picked up for implementation.
- TODO P0 "Account Reconciliation" → no existing task ID; new, added to `FEATURE_BACKLOG.md` inbox.
- TODO P1 "Budget Rollover" → overlaps the existing inbox line ("Rollover budgets; overall monthly budget across categories"); TODO.md's spec is more detailed (per-budget opt-in, negative-rollover decision, month-boundary/leap-year tests) and now supersedes it — inbox entry updated with a pointer to TODO.md rather than duplicated.
- TODO P1 "Recurring Transaction Review" → new; added to inbox. Adjacent to T4 (done) and the existing "surface recurring-processing failures in UI" follow-up — a review queue would likely subsume that follow-up.
- TODO P1 "Monthly Closeout Flow" → new; added to inbox. Reuses `MonthlyReviewCalculator`.
- TODO P2 "CSV Import Mapping Presets" → new; added to inbox. Adjacent to T8/T9/T17.
- TODO P2 "Saved Transaction Filters" → new; added to inbox.
- TODO P2 "Notification Settings" → new; added to inbox. Adjacent to `NotificationScheduler`/`BudgetAlertCoordinator` and to R2 in `BUGS_AND_RISKS.md` (surface SyncStatus, already slated to batch with T13's Settings screen).
- TODO P3 "Goal Funding Suggestions" → new; added to inbox. Adjacent to `SavingsGoal`/`SafeSpendCalculator`.
- TODO P3 "Lightweight Onboarding" → aligns with **T22** (Empty states + onboarding); T22 already covers first-run onboarding — fold in the sample-data-reset requirement when T22 is picked up.
- TODO "Later: App lock with Face ID or passcode" → already on the board as **T20** (P3-1).
- TODO "Later: Backup restore flow" → new; added to inbox as an explicit T13 follow-on (T13's current spec scopes export only, no restore).
- TODO "Later: iCloud sync diagnostics screen" → already tracked as R2 in `BUGS_AND_RISKS.md`.
- TODO "Later: Widgets" → new; added to inbox.
- TODO "Later: Multi-currency support" → potential tension with the resolved product decision behind T12 (currency display is display-only, no per-account currency tracking); flagged in inbox for an explicit future decision rather than silently folded into T12.
- TODO "Later: Receipt photo attachments" → already in inbox ("Transaction splitting; receipt photo attachments").
- TODO "Later: Rule-based auto-categorization" → already on the board as **T17** (P2-4).
- TODO "Later: Import duplicate review and merge workflow" → adjacent to T9 (duplicate detection); a review/merge UI is beyond T9's v1 scope (T9 is skip-only) — added to inbox as a T9 follow-on.

No changes were made to the committed T1–T13 status board rows or priority order as a result of this reconciliation.
