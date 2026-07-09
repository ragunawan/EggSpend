# EggSpend — Bugs & Risks Register

Working register for the agent loop. Full analysis with reproduction detail: `docs/audit-and-roadmap.md` §4–§5. Status values: open / in-progress / fixed(date, commit) / accepted-risk.

| # | Sev | Summary | Location | Fix task | Status |
|---|-----|---------|----------|----------|--------|
| B1 | Critical | Liability sign bug adds debt to net worth in Metrics timeline & Monthly Review | `MetricsView.swift:89`, `MonthlyReviewCalculator.swift:113` | T1 | fixed(2026-07-08) |
| B2 | High | Four divergent net-worth formulas; `includeInNetWorth` inconsistently respected | Dashboard/NetWorth/Metrics/MonthlyReview | T1 | fixed(2026-07-08) |
| B3 | High | Historical net-worth reconstruction reverses account-less transactions | `MonthlyReviewCalculator.swift:112`, `MetricsView.swift:88` | T2 | fixed(2026-07-08) |
| B4 | High | CSV transaction import can't link accounts, never updates balances | `CSVImportView.swift:363-408` | T8 | open |
| B5 | High | Amount entry broken in comma-decimal locales (`Double(amountText)`) | `AddTransactionView.swift:62` et al. | T5 | fixed(2026-07-08) |
| B6 | High | Currency hard-coded USD (76 sites) | app-wide | T12 | open |
| B7 | High | CloudKit multi-device: duplicate generated recurring transactions, double balance application | `RecurringTransaction.swift:132-151` | T23 | open |
| B8 | Medium | CSV type inference defaults unknown types to income; "credit" ambiguity | `CSVParser.swift:238-247` | T3 | fixed(2026-07-08) |
| B9 | Medium | `parseAmount` strips `-` mid-string; trailing-minus ignored; EU formats misparse | `CSVParser.swift:94-108` | T3 | fixed(2026-07-08) |
| B10 | Medium | Ended recurring items never materialize final overdue occurrences | `RecurringTransaction.swift:138` | T4 | fixed(2026-07-08) |
| B11 | Medium | Account deletion: no confirmation; orphans corrupt history; goals silently zero | `NetWorthView.swift:182-186` | T7 | open |
| B12 | Medium | Account edit silently rewrites balance from stale form state | `AddAccountView.swift:110-121` | T10 | open |
| B13 | Medium | Infinite-loop risk if `advanceNextDueDate` fails to advance | `RecurringTransaction.swift:108-141` | T4 | fixed(2026-07-08) |
| B14 | Medium | Budget alert state mutations may not be saved; CloudKit merge can dupe alerts | `Budget.swift:189-206`, `BudgetAlertCoordinator.swift` | T6 | fixed(2026-07-08) |
| B15 | Medium | O(n²) transaction grouping; non-localized section headers | `TransactionsListView.swift:85-97` | T21 | open |
| B16 | Medium | Forecast/SafeSpend double-count recurring due today + drift overlap | `ForecastEngine.swift`, `RecurringProjection.swift:36-42` | T15 | open |
| B17 | Low | Savings-rate/percent truncation via `Int(...)` | `MetricsView.swift:444` | (minor, batch with T12) | open |
| B18 | Low | `Double` money math app-wide (documented) | app-wide | accepted for now | accepted-risk |
| B19 | Low | Weekly budget period anchored to locale week | `Budget.swift:101-114` | backlog | open |
| B20 | Low | Empty Metrics/Forecast charts for new users | `MetricsView.swift`, forecast views | T22 | open |
| B21 | Medium | Transfers between included and excluded accounts change net worth but are invisible to historical reconstruction | `NetWorthCalculator.swift:at()` | backlog (adjacent T14) | open |

## Risks (non-bug)
| # | Risk | Mitigation task |
|---|------|-----------------|
| R1 | `try?` saves swallow financial-data write failures | T6 — fixed(2026-07-08); note: recurring-failure UI surfacing remains backlog item |
| R2 | Silent CloudKit→local fallback; user may believe data is backed up | surface SyncStatus (batch with T13 Settings) |
| R3 | No app lock | T20 |
| R4 | No data export/portability | T13 |
| R5 | No CI — regressions land unnoticed | T11 | fixed(2026-07-08) — runner-side verification pending first real run |
| R6 | Manual `generate_project.py`/pbxproj sync — drift breaks builds | QA step 3 checks every loop |

**Note (2026-07-08):** B1/B2 fixed via new shared `NetWorthCalculator` (`EggSpend/Utilities/NetWorthCalculator.swift`), adopted by DashboardView, NetWorthView, MetricsView, and MonthlyReviewCalculator. Metrics and Monthly Review now respect `includeInNetWorth` like Dashboard/NetWorthView already did. B3 (historical reconstruction reversing account-less transactions) fixed via T2: new `NetWorthCalculator.at(date:accounts:transactions:)` method filters to account-linked transactions only. B21 (transfer-boundary limitation) discovered in T2 code review and registered as separate Medium-severity item for future resolution. B8/B9 fixed via T3: rewritten `parseAmount` with sign-first detection (paren, leading, trailing, U+2212), embedded-minus rejection, unchanged thousands/decimal logic; CSV type inference now uses expense/income keyword lists with amount-sign fallback, whole-word token matching for short keywords (pos/dr/cr); QA caught "pos" substring collision in "deposit" on round 1 (revision applied); round 2 pass with Python-oracle verification of all 16 type + 13 amount test cases. B10/B13 fixed via T4: removed item-level `endDate < now` skip permitting ended items to materialize final overdue occurrences; added previousDueDate capture + print-and-break guard when advanceNextDueDate() fails to advance, preventing infinite loop on Calendar.nextDate() nil returns; test fixture revised to nextDueDate = now−14 days for deterministic behavior across all month lengths; QA round 1 failed on date flakiness (fixture off-by-one), implementer revised and QA round 2 passed. B5 fixed via T5: new `AmountParser.swift` utility with fast-path `Double(text)` and position-validated grouping fallback (single decimal separator, non-empty all-digit fraction, grouping candidates {., comma, space U+00A0 U+202F} minus decimalSep, first group 1–3 digits, subsequent exactly 3); swapped all parse/pre-fill sites across 6 views (AddTransactionView, AddAccountView, TransactionFilterView); QA round 1 found fr_FR test used wrong grouping separator (ICU uses U+202F not dot) and 100x hazard ("12,50" in en_US could mis-parse as 1250 if grouping stripped comma naively); implementer applied position-validated logic to reject this case; QA round 2 passed with Python verification of full 17-case matrix and no regression on negatives. B14/R1 fixed via T6: CSVImportView now catches save failures and displays errorMessage instead of silently advancing to .done; failed saves rollback only their own tracked inserts (safe no-op on untracked objects, does not discard unrelated edits); BudgetAlertCoordinator now explicitly saves alert-dedupe state; processRecurringTransactions returns Bool (failures logged to console); PersistenceController.seedDefaultCategoriesIfNeeded returns Bool on save. QA round 1 caught data-integrity gap (failed save keeps user on .preview, retry would double-insert); implementer round 2 added rollback. Code review requested changes: rollback() could discard unrelated unsaved edits from other screens. Implementer round 3 replaced with targeted deletes. Code review approved round 3 (full path coverage, safe no-op for untracked objects). Follow-up: processRecurringTransactions Bool return unread by both onAppear callers; recurring failures reach console only (UI surfacing deferred to future task).
