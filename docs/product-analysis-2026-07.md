# EggSpend — Product, Design & Engineering Analysis (July 2026)

Prepared as a combined senior-product-designer / iOS-engineer / product-strategist review of the codebase at commit `9f93014`. This is analysis only — no code was modified.

Evidence tags used throughout:
- **[Confirmed]** — verified directly in code or in the repo's own bug register with a fixed/open status.
- **[Suspected]** — inferred from code reading but not runtime-verified (no Xcode toolchain in this container).
- **[Judgment]** — subjective design opinion.
- **[Hypothesis]** — product claim requiring user validation.

---

## 1. Executive summary

EggSpend is a mature, offline-first personal-finance tracker (Swift 6 / SwiftUI / SwiftData / optional CloudKit, iOS 26+) with ~15,000 lines of app code, ~516 XCTest cases across 32 files, and an unusually disciplined engineering process (agent loop with QA + code review, CI, living bug register). The 2026-07 audit cycle already fixed the most dangerous money-math bugs (liability sign errors, four divergent net-worth formulas, locale-broken amount parsing, hard-coded USD, CloudKit duplicate materialization). What remains is a different class of work:

1. **Trust surfaces are incomplete.** Sync status is silently swallowed (`SyncStatus` computed at launch in `EggSpendApp.swift:7-34` but never shown to the user — register item R2, open). Backup restore does not exist (export only, T13). There is no undo anywhere in the app.
2. **The manual-entry ceiling.** Every insight feature (Safe-to-Spend, Forecast, subscription detection, "What changed") is only as good as the ledger, and the ledger depends on manual entry or CSV import. The highest-leverage product work is reducing entry cost further (widgets/App Intents/share-sheet capture) and reconciliation (already spec'd as P0 in `TODO.md` but not built).
3. **Several known correctness gaps remain open** in the register: B21 (transfers across included/excluded accounts corrupt historical net worth), B22 (recurring transactions keep mutating archived accounts silently), B24 (Double-equality dedupe key), R7/R8 (balance-adjustment edge UX), R9 (currency override requires app restart).
4. **The app has no home-screen presence at all** — no widgets, App Intents, Shortcuts, Spotlight, or watch app. For a "glance at my money" product, this is the biggest missing platform surface. [Judgment]

Recommended next step (subject to your direction choice in §12): ship the trust triad — sync-status surfacing (R2), backup **restore**, and undo for destructive actions — then attack entry friction with a Quick Add widget + App Intent, then reconciliation.

---

## 2. Current product overview

**Purpose.** Private, manual-first money tracking with forward-looking guidance: transactions, budgets with alerts, recurring bills, savings goals, net worth ("Nest Egg"), cash-flow forecast, Safe-to-Spend, monthly review, subscription audit, on-device-AI spending narratives.

**Target user.** [Hypothesis] Privacy-conscious individuals who decline bank aggregation (Plaid is explicitly deferred in `FEATURE_BACKLOG.md` constraints), are willing to log spending manually or via bank CSV, and want calm, plain-English guidance rather than raw dashboards.

**Positioning.** The decided direction is **"Cash Calm"** (Safe-to-Spend + Forecast + subscription intelligence as the hero loop) — already shipped. The differentiator vs. Copilot/Monarch/YNAB is: no accounts required, no bank link, no server, on-device AI only.

**Architecture (verified).**
- 9 SwiftData `@Model` classes; schema declared once in `EggSpendApp.swift`; CloudKit `.automatic` with `try!` local fallback (`EggSpendApp.swift:20-33`).
- Domain logic in 24 `Utilities/` types plus `ForecastEngine` (oddly placed in `Views/Forecast/` — acknowledged in CLAUDE.md).
- Five-tab `TabView` (`ContentView.swift`): Home, Transactions, Budget, Nest Egg, Metrics; `TabRouter` (`@Observable`) supports `--tab` launch routing.
- Launch pipeline in `EggSpendApp.onAppear`: seed categories → seed preview → materialize recurring → `DuplicateSweeper.sweep` → balance snapshots; re-snapshot on every `.active` transition.
- Views `@Query` SwiftData and pass arrays into pure calculators — a clean, testable seam used consistently.

**Major strengths (specific, not generic).**
- The `AccountBalanceService` / `TransferBalanceService` / `SavingsGoalContributionService` / `TransactionEntryService` discipline gives one auditable mutation path per money operation, and balance edits are recorded as visible "Balance adjustment" ledger transactions (T10) — a genuinely rare trust feature.
- `NarrativeGenerator`'s two-directional figure validator (AI may rewrite tone, never numbers) is the right way to use on-device AI in finance.
- The bug register + changelog are the most honest self-documentation I've seen in an app this size; nearly all Critical/High items are closed with tests.

**Underdeveloped areas (preview).** Restore, undo, reconciliation, widgets/intents, iPad layout (screenshots exist but no size-class-adaptive layouts found in views [Suspected]), transaction search/saved filters depth, split transactions, attachments.

---

## 3. Existing feature inventory

| Area | Features | Key files |
|---|---|---|
| Ledger | Add/edit/delete transactions, Quick Add sheet with currency keypad + merchant suggestions, transfers (with savings-goal tagging), filtering, day grouping with localized headers, adjustment transactions | `Views/Transactions/*`, `Views/QuickAdd/*`, `TransactionEntryService`, `TransactionGrouping` |
| Accounts | Asset/liability accounts, archive-not-delete, balance-edit-as-adjustment, include-in-net-worth flag, debt payoff planner | `Views/Accounts/*`, `AccountBalanceService`, `DebtPayoffCalculator` |
| Budgets | Per-category + uncategorized budgets, periods, threshold alerts via notifications, detail with trajectory chart | `Views/Budget/*`, `BudgetAlertCoordinator`, `NotificationScheduler` |
| Recurring | Materialization of overdue occurrences, next-30-days view, subscription detection/audit with one-tap track | `Models/RecurringTransaction.swift`, `SubscriptionDetector`, `Views/Subscriptions/*` |
| Insight | Safe-to-Spend, 30/60/90-day forecast + calendar, Metrics (net-worth timeline, category donut, cash-flow), Monthly Review, "What changed this month?" card, AI narrative | `SafeSpendCalculator`, `ForecastEngine`, `Views/Metrics/*`, `MonthlyReviewCalculator`, `SpendingDeltaCalculator`, `NarrativeGenerator` |
| Data | CSV import (account link, balance apply, dedupe, auto-categorize with "Auto" badge), CSV/JSON export (schema v4), auto-categorization rules with management UI | `Views/Import/CSVImportView.swift`, `DataExporter`, `CategoryRuleEngine` |
| Platform/trust | CloudKit sync w/ local fallback + duplicate self-heal, Face ID/Touch ID app lock, onboarding (3 screens, skippable), appearance setting, privacy manifest, string catalog (373 strings) | `EggSpendApp.swift`, `AppLockController`, `Views/Onboarding/*`, `SettingsView` |

Notably absent: restore-from-backup, undo, reconciliation, widgets, App Intents/Siri, Spotlight, watch, iPad-optimized layouts, receipts/attachments, split transactions, search-as-you-type in the ledger (filter sheet only [Suspected — verify in `TransactionsListView`]).

---

## 4. Core user journeys

1. **Log a purchase** — Home → Quick Add sheet → keypad amount → title (merchant suggestions + learned category) → save. Efficient: 3–4 taps plus typing; `lastUsedAccountID` is remembered (`QuickAddSheet.swift:24`). This is the app's best flow. [Judgment]
2. **Monthly bank catch-up** — Export bank CSV elsewhere → CSV import → map columns → account/balance/dedupe/auto-category preview → import. Robust after T3/T8/T9/T17, but reachable only from deep in the app; discoverability is weak (see §5).
3. **"Can I afford this?"** — Home Safe-to-Spend card → SafeToSpendView breakdown. Good hero loop.
4. **Bill awareness** — Recurring list / Next-30-days / Forecast calendar. Three partially overlapping surfaces for the same mental model. [Judgment]
5. **Month-end reflection** — "What changed" card → Monthly Review; Metrics for trends.
6. **Net-worth check-in** — Nest Egg tab; tap account → filtered ledger; edit via swipe.

---

## 5. UX findings

**Confirmed problems**
- **U1. Sync state invisible (R2, open).** A user whose CloudKit init failed runs local-only forever with zero indication (`EggSpendApp.swift:26-33` prints to console). For a finance app whose pitch includes iCloud backup, this is the single worst trust gap. Affected: Settings (planned host), onboarding.
- **U2. Currency override requires restart (R9, open).** `CurrencyFormat.override` is a bare static var with no observation edge — Settings currency change won't re-render until relaunch.
- **U3. Recurring-processing failures are console-only (T6 follow-up, open).** Both `onAppear` callers ignore the Bool result; a user whose bills silently failed to materialize sees wrong balances with no signal.
- **U4. Silent bulk materialization.** After a restore/long absence, launch can create N historical transactions with no toast (register: T4 follow-up). Balances jump without explanation.
- **U5. Archived-account recurring items keep firing (B22, open)** and forecast surfaces are inconsistently filtered (B23) — a user archives a card, its autopay keeps mutating the hidden balance.
- **U6. AX5 empty-state clipping partially unverified (B27)** — fix landed but awaits human verification at AccessibilityXXXL.
- **U7. App-switcher snapshot shows content under app lock (B26, open)** — privacy feature has a documented hole.

**Suspected problems**
- **U8. Import/entry discoverability.** CSV import appears reachable only from Transactions toolbar/onboarding; subscription audit is buried behind the Recurring toolbar (itself not a tab). Verify with a nav-map pass.
- **U9. Duplicated "upcoming bills" mental model** across RecurringTransactionsView, RecurringNext30DaysView, and CashFlowCalendarView — likely confuses which is canonical.
- **U10. iPad is scaled-up iPhone.** No `horizontalSizeClass` adaptations found in a grep of Views [Suspected]; ipad-13 screenshots exist but layouts are single-column.
- **U11. No undo.** Deletes (transaction, transfer, account after 4 confirmations, category, rule) are permanent. Confirmation dialogs are prevention, not recovery.

**Judgments**
- **U12.** Five tabs plus a Settings sheet plus toolbar-buried features (subscriptions, import, monthly review, debt planner, safe-to-spend detail) means the IA has a "long tail" of screens with 2–3-deep discoverability. A "More/Insights" hub or Home cards as the canonical index would help.
- **U13.** `DashboardView` computes many summaries; on small phones the Home tab likely requires substantial scrolling to reach goals/budgets cards — good candidates for user-configurable card order (see F10).
- **U14.** Onboarding creates an account and offers import but never asks about the user's goal (budgeting vs. net worth vs. subscriptions), so the first-run Home is identical for everyone. [Hypothesis: goal-based onboarding improves week-1 retention.]

**Positives worth preserving.** Quick Add + merchant learning; empty states with CTAs (T22); archive-not-delete; adjustment-transaction auditability; localized headers; consistent drill-down (account → filtered ledger, matching Metrics category tap).

---

## 6. Visual design findings

Grounding: `EggSpendTheme.swift` (semantic palette with light/dark hex pairs, `.nestCard()`), `Views/Components/` (14 shared components: `StatTile`, `LedgerRowView`, `EggProgressView`, `ThinProgressBar`, `SectionHeader`, `EmptyStateView`, `NestBackground`, `AmountText`, etc.), plus `screenshots/` (noted as stale vs. current code).

- **[Confirmed] The design system is real and used.** Adaptive light/dark hex pairs via `Color(lightHex:darkHex:)`, semantic names (`.yolk`, `.nestBrown`, `.eggBlue`, `.nestLeafGreen`, `.twig`, `.nestCream`), one card treatment, one ledger row. This is above-average consistency for an indie app.
- **[Confirmed] Chart styling has been fragile.** Three separate Swift Charts rendering bugs were fixed in the last cycle (series merging without `foregroundStyle(by:)`, `Label` icon-only collapse in annotations, callout clipping), and **B29 remains open**: the Budget trajectory `AreaMark`s at `BudgetDetailView.swift:276-317` plausibly still merge. A chart style guide (always categorical encoding + explicit scale + `.fit(to: .chart)` annotations) should be codified in `DesignSystem.swift`.
- **[Judgment] The egg/nest identity is charming but must not carry data meaning alone.** `EggProgressView` and the yolk palette are distinctive; keep them, but ensure status is never color-only (over-budget red vs. green) — partially addressed by accessibility values, worth a deliberate pass for color-blind users (no `accessibilityDifferentiateWithoutColor` handling found [Suspected]).
- **[Judgment] Density is uneven.** Home is card-stacked and long; Metrics packs donut + timeline + cash-flow into one scroll; Budget detail crams 4+ stat tiles and a 120-point chart. A consistent "hero number → chart → details" template per screen would improve scanability.
- **[Confirmed] Dark mode and Dynamic Type were engineered, not assumed** (adaptive hex pairs; T24a AX audit; AX5 fix). Alternates screenshots captured under an undocumented accessibility setting are a small process smell (`screenshots/README.md`).
- **[Judgment] Apple-convention alignment is good** (NavigationStack per tab, sheets for creation, swipe actions, ContentUnavailableView) with one deviation: Settings as a sheet from Home's gear rather than a fifth-tab or profile affordance — fine, but it hides Export/Privacy/AI toggles behind a tab-specific toolbar.

**Recommended visual direction:** keep the identity; invest in (a) a codified chart style kit, (b) a screen template normalizing hierarchy, (c) a spacing/typography token pass in `DesignSystem.swift` so cards/tiles share one scale. No rebrand needed.

---

## 7. Technical findings

**Confirmed strengths.** Calculator pattern (pure functions over arrays) → 516 tests; `NotificationCenterProtocol` DI; in-memory test containers; CI (T11); string catalog; privacy manifest; no networking layer at all (nothing to audit — the app is genuinely offline).

**Confirmed issues**
- **T-1. `DashboardView.safeSpendRefreshKey` hand-rolled invalidation** (`DashboardView.swift:84-120`): hashes every transaction/account/budget/goal/recurring on every body evaluation to decide recompute — O(n) hashing per render over the full transaction table, and a fragile duplicate of SwiftData observation. Fix: compute `SafeSpendResult` in `.task(id:)` keyed on cheaper inputs, or accept recompute (the calculator is pure and probably cheaper than the hash) — measure first.
- **T-2. `@Query` all-transactions in hot views.** `DashboardView`, `QuickAddSheet`, `MetricsView` each subscribe to the entire `Transaction` table unfiltered. With multi-year histories every keystroke-adjacent update touches these. Mitigations: predicate-bounded queries (current month / last 60 days) for Home; `fetchLimit` for recents.
- **T-3. Double money math app-wide (B18, accepted-risk)** plus **B24**: the CSV dedupe key uses `Double` exact equality — a latent trap for the planned Decimal migration. If Decimal is ever adopted, it must be one coordinated task; the register already knows this.
- **T-4. `try!` container fallback** (`EggSpendApp.swift:28`): if the local store also fails to open (disk full, corrupt store), the app crashes at launch with no recovery path. A finance app should degrade to read-only/in-memory with an error screen instead.
- **T-5. Open register items with data impact:** B21 (historical net worth wrong across include-boundary transfers, bounded post-launch by snapshots but wrong for pre-snapshot dates), B22/B23 (archived-account recurring), B19 (weekly budget anchored to locale week), B17 (Int truncation of savings-rate percent), B29 (chart area marks).
- **T-6. `CurrencyFormat.override` is `nonisolated(unsafe) static var`** — both a Swift-6 concurrency smell and the cause of U2. Should become `@Observable` app-level environment.
- **T-7. Error surfacing is inconsistent**: CSV import shows errors (T6), but recurring materialization, seeding, and snapshot capture fail silently (`try?` at `EggSpendApp.swift:79`, `captureBalanceSnapshots`). A lightweight in-app diagnostics log (last N warnings, viewable in Settings) would close R1's residue.
- **T-8. View size.** `CSVImportView` (695 lines), `MetricsView` (689), `TransactionsListView` (636), `AddTransactionView` (571) are at the edge of maintainability; each mixes flow state, calculations, and layout. Not urgent, but extract step-views/calculators before adding features to them.
- **T-9. `ForecastEngine` lives in `Views/Forecast/`** — misplaced vs. the Utilities convention (documented, still worth moving during the next forecast task).
- **T-10. No UI test target** — all 516 tests are unit-level; flows like CSV import, onboarding, and app lock have zero automated end-to-end coverage. Environment currently can't run XCUITest (documented), so this is a known accepted gap, but it should be on the roadmap for when a Mac runner is available.

**Suspected issues**
- **T-11.** `QuickAddSheet` recomputes `suggestions` from the full transaction table per keystroke via `CSVParser.normalizedTitle` scans [Suspected — verify `MerchantSuggestion` complexity]; fine at 1k transactions, questionable at 50k.
- **T-12.** Launch does all data work synchronously in `onAppear` on the main actor (materialization + sweep + snapshots) — with a large backlog this could produce a visible hang at cold start.

**Security/privacy.** Solid posture: no network, on-device AI only, privacy manifest, app lock (with documented B26 snapshot gap), export clearly labeled sensitive. Gap: data at rest is not encrypted beyond OS file protection, and app lock explicitly doesn't encrypt (correctly documented in changelog). Consider enabling `NSFileProtectionComplete`-class protection for the store if not already the default. [Suspected — verify store file protection.]

---

## 8. Accessibility findings

- **[Confirmed]** Substantial recent investment: T24a added VoiceOver labels/values across charts, budget egg indicator, rows; button traits fixed on interactive rows; Dynamic Type through AX5 audited; 44pt targets rechecked post-redesign.
- **[Confirmed open]** B27 human verification pending at AX5; 7 accessibility-value strings are English-only (localization-readiness, not a regression); MetricsView donut lacks the hide+legend pattern BudgetDetailView uses (filed); `NestHeaderView` `.accessibilityHidden` placement is fragile; account menu accessibility value omits balance.
- **[Suspected]** No handling for Reduce Motion (chart/value animations added in Monthly Review polish) or Differentiate Without Color; VoiceOver reading order in dense Home card stack unaudited as a sequence (labels exist, order untested).

---

## 9. Performance & reliability findings

- **[Confirmed fixed]** O(n²) grouping (B15/T21); empty-chart states (B20).
- **[Confirmed risk]** T-1/T-2 above (Dashboard hashing + full-table queries) are the main scaling limits; ledger dedupe fetch at import preview is O(n) unbounded (T9 follow-up).
- **Reliability positives:** duplicate sweep self-heal with deterministic tie-break (T23, residual race documented as B28); import rollback symmetry (T8); snapshot idempotence (T14); infinite-loop guard on recurrence advance (B13).
- **Reliability gaps:** no restore path means CloudKit is the only real backup, and R2 means users can't tell if it's on — combined, these are the top reliability risk. `try!` fallback crash path (T-4). Notification delivery unverified after permission revocation [Suspected — check `NotificationScheduler` re-auth handling].

---

## 10. Missing capabilities (grouped)

**Core:** backup **restore**; account reconciliation (already P0-spec'd in `TODO.md`); budget rollover (P1-spec'd); split transactions; per-account detail screen with running balance.
**Workflow:** home-screen Quick Add widget; ledger search field; saved filters; bulk edit/categorize; receipt/photo attachment; template transactions.
**Insights:** anomaly flags; budget suggestions from 3-month averages; subscription price-change alerts (engine partially exists); year-in-review.
**Engagement (non-manipulative):** opt-in morning Safe-to-Spend notification; weekly digest; goal-milestone moments — all already in the backlog inbox, none built.
**Customization:** configurable Home card order; budget week anchor (B19); currency override UI (R9); notification preferences panel.
**Platform integrations (justified only):** Widgets/WidgetKit, App Intents + Siri + Spotlight donation, Control Center quick-add control, Lock-Screen widget, Apple Watch complication (Safe-to-Spend number), Share extension (import CSV from Files/Mail). **Not recommended:** HealthKit, Apple Pay, Sign in with Apple (no accounts), Contacts/Photos/Calendar (Calendar only if bill-due export is demanded).
**Reliability & trust:** restore; undo; sync-status UI; in-app diagnostics log; audit history view for adjustments (data already exists as adjustment transactions — a filtered view is nearly free).

---

## 11. Recommended new features (concepts)

Scoring key for §13: Impact/Effort/Confidence/Strategic 1–5; Priority = (Impact + Strategic + Confidence − Effort).

### F1. Sync & Backup Trust Center (R2 + restore)
- **Problem:** users cannot tell whether their financial data is backed up, and export has no re-import path — data loss on device loss is plausible today.
- **Solution:** Settings section showing sync state (`SyncStatus` already computed), last-snapshot date, and a Restore flow consuming the versioned JSON backup (schema v4 already round-trips in tests).
- **Flow:** Settings → Data → status banner; Restore → file picker → validation preview (counts per model, schema version) → confirm → atomic import into empty or merged store.
- **Affected:** `SettingsView`, `SyncStatus`, new `BackupRestoreService` + view; `DataExporter` (validation reuse).
- **Complexity:** Medium (restore-merge semantics are the hard part; v1 can require empty store). **Risk:** corrupting data on bad merge — mitigate with restore-to-empty-only v1 + pre-restore auto-export. **Priority: highest.** MVP: status banner + restore-into-empty. Future: selective merge, encrypted backup file.

### F2. Undo for destructive actions
- **Problem:** every delete is permanent; confirmation ≠ recovery (U11).
- **Solution:** post-delete "Undo" toast (8s) backed by an in-memory tombstone that re-inserts the model graph and re-applies balance services symmetrically — the service layer already has exact `reverse`/`apply` pairs, which makes this unusually cheap here.
- **Affected:** `TransactionEntryService` (add delete path), transfer/goal services, list views. **Complexity:** Medium. **Risk:** partial re-insert on relationship edges (category/account deleted meanwhile). MVP: transactions + transfers only. Future: accounts, categories, budgets.

### F3. Quick Add widget + App Intents ("LogExpenseIntent")
- **Problem:** entry cost is the product's existential constraint; today logging requires launching the app.
- **Solution:** interactive widget (small: Safe-to-Spend number + "+" button; medium: + recent) and an App Intent (amount, title, category) enabling Siri/Shortcuts/Spotlight/Action-button entry, routed through `TransactionEntryService`.
- **Affected:** new widget extension target (pbxproj + `generate_project.py` sync — nontrivial in this repo's generated-project setup), `TransactionEntryService` (must become extension-safe; shared app group container required since the store currently lives in the app sandbox).
- **Complexity:** High (app-group store migration is the risk). **Risk:** store migration bug = data loss; mitigate behind F1. MVP: read-only Safe-to-Spend widget (no store migration if snapshot is mirrored to app-group UserDefaults) + in-app intent. Future: interactive logging, watch complication, Control Center control.

### F4. Account reconciliation (from `TODO.md` P0 spec)
- **Problem:** manual ledgers drift from bank reality; users lose trust in every derived insight.
- **Solution & MVP:** per the existing spec — statement balance/date entry, computed difference, likely-cause surfacing, cleared flags. Balance-at-date math already exists (`NetWorthCalculator.at`, snapshots). **Complexity:** Medium-High. **Risk:** B21 makes pre-snapshot balance-at-date wrong across include-boundary transfers — fix B21 first or scope reconciliation to post-snapshot dates.

### F5. Budget rollover (from `TODO.md` P1 spec)
Per-budget opt-in; show base/rollover/effective in `BudgetDetailView`. **Complexity:** Medium. Decision needed: negative rollover debt. MVP: positive-only.

### F6. Ledger search + saved filters
- **Problem:** `TransactionFilterView` is a modal form; finding "that Costco charge" is slow.
- **Solution:** `.searchable` on `TransactionsListView` matching title/category/amount, plus persisting named filters. **Complexity:** Low. **Priority: quick win.**

### F7. Split transactions
- **Problem:** one receipt, multiple categories — currently forces miscategorization, which poisons budgets, deltas, and auto-categorization learning.
- **Solution:** child line-items on `Transaction` (new model or self-relation; CloudKit-safe pattern per CLAUDE.md), splits shown indented in ledger; budgets/metrics consume leaf lines. **Complexity:** High (touches every summation site — the T10 exclusion audit lists 12+). **Risk:** high regression surface; demands the calculator test suite be extended first. Strategic, not urgent.

### F8. Subscription price-change alerts
- **Problem:** `SubscriptionDetector` already computes price changes but only shows them when the user visits the buried audit screen.
- **Solution:** on launch materialization, diff latest occurrence amount vs. median for tracked recurring items; local notification + Home card row. **Complexity:** Low-Medium (engine exists). MVP: in-app badge only, no notification.

### F9. Morning Safe-to-Spend notification (opt-in)
Backlogged already. Scheduled local notification with today's number; requires computing SafeSpend in a background task or caching last-foreground value (honest label "as of last open"). **Complexity:** Low with the cached approach. [Hypothesis: this is the strongest ethical retention lever — validate opt-in rate.]

### F10. Configurable Home
Reorderable/hideable Home cards (persisted order in `@AppStorage`). **Complexity:** Low-Medium. Addresses U13 and serves both power and simple personas without forking the design.

### F11. Adjustment audit view
Filtered ledger view of `isAdjustment` transactions per account ("Balance history & corrections"). Data already exists; **Complexity: Low**; strong trust signal.

### F12. iPad two-column layout
`NavigationSplitView` on regular width for Transactions and Nest Egg. **Complexity:** Medium. Only worth it if iPad usage is nonzero — instrument first. [Hypothesis]

---

## 12. Three design directions (no selection made)

### Direction A — Refined current experience
- **Principles:** trust before delight; one canonical surface per mental model; finish what's open.
- **Navigation:** unchanged five tabs; consolidate the recurring/next-30/forecast-calendar trio into one "Upcoming" surface; promote Subscriptions out of the toolbar.
- **Home:** current card stack, tightened to a "hero (Safe-to-Spend) → what changed → shortcuts" template.
- **Visual:** current identity; codify chart kit + spacing tokens (§6).
- **Density:** unchanged (medium). **Interactions:** unchanged.
- **Ideal user:** current users. **Advantages:** lowest risk, compounding trust, mostly closes the open register. **Risks:** no new-user acquisition story. **Scope:** ~4–6 loop-weeks (R2, restore, undo, B21/B22, search, chart kit, IA consolidation).

### Direction B — Information-dense power-user experience
- **Principles:** every number one tap away; configurability over curation; keyboard-of-the-thumb speed.
- **Navigation:** tabs become Ledger, Dashboard (configurable grid of `StatTile`s/mini-charts), Planning (budgets+recurring+forecast merged), Accounts, More. Persistent quick-add FAB.
- **Home:** user-composed dashboard (F10 taken to its conclusion): draggable tiles for net worth, safe-to-spend, any budget, any account, cash-flow sparkline.
- **Visual:** tighter type ramp, denser rows (LedgerRowView compact variant exists), more numerals, restrained egg motif.
- **Density:** high. **Interactions:** search-first ledger, saved filters, bulk edit, comparison toggles (this month vs. last) everywhere.
- **Ideal user:** spreadsheet refugees, FIRE trackers. **Advantages:** genuine differentiation vs. simplified competitors; leverages the app's unusually deep calculator layer. **Risks:** intimidates the manual-entry casual user; config UI is expensive; conflicts with the decided "Cash Calm" positioning. **Scope:** ~10–14 loop-weeks.

### Direction C — Guided and approachable experience
- **Principles:** one number, one next action; progressive disclosure; the app talks (narrative-first, leveraging `NarrativeGenerator`/`SpendingDeltaCalculator` — an asset competitors lack on-device).
- **Navigation:** three tabs — Today (Safe-to-Spend hero + guided actions + narrative), Money (ledger + accounts merged), Plan (budgets/goals/recurring as a checklist-style coach). Metrics demoted to drill-downs.
- **Home:** full-screen "Today" with the safe-to-spend number, a one-line AI narrative, and at most two suggested actions ("2 bills due this week", "Groceries pacing 20% high").
- **Visual:** bigger type, more whitespace, more egg/nest personality, celebratory goal moments.
- **Density:** low. **Interactions:** guided flows, goal-based onboarding (U14), inline explanations ("why this number").
- **Ideal user:** finance-anxious beginners; strongest fit with the decided "Cash Calm" positioning. **Advantages:** clearest brand story; narrative engine becomes the hero. **Risks:** hiding data frustrates existing users; IA migration cost; AI features gated to Apple-Intelligence devices creates a two-tier experience. **Scope:** ~8–12 loop-weeks.

**Tradeoff summary:** A maximizes trust per unit effort and unblocks either B or C later; B contradicts the previously decided positioning but exploits the codebase's depth; C amplifies the decided positioning but has the largest migration risk for current users.

---

## 13. Prioritized roadmap (scored)

### Immediate fixes
| Item | Impact | Effort | Conf | Strat | Priority |
|---|---|---|---|---|---|
| R2 sync-status surfacing (F1 part 1) | 5 | 1 | 5 | 4 | 13 |
| B22/B23 archived-account recurring | 4 | 2 | 4 | 3 | 9 |
| R9 currency override observation wiring | 3 | 2 | 5 | 2 | 8 |
| B29 verify/fix trajectory AreaMarks (needs simulator) | 2 | 1 | 3 | 2 | 6 |
| U3/U4 surface materialization failures & bulk toasts | 3 | 2 | 4 | 3 | 8 |
| B27 human AX5 verification | 2 | 1 | 4 | 2 | 7 |
| T-4 replace `try!` fallback with degraded mode | 3 | 2 | 4 | 3 | 8 |

### High-impact improvements
| Item | Impact | Effort | Conf | Strat | Priority |
|---|---|---|---|---|---|
| F1 backup **restore** (into-empty v1) | 5 | 3 | 4 | 5 | 11 |
| F2 undo (transactions/transfers) | 4 | 3 | 4 | 4 | 9 |
| F6 ledger search + saved filters | 4 | 2 | 5 | 3 | 10 |
| F8 subscription price-change surfacing | 3 | 2 | 4 | 4 | 9 |
| F11 adjustment audit view | 3 | 1 | 5 | 3 | 10 |
| B21 fix (transfer boundary in `NetWorthCalculator.at`) | 3 | 3 | 3 | 4 | 7 |
| T-1/T-2 Dashboard query/hashing perf | 3 | 2 | 3 | 2 | 6 |

### Strategic features
| Item | Impact | Effort | Conf | Strat | Priority |
|---|---|---|---|---|---|
| F3 widget + App Intents (staged) | 5 | 4 | 4 | 5 | 10 |
| F4 reconciliation | 5 | 4 | 4 | 5 | 10 |
| F5 budget rollover | 4 | 3 | 4 | 3 | 8 |
| F7 split transactions | 4 | 5 | 3 | 4 | 6 |
| F12 iPad split view | 2 | 3 | 3 | 2 | 4 |

### Experiments
| Item | Impact | Effort | Conf | Strat | Priority |
|---|---|---|---|---|---|
| F9 morning notification (opt-in-rate experiment) | 4 | 2 | 2 | 4 | 8 |
| F10 configurable Home (prototype) | 3 | 3 | 3 | 3 | 6 |
| U14 goal-based onboarding variant | 3 | 2 | 2 | 3 | 6 |
| Direction C "Today" tab prototype | 4 | 4 | 2 | 4 | 6 |

## 14. Quick wins (≤1 loop each)
R2 banner; F11 adjustment view; F6 `.searchable`; U3/U4 toasts; R9 wiring; B27 verification; chart-kit codification in `DesignSystem.swift`; move `ForecastEngine` to Utilities; delete stale screenshots note by re-capturing (needs Mac).

## 15. Medium-term (1–2 months)
F1 restore; F2 undo; F8; B21/B22; F5 rollover; T-1/T-2 perf; T-8 view decomposition (do opportunistically inside feature tasks); UI test target once a Mac runner exists.

## 16. Long-term opportunities
F3 full widget/intents/watch surface (after app-group store migration); F4 reconciliation as the trust capstone; F7 splits; Decimal migration (coordinate B18+B24 as one task); localization (catalog groundwork done; sentence templates + accessibility values deferred items are the remaining blockers); Direction B or C evolution per your choice.

## 17. Open questions & assumptions
1. **Usage reality:** no analytics exist (by design). All retention/engagement claims here are hypotheses — decide whether privacy-preserving, on-device-only usage counters are acceptable to inform prioritization.
2. **Product decisions the register is already waiting on:** archived-account recurring behavior (B22); positive-balance liability treatment in net worth; negative budget rollover; liability wording in CSV net-effect copy.
3. **Assumption:** CloudKit remains the only sync; no server/Plaid in the planning horizon (per decided constraints).
4. **Assumption:** iPad is secondary; F12 gated on evidence.
5. **Unverified:** everything tagged [Suspected] — notably store file protection class, Reduce Motion behavior, merchant-suggestion complexity, iPad layout behavior, and B29's visual rendering (no simulator in this container).

## 18. Recommended next step
Review this report and pick: (a) a design direction from §12 (my lean: **Direction A now, C as the v2 north star** — A closes the trust gaps that any direction depends on, and C matches the decided positioning), and (b) approve the first work package: **R2 sync banner → F1 restore-into-empty → F2 undo → F6 search**, which is one coherent "trust & recovery" release with no product-decision blockers. I'll then promote those into `docs/task-backlog.md` / `IMPLEMENTATION_PLAN.md` and begin implementation on your go-ahead.
