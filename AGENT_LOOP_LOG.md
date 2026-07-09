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

## Loop 7 — 2026-07-08 — T6: Surface save failures in critical paths
- Planner: selected T6 (P0-6, last open P0).
- Repo Analyst: confirmed CSVImportView advanced to .done regardless of save outcome; BudgetAlertCoordinator never saved alert-dedupe state at all; processRecurringTransactions already caught+printed (post-T4) but returned Void; recommended minimal design (do/catch + errorMessage in import; explicit save in the context overload; @discardableResult Bool; seed saves log-only).
- Implementer round 1: implemented all four production changes + 2 tests (alert-state persists across a fresh ModelContext; recurring success-path returns true; failure branches documented as inspection-covered).
- QA: FAIL — found a newly-reachable data-integrity gap: failed save keeps user on .preview, so retry would double-insert rows (previously unreachable since the UI always advanced to .done).
- Implementer round 2: added modelContext.rollback() in the catch.
- Code Review: REQUEST CHANGES — blanket rollback() on the shared main context could silently discard unrelated unsaved edits from other screens.
- Implementer round 3: replaced rollback with targeted deletes of only this import's tracked inserts (insertedTransactions/insertedAccounts locals).
- Code Review re-verdict: APPROVE. Confirmed full insert-path coverage and that deleting inserted-but-unsaved objects is a safe no-op. Follow-ups: (1) processRecurringTransactions Bool return still unread by both onAppear callers — recurring failures reach console only; file explicit backlog item "surface recurring-processing failures in UI" so T6 isn't overstated as fully closed; (2) optional shared logging helper instead of print (stylistic).
- Docs: IMPLEMENTATION_PLAN.md (T6 → done; next up T7; added two follow-ups; milestone note: P0 tasks complete), AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md (B14 fixed; R1 fixed with note), CHANGELOG.md, FEATURE_BACKLOG.md.
- Follow-ups filed: (1) surface recurring-processing failures in UI (banner/toast); (2) optional shared logging helper.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T7.

## Loop 8 — 2026-07-08 — T7: Archive accounts instead of delete
- Planner: confirmed T7 (P1-1, dependency T1 done); reconciled user's new TODO.md into registers (mapping + new inbox items; no reorder of committed queue).
- Repo Analyst: found AccountsView.swift is dead code (skip); mapped exact consumers (NetWorthCalculator, ForecastEngine, CashFlowCalendarView, four pickers); flagged Picker blank-selection edge case for archived-linked accounts (AddRecurringTransactionView/AddSavingsGoalView); confirmed all Account relationships already .nullify so true-delete needs no schema change; #Predicate-on-Bool precedent exists but recommended in-memory filtering to support keep-selected pattern.
- Implementer round 1: Account.isArchived (CloudKit-safe default); NetWorthCalculator current/totals/at exclude archived; ForecastEngine.liquidBalance excludes archived (covers SafeSpendCalculator transitively); CashFlowCalendarView.bills filter; NetWorthView assets/liabilities exclude archived + Archive swipe with confirmationDialog + archived section (greyed, Unarchive, separately-confirmed true Delete, no DebtPayoffPlannerView link) + removed deleteAccounts helper; four pickers use accounts.filter { !$0.isArchived || $0 == currentSelection }; TransactionFilterView deliberately unfiltered; 5 new tests (testArchivedAccountExcludedFromCurrentAndTotals, testArchivedLiabilityExcludedFromCurrentAndTotals, testUnarchivingAccountRestoresPreviousTotals in NetWorthCalculationTests; testNetWorthAtDateIgnoresTransactionsOnArchivedAccount in MonthlyReviewCalculatorTests; testLiquidBalanceExcludesArchivedCheckingAccount in CashFlowForecastTests). No new files; generate_project.py regeneration byte-identical.
- QA: PASS (static trace of all filters, consumer sweep, picker bindings, dialog state; two nits: swipe ordering, recurring-on-archived forecast gap). ENVIRONMENT MILESTONE: real xcodebuild test run available for the first time — full suite TEST SUCCEEDED, 299 tests, all 5 new tests pass.
- Code Review round 1: REQUEST CHANGES — archived-row trailing swipe listed destructive Delete first, full swipe would trigger delete confirmation; escalated QA's nit to required citing CategoryManagementView leading/trailing precedent and financial-data mis-tap risk.
- Implementer round 2: Unarchive → leading edge (allowsFullSwipe: true), Delete alone on trailing (allowsFullSwipe: false).
- Code Review re-verdict: APPROVE (verified via file diff + swiftc -parse).
- Test suite re-run after fix: TEST SUCCEEDED.
- Docs: IMPLEMENTATION_PLAN.md (T7 → done; next up T8; environment constraint updated; T7 entry added to Completed; follow-ups added), AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md (B11 fixed; two new risk items added; R5 updated), FEATURE_BACKLOG.md (two new inbox items), CHANGELOG.md.
- Follow-ups filed: (1) Medium risk — recurring transactions linked to archived accounts keep materializing and mutating its balance silently via processRecurringTransactions (deliberate T7 scope cut, needs product decision or follow-up task); (2) Low risk — forecast upcoming events / calendar recurring occurrences not filtered by archived account, inconsistent with bills filter; (3) AccountsView.swift is dead code, candidate for deletion or wiring up; (4) UX: consider pausing or surfacing recurring transactions on archived accounts.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T8.

