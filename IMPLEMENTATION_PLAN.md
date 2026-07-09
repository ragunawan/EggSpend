# EggSpend — Implementation Plan (living document)

Owned by the Planner Agent. Detailed specs live in `docs/task-backlog.md` (T1–T24); audit context in `docs/audit-and-roadmap.md`. This file tracks execution state only.

**Loop protocol:** Planner selects → Repo Analyst inspects → Implementer changes → QA verifies → Code Review approves → Docs update → commit. A task advances only on QA pass + review approval. Stop conditions: destructive migration, missing product decision, credentials required, risky financial-data mutation, or unrelated build/test failure.

**Environment constraint:** this container has no Swift toolchain. QA is static; `xcodebuild test` must run on CI/macOS (see T11) before merging to `main`.

## Status board

| ID | Task | Priority | Status | Depends on | Approval needed |
|----|------|----------|--------|------------|-----------------|
| T1 | Shared NetWorthCalculator + liability sign fix | P0-1 | done (2026-07-08, commit pending) | — | no |
| T2 | Restrict net-worth reconstruction to account-linked transactions | P0-2 | done (2026-07-08, commit pending) | T1 | no |
| T3 | CSV amount/type parsing fixes | P0-3 | done (2026-07-08, commit pending) | — | no |
| T4 | Recurring end-date + infinite-loop guards | P0-4 | done (2026-07-08, commit pending) | — | no |
| T5 | Locale-safe amount entry | P0-5 | done (2026-07-08, commit pending) | — | no |
| T6 | Surface save failures in critical paths | P0-6 | pending | — | no |
| T7 | Archive accounts instead of delete | P1-1 | pending | T1 | no (decision resolved: archive) |
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

**Next up:** T6 (Surface save failures in critical paths).

## Completed

- T1 — Shared NetWorthCalculator + liability sign fix — done 2026-07-08. Added `EggSpend/Utilities/NetWorthCalculator.swift` (`current`, `totals`); adopted at all four call sites (DashboardView, NetWorthView, MetricsView:89, MonthlyReviewCalculator:113); extended `NetWorthCalculationTests`. QA pass-with-CI-caveat (no Swift toolchain in container); code review approved with zero required fixes.
- T2 — Restrict net-worth reconstruction to account-linked transactions — done 2026-07-08. Added `NetWorthCalculator.at(date:accounts:transactions:)`; deleted `MonthlyReviewCalculator.netWorth` and related calculate() delegation; MetricsView.netWorthTimeline delegates per bucket. Updated 2 existing tests (rewired to linked accounts) and added 3 new tests (unlinked-flat, excluded-liability-not-reversed, mixed exact arithmetic) in `MonthlyReviewCalculatorTests`. QA pass-with-CI-caveat; code review approved with zero required fixes (two follow-ups: trim stale comment in MetricsView, track transfer-boundary limitation as named risk item).
- T3 — CSV amount/type parsing fixes — done 2026-07-08. Rewrote `parseAmount` with sign-first detection (paren, leading, trailing, U+2212); embedded-minus → nil rejection; thousands/decimal logic unchanged. Type inference now uses expense/income keyword lists with amount-sign fallback for unknown types. Added table-driven test cases (16 type, 13 amount). QA round 1: FAIL — caught "pos" substring-colliding inside "deposit", misclassifying Deposit as expense; loop returned to implementer per protocol. Implementer revision: whole-word token matching for short keywords (split on non-alphanumerics); tests extended with Direct Deposit/DR/CR pins. QA round 2: PASS-WITH-CI-CAVEAT — Python-oracle-verified all 16 type cases + 13 amount cases; parseAmount unchanged from earlier pass; scope clean. Code review approved with zero required fixes. Follow-up: long keywords still substring-match (e.g. "sale" in "wholesale", "payment" in "Payment Received") — pre-existing pattern, revisit if real exports misfire.
- T4 — Recurring end-date + infinite-loop guards — done 2026-07-08. Removed item-level `endDate < now` skip in `processRecurringTransactions`; added `previousDueDate` capture + print-and-break guard when `advanceNextDueDate()` fails to strictly advance (safeguards infinite loop if Calendar.nextDate returns nil). Added 3 new tests (final-occurrence-for-ended-item, ended-item idempotent across relaunch, deep-backlog terminates with pinned 401 count). QA round 1: FAIL — test fixture off-by-one: 5-week-stale monthly item + endDate yesterday generated TWO occurrences, breaking count-1 assertion and introducing date flakiness. Loop returned to implementer per protocol. Implementer revision: fixture changed to nextDueDate = now−14 days, deterministic for all month lengths (monthly advance ≥28d overshoots now by ≥14d). QA round 2: PASS-WITH-CI-CAVEAT — fixture provably deterministic; production file byte-identical; scope surgical. Code review approved with zero required fixes. Follow-ups: (1) consider making Calendar injectable so non-advancing guard branch becomes testable (RecurringProjection already accepts a calendar); (2) UX note — long-unprocessed item (e.g. fresh CloudKit restore) can now materialize a batch of historical transactions silently; correct per spec but consider a "materialized N transactions" toast.
- T5 — Locale-safe amount entry — done 2026-07-08. New `EggSpend/Utilities/AmountParser.swift` (fast-path `Double(text)` fallback, then position-validated grouping with single decimal separator, non-empty all-digit fraction, and grouping candidates {., comma, space U+00A0 U+202F} minus decimalSep; first group 1–3 digits, subsequent exactly 3; rejects trailing separators). Swapped all `Double(text)` parse sites and `String(format:)` pre-fill sites in 6 views (AddTransactionView, AddAccountView with four fields, TransactionFilterView). Registered new file in `generate_project.py` + regenerated pbxproj. Added `AmountParserTests.swift` with 17 test cases. QA round 1: FAIL-WITH-TWO-FINDINGS — (a) fr_FR test assumed dot grouping but real ICU uses narrow no-break space (U+202F) causing test failure in CI; (b) 100x hazard: en_US paste "12,50" with old `Double(text)` → 12.50 (safe rejection), but if grouping fallback mistakenly strips comma → 1250 (wrong). Loop returned to implementer per protocol. Implementer revision: position-validated grouping logic rejects "12,50" in en_US (no grouping separator, so trailing comma invalid; fraction would be "50" but "5" is position 4 from decimal so not exactly 3-digit group); tests re-pinned (en_US "12,50" → nil, fr_FR space/U+202F/dot-grouping cases all pass). QA round 2: PASS — full matrix machine-checked via Python port (17 cases), both defects resolved (no false-positive grouping, fr_FR test correct), no regression for negatives (fast path still handles "-12.50", fallback rejects "-12,50" same as old code). Code review approved with zero required fixes. Follow-ups: (1) doc note or test pinning that locale fallback rejects signed input ("-12,50" → nil; fail-safe, unreachable from decimal pads today); (2) optional de_DE/negative round-trip test.

