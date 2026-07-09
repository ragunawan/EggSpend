# EggSpend — Agent Loop Log

Append-only record of each loop iteration. Maintained by the Documentation Agent.

## Entry template

```
## Loop N — <date> — <Task ID>: <title>
- Planner: <selection + reason>
- Repo Analyst: <valid? blockers? approach>
- Implementer: <files changed, summary>
- QA: <verdict + key evidence; what's deferred to CI>
- Code Review: <verdict; required fixes if any; revision rounds>
- Docs: <files updated>
- Follow-ups filed: <list or none>
- Commit: <hash>
- Next task: <ID>
```

---

## Loop 1 — 2026-07-08 — T1: Shared NetWorthCalculator + liability sign fix
- Planner: selected T1 (P0-1, top correctness bug, no approval needed).
- Repo Analyst: task valid; confirmed sign inversion (liabilities stored negative, `-balance` double-negated); recommended porting Dashboard's `-abs()` formula; no blockers.
- Implementer: added `EggSpend/Utilities/NetWorthCalculator.swift` (`current`, `totals`); adopted at all four call sites (DashboardView, NetWorthView, MetricsView:89, MonthlyReviewCalculator:113); left T2's delta-reversal lines untouched; registered file in `generate_project.py` (FR 0x67) + regenerated pbxproj (also synced generator `CURRENT_PROJECT_VERSION` 2→5 + trailing newline to match checked-in pbxproj); rewired/extended `NetWorthCalculationTests` (mixed-accounts 49,200 case, `includeInNetWorth` exclusions, asset-always-counts invariant, empty input).
- QA: PASS-WITH-CI-CAVEAT (no Swift toolchain in container; arithmetic traced by hand; pbxproj regen byte-identical; `xcodebuild test` must run on CI/macOS).
- Code Review: APPROVE, zero required fixes. Optional follow-ups filed (see below).
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, FEATURE_BACKLOG.md, CHANGELOG.md.
- Follow-ups filed: (1) NetWorthView computes `totals()` twice — minor cleanup; (2) product question: positive-balance liability (overpaid credit card) counted as debt everywhere — pre-existing, needs product decision eventually; (3) `totals`/`current` could share one predicate.
- Commit: this loop's commit (next commit on branch `claude/finance-app-audit-roadmap-t8y2p4`).
- Next task: T2.