## Loop 9 — 2026-07-09 — T8: CSV import: account selection + balance application
- Planner: T8 selected for loop 9 (marked in_progress 2026-07-08 from prior session; loop resumed from right after planner phase).
- Repo Analyst: task valid; deps T2/T3 done; mapped CSVImportView (pick→map→preview→done wizard, T6 targeted-rollback via insertedTransactions/insertedAccounts locals); flagged CRITICAL hazard — selectedImportAccount is a pre-existing persisted object not covered by T6 targeted deletes, so a failed save would leave the account balance dirty and retry would double-apply; required symmetric AccountBalanceService.reverse in the catch block before the deletes. Also: unarchived-filter for picker per T7 (no keep-selected exception needed — fresh selection only); file-scoped non-private netBalanceEffect helper for testability; no new files → no pbxproj change.
- Implementer (round 1, no revisions needed): CSVImportView.swift — @Query(sort: \Account.name) accounts + availableAccounts (!isArchived); @State selectedImportAccount (nil default) + applyBalanceToggle (true default); "Account" Section on map step (transactions import only) with None+unarchived Picker and conditional Toggle; .onChange(of: selectedImportAccount) resets toggle to true only on nil→non-nil; net-effect sentence above Import button on preview step gated on (transactions && account selected && toggle on), wording increase/decrease derived from the sign of the computed effect, .currency(code: "USD") formatting; file-scoped netBalanceEffect(of:) sums isValid rows with type.sign * amount (same filter performImport uses); performImport passes account: selectedImportAccount into Transaction(...) unconditionally and calls AccountBalanceService.apply per row when toggle on; catch block reverses (AccountBalanceService.reverse per inserted tx, same applyBalanceToggle guard) BEFORE targeted deletes. Tests: 4 new in TransactionAccountTests.swift — testNetBalanceEffectSumsOnlyValidRowsWithSign, testImportingExpensesWithToggleOnReducesAccountBalance, testImportingExpensesWithToggleOffLeavesBalanceUnchangedButLinksAccount, testReversingAllImportedTransactionsRestoresOriginalBalance. No new files; generate_project.py regeneration byte-identical.
- QA: PASS. Real xcodebuild test on iPhone 17 Pro simulator: TEST SUCCEEDED, 303/303 (299→303, all 4 new tests pass). All 5 acceptance criteria traced with concrete arithmetic (e.g. 3 expenses 42.50/18.25/63.40 into $1000 → 875.85; reversal restores exactly 1000). pbxproj byte-identical after regeneration. No scope creep. Unverifiable statically: on-device rendering of new section/sentence; true end-to-end save-failure path through performImport (tests pin the primitives, not the private view method).
- Code Review: APPROVE, zero required fixes. Optional follow-ups filed (record these in the appropriate registers): (1) netBalanceEffect is pure money-math at top level of a Views file (file-scoped for testability) — consider relocating to Utilities/CSVParser.swift in a cleanup pass; (2) Net effect of exactly 0 renders "Will increase X by $0.00" — consider suppressing the sentence when the effect rounds to zero; (3) Liability accounts: increase/decrease wording refers to the literal signed balance (negative = owed), which may read debt-inverted to users — product-copy consideration; (4) Retry-path safety implicitly depends on the wizard having no back-navigation from .preview to .map; add a comment documenting this invariant so future back-button work doesn't silently break reversal correctness; (5) New tests pin AccountBalanceService/netBalanceEffect primitives, not performImport itself (private, view-bound) — a future edit dropping the applyBalanceToggle guard inside performImport wouldn't be caught; remember when touching this file for T9 dedupe.
- Docs: IMPLEMENTATION_PLAN.md (T8 → done 2026-07-09; next up paragraph updated; 5 follow-ups added to discovered list), AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md (B4 marked fixed), CHANGELOG.md.
- Follow-ups filed: (1) netBalanceEffect relocation to Utilities (cleanup); (2) suppress net effect sentence when effect = 0; (3) liability account increase/decrease wording — product-copy decision; (4) document no-back-navigation invariant; (5) performImport test coverage gap note for T9.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T9/T10 blocked on product decisions; next unblocked by priority is T12.