## Discovered follow-ups / new tickets

- NetWorthView calls `NetWorthCalculator.totals()` twice — minor cleanup opportunity (from T1 code review).
- Product question: a positive-balance liability account (e.g. an overpaid credit card) is still counted as debt everywhere — pre-existing behavior, needs a product decision eventually (from T1 code review).
- `NetWorthCalculator.totals` and `.current` could share one predicate/helper to reduce duplication (from T1 code review).
- Trim stale comment above MetricsView.netWorthTimeline pointing at deleted MonthlyReviewCalculator.netWorth documentation (from T2 code review).
- Track transfer-boundary limitation as a named register item: transfers between included and excluded accounts change net worth but are invisible to historical reconstruction (from T2 code review).
- CSV type inference: long keywords still substring-match (e.g. "sale" in "wholesale", "payment" in "Payment Received") — pre-existing pattern, revisit if real exports misfire (from T3 code review).
- Locale-safe amount entry: doc note or test pinning that locale fallback rejects signed input ("-12,50" → nil; fail-safe, unreachable from decimal pads today) (from T5 code review).
- Locale-safe amount entry: optional de_DE/negative round-trip test to expand coverage beyond en_US/fr_FR (from T5 code review).
- T11 follow-ups (CI workflow):
  1. Add `permissions: contents: read` hardening to GitHub Actions workflow.
  2. Tighter step-level timeout for simulator-boot hangs.
  3. Confirm `macos-26` runner label validity at merge time.
  4. Add `*.xcresult` to .gitignore.

## Blockers awaiting user decision

- T9: duplicate-match strictness (recommend exact same-day + amount + normalized title).
- T10: are balance-adjustment transactions visible in ledger / included in cash-flow stats? (Recommend visible in ledger, excluded from metrics.)
- T19: minimum iOS target acceptable if on-device model framework requires raising it.
