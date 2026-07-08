# EggSpend — Bugs & Risks Register

Working register for the agent loop. Full analysis with reproduction detail: `docs/audit-and-roadmap.md` §4–§5. Status values: open / in-progress / fixed(date, commit) / accepted-risk.

| # | Sev | Summary | Location | Fix task | Status |
|---|-----|---------|----------|----------|--------|
| B1 | Critical | Liability sign bug adds debt to net worth in Metrics timeline & Monthly Review | `MetricsView.swift:89`, `MonthlyReviewCalculator.swift:113` | T1 | fixed(2026-07-08) |
| B2 | High | Four divergent net-worth formulas; `includeInNetWorth` inconsistently respected | Dashboard/NetWorth/Metrics/MonthlyReview | T1 | fixed(2026-07-08) |
| B3 | High | Historical net-worth reconstruction reverses account-less transactions | `MonthlyReviewCalculator.swift:112`, `MetricsView.swift:88` | T2 | fixed(2026-07-08) |
| B4 | High | CSV transaction import can't link accounts, never updates balances | `CSVImportView.swift:363-408` | T8 | open |
| B5 | High | Amount entry broken in comma-decimal locales (`Double(amountText)`) | `AddTransactionView.swift:62` et al. | T5 | open |
| B6 | High | Currency hard-coded USD (76 sites) | app-wide | T12 | open |
| B7 | High | CloudKit multi-device: duplicate generated recurring transactions, double balance application | `RecurringTransaction.swift:132-151` | T23 | open |
| B8 | Medium | CSV type inference defaults unknown types to income; "credit" ambiguity | `CSVParser.swift:238-247` | T3 | fixed(2026-07-08) |
| B9 | Medium | `parseAmount` strips `-` mid-string; trailing-minus ignored; EU formats misparse | `CSVParser.swift:94-108` | T3 | fixed(2026-07-08) |
| B10 | Medium | Ended recurring items never materialize final overdue occurrences | `RecurringTransaction.swift:138` | T4 | open |
| B11 | Medium | Account deletion: no confirmation; orphans corrupt history; goals silently zero | `NetWorthView.swift:182-186` | T7 | open |
| B12 | Medium | Account edit silently rewrites balance from stale form state | `AddAccountView.swift:110-121` | T10 | open |
| B13 | Medium | Infinite-loop risk if `advanceNextDueDate` fails to advance | `RecurringTransaction.swift:108-141` | T4 | open |
| B14 | Medium | Budget alert state mutations may not be saved; CloudKit merge can dupe alerts | `Budget.swift:189-206`, `BudgetAlertCoordinator.swift` | T6 | open |
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
| R1 | `try?` saves swallow financial-data write failures | T6 |
| R2 | Silent CloudKit→local fallback; user may believe data is backed up | surface SyncStatus (batch with T13 Settings) |
| R3 | No app lock | T20 |
| R4 | No data export/portability | T13 |
| R5 | No CI — regressions land unnoticed | T11 | fixed(2026-07-08) — runner-side verification pending first real run |
| R6 | Manual `generate_project.py`/pbxproj sync — drift breaks builds | QA step 3 checks every loop |

**Note (2026-07-08):** B1/B2 fixed via new shared `NetWorthCalculator` (`EggSpend/Utilities/NetWorthCalculator.swift`), adopted by DashboardView, NetWorthView, MetricsView, and MonthlyReviewCalculator. Metrics and Monthly Review now respect `includeInNetWorth` like Dashboard/NetWorthView already did. B3 (historical reconstruction reversing account-less transactions) fixed via T2: new `NetWorthCalculator.at(date:accounts:transactions:)` method filters to account-linked transactions only. B21 (transfer-boundary limitation) discovered in T2 code review and registered as separate Medium-severity item for future resolution. B8/B9 fixed via T3: rewritten `parseAmount` with sign-first detection (paren, leading, trailing, U+2212), embedded-minus rejection, unchanged thousands/decimal logic; CSV type inference now uses expense/income keyword lists with amount-sign fallback, whole-word token matching for short keywords (pos/dr/cr); QA caught "pos" substring collision in "deposit" on round 1 (revision applied); round 2 pass with Python-oracle verification of all 16 type + 13 amount test cases.