## Loop 9.5 — 2026-07-09 — CI hotfix: Tests workflow Xcode pin (orchestrator hotfix, abbreviated loop)
- Trigger: standing user rule — "if CI reveals failures in already-committed loops, fix them as the immediate next task." Post-T8-push check of GitHub Actions (public REST API; `gh` no longer installed on this machine, repo auth is SSH-only) showed the Tests workflow has NEVER passed: every run since T11 landed (runs 1–14, both branch and main) concluded `failure`; run 15 (T8 commit 7abe18b) queued and expected to fail identically.
- Diagnosis: step-level API data showed setup/checkout/simulator-resolve succeeding and only "Run tests" failing, with a suspiciously tiny (4 KB) test-results artifact. Downloaded the run-14 xcresult via nightly.link (unauthenticated artifact proxy for public repos); it contains a single error: "Unable to find a destination … iOS 26.0 is not installed. Please download and install the platform." Root cause: `setup-xcode` pin `xcode-version: '26.0'` selects an Xcode on the macos-26 image whose iOS simulator platform is not installed — the image only ships runtimes for its default (newest) Xcode. Not a code failure: the same commits pass locally (303/303 on Xcode 26.6).
- Fix: `.github/workflows/test.yml` — pin `latest-stable` instead of `'26.0'`, with a comment documenting the failure mode. macos-26's latest-stable is still Xcode 26.x, so the iPhone 17-family simulator assumption holds.
- Protocol note: one-line YAML hotfix applied directly by the orchestrator (no implementer/QA/review agents); verification is the next CI run itself, observable only after push. QA equivalent: local suite already green on the same commit; the workflow's only change is which Xcode CI selects.
- Verification: pending — first green run to be confirmed after push; if the run still fails, diagnose the new xcresult artifact the same way.
- Remaining T11 follow-ups untouched (permissions hardening, step timeout, .gitignore *.xcresult) — left for a dedicated cleanup task to keep this commit single-purpose.
- Next task: verify CI run goes green, then T12 (T9/T10 remain decision-blocked).