## Loop 2 — 2026-07-08 — T11: CI: GitHub Actions test workflow
- Planner: encoded user's pull-forward decision; T11 in_progress; T2 queued next.
- Repo Analyst: greenfield .github; shared scheme test-ready; all tests in-memory (no iCloud/notification needs on runner); flagged simulator-name fragility → recommended runtime device resolution.
- Implementer: created `.github/workflows/test.yml` only — triggers PR + push(main, claude/**); macos-26 runner, Xcode 26.0 pinned via setup-xcode; runtime simulator resolution (iPhone 17 exact match, else first iPhone, else clean failure) exported via GITHUB_ENV; xcbeautify best-effort with plain fallback under pipefail; xcresult artifact uploaded on failure.
- QA: PASS-WITH-CI-CAVEAT — YAML valid, structure audited, simulator-resolution python fixture-tested on all three paths; green-run and broken-test-fails criteria only verifiable on GitHub after push.
- Code Review: APPROVE, zero required fixes. Follow-ups filed: (1) add `permissions: contents: read` hardening; (2) tighter step-level timeout for simulator-boot hangs; (3) confirm macos-26 runner label validity at merge time; (4) gitignore *.xcresult.
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md.
- Follow-ups filed: (1) add hardening with `permissions: contents: read`; (2) step-level timeout for simulator-boot; (3) macos-26 runner label validity; (4) .gitignore *.xcresult.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T2.

## Loop 3 — 2026-07-08 — T2: Restrict net-worth reconstruction to account-linked transactions
- Planner: selected T2 (P0-2, dependency T1 done).
- Repo Analyst: task valid; recommended (orchestrator-approved) tighter filter `account?.countsTowardNetWorth ?? false` instead of literal `account != nil` for consistency with `current()`; flagged transfer-crossing-included/excluded-boundary gap as follow-up; noted two old tests asserted buggy behavior.
- Implementer: added `NetWorthCalculator.at(date:accounts:transactions:)` for historical reconstruction; deleted `MonthlyReviewCalculator.netWorth` and deleted calculate() delegation code; MetricsView.netWorthTimeline delegates to new `at()` per bucket; MonthlyReviewCalculatorTests — rewired 2 existing tests to linked accounts, added 3 new tests (unlinked-flat, excluded-liability-not-reversed, mixed exact arithmetic). No new files, no generator changes.
- QA: PASS-WITH-CI-CAVEAT — arithmetic traced, strict `>` boundary preserved, no leftover callers, no scope creep.
- Code Review: APPROVE, zero required fixes. Follow-ups: (1) trim now-stale comment above MetricsView.netWorthTimeline pointing at deleted calculator doc; (2) ensure transfer-boundary limitation (transfers between included and excluded accounts change net worth but are invisible to reconstruction) is tracked as named register item, not just code comment.
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md.
- Follow-ups filed: (1) trim stale MetricsView comment; (2) track transfer-boundary limitation as B21.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T3.

## Loop 4 — 2026-07-08 — T3: CSV amount/type parsing fixes
- Planner: selected T3 (P0-3, no dependencies).
- Repo Analyst: task valid; recommended sign-first parseAmount rewrite with embedded-minus rejection; keyword lists with sign fallback; EU `1.234,56` stays safely rejected (T5's scope); flagged 'payment' keyword imprecision as pre-existing pattern.
- Implementer: rewrote parseAmount (paren/leading/trailing minus incl U+2212 detected before stripping; embedded minus → nil; thousands/decimal logic unchanged); type inference now uses expense/income keyword lists with amount-sign fallback for unknown types; added table-driven tests (16 type cases, 13 amount cases).
- QA round 1: FAIL — caught "pos" substring-colliding inside "deposit", misclassifying Deposit rows as expense (would have failed CI). Loop returned to implementer per protocol.
- Implementer revision: whole-word token matching for short keywords pos/dr/cr (split on non-alphanumerics); tests extended with Direct Deposit/DR/CR pins.
- QA round 2: PASS-WITH-CI-CAVEAT — Python-oracle-verified all 16 type cases + 13 amount cases; parseAmount unchanged from earlier pass; scope clean.
- Code Review: APPROVE, zero required fixes. Follow-up filed: long keywords still substring-match (e.g. "sale" in "wholesale", "payment" in "Payment Received") — pre-existing pattern, revisit if real exports misfire.
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md.
- Follow-ups filed: long-keyword substring-matching follow-up.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T4.

## Loop 5 — 2026-07-08 — T4: Recurring end-date + infinite-loop guards
- Planner: selected T4 (P0-4, no dependencies).
- Repo Analyst: task valid; removing item-level endDate skip safe (per-occurrence break + dedupe bound generation); recommended inline non-advancing-date guard without making Calendar injectable; confirmed reminderFireDate handles nextDueDate > endDate.
- Implementer: removed item-level `endDate < now` skip in processRecurringTransactions; added previousDueDate capture + print-and-break guard when advanceNextDueDate() fails to strictly advance; dedupe and AccountBalanceService.apply untouched; 3 new tests (final-occurrence-for-ended-item, ended-item idempotent across relaunch, deep-backlog terminates with pinned 401 count); non-advancing branch documented as an accepted test gap (Calendar not injectable).
- QA round 1: FAIL — test fixture off-by-one: 5-week-stale monthly item + endDate yesterday generates TWO occurrences, making the count-1 assertion wrong and date-flaky. Loop returned to implementer per protocol.
- Implementer revision: fixture changed to nextDueDate = now−14 days; deterministic for all month lengths (monthly advance ≥28d overshoots now by ≥14d).
- QA round 2: PASS-WITH-CI-CAVEAT — fixture provably deterministic; production file byte-identical; scope surgical.
- Code Review: APPROVE, zero required fixes. Follow-ups: (1) consider making Calendar injectable so the non-advancing guard branch becomes testable (RecurringProjection already accepts a calendar); (2) UX note — a long-unprocessed item (e.g. fresh CloudKit restore) can now materialize a batch of historical transactions silently; correct per spec but consider a "materialized N transactions" toast; (3) reviewer verified all readers of nextDueDate handle the new persisted nextDueDate > endDate state.
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md.
- Follow-ups filed: (1) Calendar injectability for testable non-advancing branch; (2) materialization-toast UX feature.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T5.

## Loop 6 — 2026-07-08 — T5: Locale-safe amount entry
- Planner: selected T5 (P0-5, no dependencies).
- Repo Analyst: enumerated every `Double(text)` parse site (AddTransactionView:62, AddAccountView's four fields across two save branches, TransactionFilterView) and every `String(format: "%.2f")` pre-fill site; recommended manual normalization over NumberFormatter; documented literal-dot ambiguity rule; flagged TransactionFilterView as same bug class; orchestrator approved inclusion in scope.
- Implementer round 1: new `EggSpend/Utilities/AmountParser.swift` (fast-path `Double(text)`, then strip-grouping fallback); swapped all parse/pre-fill sites in 6 views (AddTransactionView, AddAccountView, TransactionFilterView); registered files in `generate_project.py` (FR 0x68/0x69) + regenerated pbxproj.
- QA round 1: PASS-WITH-CI-CAVEAT but two must-fix findings: (a) fr_FR test assumed dot grouping but real ICU uses narrow no-break space (U+202F), test would fail CI; (b) 100x hazard: en_US paste "12,50" with naive comma-strip fallback would yield 1250 where old code safely rejected it. Loop returned to implementer per protocol.
- Implementer round 2: replaced fallback with position-validated grouping (single decimal separator; non-empty all-digit fraction; grouping candidates {. , space U+00A0 U+202F} minus decimalSep; first group 1–3 digits, subsequent exactly 3); trailing-separator leniency removed ("12," → nil); tests re-pinned (en_US "12,50" → nil, fr_FR space/U+202F/dot-grouping cases all pass).
- QA round 2: PASS — full matrix machine-checked via Python port (17 cases); both defects resolved (no false-positive grouping, fr_FR test correct); no regression for negatives (fast path still handles "-12.50", fallback rejects "-12,50" same as old code).
- Code Review: APPROVE, zero required fixes. Follow-ups: (1) doc note or test pinning that locale fallback rejects signed input ("-12,50" → nil; fail-safe, unreachable from decimal pads today); (2) optional de_DE/negative round-trip test to expand locale coverage.
- Docs: IMPLEMENTATION_PLAN.md, AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md.
- Follow-ups filed: (1) doc/test pinning for signed-input fallback rejection; (2) de_DE/negative round-trip test.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T6.