## Loop 10 — 2026-07-09 — T9: CSV import duplicate detection
- Planner: user resolved the two outstanding product decisions via AskUserQuestion at loop start. T9 (dedupe strictness): exact same-day duplicate = same calendar day + same amount + case/whitespace-normalized title + same account (when set); no ±1-day window, no per-row override in v1. T10 (balance adjustments visibility): visible in Transactions ledger, excluded from income/expense/cash-flow/savings-rate metrics (decision deferred T10 to next loop). T9 selected and marked in_progress. CI milestone confirmed: Tests workflow now green (run 16, commit 56edc99, first successful GitHub Actions run across all 16 prior runs).
- Repo Analyst: task valid; dep T8 done (loop 9); critical interaction with T8: duplicates must be excluded from netBalanceEffect/ready-count/Import button (introduce willImport = isValid && !isDuplicate, keep isValid purely structural). Approach: within-file duplicates need a growing seen-set seeded from DB keys; dedupe computed once in buildPreview (selectedImportAccount final by then; no back-navigation invariant from T8); baked into txResults as single source of truth. buildPreview fetches all transactions unfiltered (no Date-range #Predicate precedent in repo); include isGenerated recurring-materialized transactions in matching (deliberate — bank row colliding with materialized recurring charge is a real duplicate); key has no type/sign dimension — refund vs purchase same day/amount/title collide, accepted v1 imprecision.
- Implementer (round 1, no revisions): CSVParser.swift — new normalizedTitle property (lowercase/trim/collapse whitespace). ParsedTransactionResult gains defaulted isDuplicate + willImport (source-compatible, all 7-arg call sites unmodified). CSVImportView.swift — file-scoped TransactionDuplicateKey (Hashable: startOfDay day + positive Double amount + normalizedTitle + optional accountID UUID?); duplicateKey() method; markDuplicates(in:existingKeys:accountID:) with growing seen-set (invalid rows pass through unmarked, don't poison set). Key definition includes accepted-imprecision doc comment. buildPreview fetches all transactions unfiltered, keys existing by tx.account?.id vs rows by selectedImportAccount?.id. isValid→willImport switch in netBalanceEffect, summaryBar ready count, Import button count; third summaryBar bucket "N duplicates". TransactionPreviewRow "Duplicate — will skip" treatment (dimming via willImport, invalid takes icon precedence). performImport: duplicateSkippedCount reset, isDuplicate skip AFTER isValid guard BEFORE insert/apply (duplicates never enter insertedTransactions → T8 catch-block reversal stays symmetric; doc forbids re-deriving). doneStep "N duplicates skipped" line gated on >0. Tests: 8 new — testNormalizedTitleCaseAndWhitespace (CSVParserTests); testMarkDuplicatesSkipsRowMatchingExistingTransaction, testMarkDuplicatesCatchesWithinFileDuplicateOnSecondOccurrence, testMarkDuplicatesTreatsDifferentDayAsDistinct, testMarkDuplicatesTreatsDifferentAmountAsDistinct, testMarkDuplicatesTreatsDifferentAccountAsDistinct, testMarkDuplicatesLeavesStructurallyInvalidRowsUnmarked, testNetBalanceEffectExcludesDuplicateRows (TransactionAccountTests). No new files; generate_project.py regeneration byte-identical.
- QA: PASS. Real xcodebuild test on iPhone 17 Pro simulator: TEST SUCCEEDED 311/311 (303→311, all 8 new tests pass). Grep-verified isValid→willImport switch complete (remaining isValid sites genuinely structural or acctResults). Double-equality amount key sound (both sides abs() through same parseAmount pipeline). duplicateSkippedCount not reset in catch — harmless (never displayed on failure, reset at next performImport start; pre-existing pattern). Unverifiable statically: on-device rendering of duplicate badge/row treatment.
- Code Review: APPROVE, zero required fixes. Reviewer independently re-ran full suite: TEST SUCCEEDED. Optional follow-ups: (1) doc-comment that nil-account is its own dedupe bucket ("unassigned" matches only unassigned — defensible reading of "same account when set", but the phrase could be misread as ignore-account-when-none); (2) Double exact-equality in the dedupe key — backlog note that a future Decimal migration (T12+) must migrate the key too; (3) unfiltered full-table fetch at buildPreview is O(n) per preview — fine for v1/repo precedent, consider a date-bounded predicate if tens of thousands of transactions become real.
- Docs: IMPLEMENTATION_PLAN.md (T9 → done 2026-07-09; status board, next-up, Completed section, follow-ups all updated; T10 product decision now recorded; T19 remains only blocker), AGENT_LOOP_LOG.md, BUGS_AND_RISKS.md, CHANGELOG.md, FEATURE_BACKLOG.md.
- Follow-ups filed: (1) T9 nil-account dedupe bucket doc-comment clarity; (2) Decimal migration coupling of dedupe key; (3) O(n) buildPreview fetch optimization for large volumes.
- Commit: this loop's commit on branch `claude/finance-app-audit-roadmap-t8y2p4`.
- Next task: T10.
