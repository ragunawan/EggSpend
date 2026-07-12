# EggSpend UI Redesign — Implementation Specification

**Audience:** an AI engineer (GPT) with full repository access and zero prior project context.
**Objective:** implement the approved "Quiet Nest Dashboard" redesign (Minimal-Apple system + Compact Dashboard home + amount-first Quick Add sheet) while preserving all business logic and functionality.
**This document is the single source of truth.** Companion artifacts: `docs/redesign/REDESIGN_PLAN.md` (design rationale), `docs/redesign/wireframes.html` (visual targets — Direction B frames = Home; Direction A frames = Transactions/Budget; Direction E third frame = Quick Add sheet).

**Ground rules (repeated from repo conventions — violating these breaks the build or the data):**

1. Build/test destination: `xcodebuild -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'` (`build` / `test`; single class via `-only-testing:EggSpendTests/<Class>`).
2. Every Swift file added or deleted must be reflected in **both** `EggSpend.xcodeproj/project.pbxproj` **and** `generate_project.py`.
3. **No SwiftData `@Model` schema changes in this redesign.** The store syncs via CloudKit; the entire plan is achievable with view/service/`@AppStorage` changes only.
4. Money: `Transaction.amount` is stored **positive**; use `signedAmount` for arithmetic. Balances are **not** auto-updated — any create/edit/delete of an account-linked transaction must call `AccountBalanceService.apply/reverse` (transfers: `TransferBalanceService`).
5. Enums on persistent models are stored as `String` rawValues (`typeRaw`, etc.) with computed wrappers — CloudKit does not support Swift enums.
6. A `Budget` with `category == nil` matches **uncategorized** transactions, not all transactions.
7. New user-facing strings go into `EggSpend/Localizable.xcstrings`.
8. Tests use in-memory `ModelContainer` in `setUpWithError`/`tearDownWithError` — follow that pattern.
9. Commit only when a phase's verification checklist passes. One phase = one commit series; never mix phases in a commit.

---

## Section 1 — Executive Summary

**Current problems (measured, see Section 3):** first screenful is 30–45% useful content; the same facts are rendered 2–5 times (budget rows encode progress four ways; the net-worth number has three names and two hero cards); heavy card chrome + decoration (animated canopy, bird animation, 190pt nest illustration) crowd out data; 4 transactions visible per screenful; the most frequent action (logging a transaction) takes ~10 interactions through a 7-section form; no design system (7 corner radii, 13 hard-coded font sizes, 20+ padding values, raw colors bypassing the semantic palette).

**Design philosophy:** hierarchy from typography, not boxes; one encoding per fact; the daily-decision number (Safe to Spend) is the hero; native components and platform behavior wherever possible; decoration retired from the money surface (kept in Onboarding); every frequent action reachable with a thumb.

**Expected outcome:** Home scannable in <2s with hero + 4 stats + recent activity above the fold; Transactions showing ≥9 rows/screenful; repeat-merchant entry in ≤4 taps; a token-driven design system with zero hard-coded font sizes and 3 corner radii; all 29 existing test classes still green; zero CloudKit schema risk.

**Implementation strategy:** 7 sequential phases (R0–R6), each independently shippable. R0 builds tokens/components with no visual change; R1 is a mechanical system-wide sweep with grep-able gates; R2–R5 restructure screens one at a time; R6 cleans up. Business logic is never rewritten — views are re-skinned around the existing services, and the one logic extraction (`TransactionEntryService`) is a pure refactor guarded by new unit tests.

---

## Section 2 — Current Architecture

### App entry & state management

- `EggSpend/EggSpendApp.swift` (`@main EggSpendApp`): builds a **static** `(modelContainer, syncStatus)` pair — CloudKit-backed `ModelContainer` with automatic local-only fallback (`SyncStatus.localOnly` drives an icloud-slash toolbar icon on Home). On appear: `PersistenceController.seedDefaultCategoriesIfNeeded` (idempotent) and `processRecurringTransactions(_:context:)` (top-level function in `Models/RecurringTransaction.swift`; also re-run on scenePhase → `.active`). Holds `AppLockController` (`@State`, injected via `.environment`) implementing biometric app lock with `LockScreenView` overlay on scenePhase transitions.
- **There are no ViewModels.** Views hold `@Query` results and `@State`, and call **static** service/calculator functions with plain arrays. State flows: SwiftData `@Query` → view computed properties → static utilities. Settings-level flags use `@AppStorage` (e.g. `SettingsView.aiNarrativeStorageKey`, app-lock flag).
- `ContentView.swift`: `TabView` with 5 tabs (Home 0, Transactions 1, Budget 2, Nest Egg 3, Metrics 4); each tab root is its own `NavigationStack`. Launch args: `--preview-data`, `--tab <n>`.

### Models (`EggSpend/Models/`, 9 `@Model` classes — DO NOT MODIFY)

`Transaction`, `TransactionCategory`, `Account`, `Budget`, `RecurringTransaction`, `Transfer`, `SavingsGoal`, `BalanceSnapshot`, `CategoryRule`.

### Services & utilities (`EggSpend/Utilities/`, all enum/static style)

Balance: `AccountBalanceService`, `TransferBalanceService`, `BalanceSnapshotService`. Calculation: `SafeSpendCalculator`, `NetWorthCalculator`, `MonthlyReviewCalculator`, `SpendingDeltaCalculator`, `DebtPayoffCalculator`, `RecurringProjection`, `SubscriptionDetector`, `TransactionGrouping`, `TransactionFilter`. Entry/format: `AmountParser`, `CurrencyFormat`, `CategoryRuleEngine` (`recordRule`, **`categoryFor`** — read API exists but is currently only used by import, not the add form), `BudgetAlertCoordinator`, `NotificationScheduler`. Data: `CSVParser`, `DataExporter`, `DuplicateSweeper`. AI: `NarrativeGenerator` (+ `LiveNarrativeModelSession`; on-device narrative, gated by `@AppStorage` toggle). `Views/Forecast/ForecastEngine.swift` holds forecast math (note: lives in Views/).

### Views (`EggSpend/Views/`, 39 files, ~9,850 lines)

Tab roots: `Dashboard/DashboardView` (701 lines — largest), `Transactions/TransactionsListView`, `Budget/BudgetView`, `NetWorth/NetWorthView`, `Metrics/MetricsView`. Secondary: SafeSpend, Forecast (+ calendar), MonthlyReview, Recurring (+ Next30Days), SavingsGoals, Subscriptions, Categories, Import, Settings, Onboarding, Accounts (**dead — unreachable**), plus Add/Detail/Filter screens. Shared components: `TransactionRowView`, `TransferRowView`, `AmountLabel`, `CategoryBadgeView`, `EggProgressView`, `NestHeaderView`, `AnimatedCanopyBackground`, `BirdAnimationView`, `FloatingLeavesView`.

### Tests (`EggSpendTests/`, 29 classes)

Full unit coverage of utilities/calculators/models (see directory listing). **No XCUITest target exists**; UI verification is via `scripts/capture_screenshots.sh <udid> <outdir>` (builds, installs, screenshots the 5 tabs via `--tab`; cannot tap/type/scroll).

### Coupling to reduce before UI work

1. **Save-side-effect chain duplicated risk:** `AddTransactionView.saveTransaction()` owns the apply-balance → record-rule → check-budget-alerts chain inline. Quick Add would duplicate it → extract `TransactionEntryService` (WP-4.1) *before* building the sheet.
2. **Row rendering duplicated 3×:** `TransactionRowView` / `TransferRowView` / `UpcomingRecurringRowView` (private in `TransactionsListView`) share ~80% layout → unify as `LedgerRowView` (WP-0.4).
3. **Empty-state pattern copy-pasted 3×** (`MetricsView`, `SafeToSpendView`, near-variant in `DashboardView`) with load-bearing `@ScaledMetric` + AX3-cap comments → wrap once as `EmptyStateView` (WP-0.5).
4. **DashboardView is 701 lines** with scroll-progress `PreferenceKey` machinery (3 keys + 6 `@State`) that the redesign deletes outright.
5. `DashboardView` recomputes `SafeSpendCalculator.calculate` (O(all transactions)) on every body evaluation — restructure keeps the call but it must be computed once per dependency change (`WP-2.1`).

### Dependencies

None beyond Apple frameworks (SwiftUI, SwiftData, Charts, LocalAuthentication, UserNotifications, FoundationModels for narrative). **Do not add any package dependencies.**

---

## Section 3 — UX Audit (per screen)

Priority: **P1** = redesign target, **P2** = token sweep only, **P3** = untouched this cycle.

| Screen | Purpose | Problems / pain points | Priority |
|---|---|---|---|
| **DashboardView** (Home) | daily glance | Hero slot spent on decoration (nest art ~190pt + bird + animated canopy); net worth duplicated vs Nest Egg tab; Safe to Spend (the daily number) third; two nav-only cards with zero data; two horizontal tile scrollers hide content + custom scrollbar machinery; cascading 0.05–0.4s reveal animations on every visit; ~33% useful content above fold; `SafeSpendCalculator` re-runs per body eval | **P1** |
| **TransactionsListView** | ledger | 4 rows/screenful; day headers are headline-sized with one-transaction days costing 2 header lines; category icon rendered twice per row; 4 unlabeled toolbar icons (mystery meat, mixed sheet/push behavior); only-delete swipe; card chrome + shadows per group | **P1** |
| **BudgetView** | budget health | Hero card ≈45% of screen with 5 encodings of one fact (badge, number pair, bar, % text, donut+legend); rows encode progress 4 ways → ~110pt rows; persistent 4-chip filter row for 4 budgets; container-in-container nesting | **P1** |
| **NetWorthView** (Nest Egg) | accounts & net worth | 3 names for one number (tab/screen/Home card); 180pt chart encoding two numbers already printed above it; asymmetric edit affordances (asset tap=edit, liability tap=planner + inline pencil); no trend chart (it lives in Metrics) | **P1** |
| **MetricsView** | trends | Two charts of the same data (bucketed income/expense + totals income/expense); triple heading stack before content; otherwise healthiest screen | **P1 (light)** |
| **AddTransactionView** | data entry | ~10 interactions for one entry; no autofocus; `CategoryRuleEngine` rules recorded but never read back; account defaults to "None" every time (silently skips balance updates); Budget section only proxies category selection | **P1** |
| SafeToSpendView / CashFlowForecastView / MonthlyReviewView | detail screens | structurally fine; inconsistent tokens; reached only via Home cards | P2 |
| RecurringTransactionsView (+Next30Days), SubscriptionAuditView | recurring mgmt | buried 2–3 levels behind an unlabeled toolbar icon | P2 (reachability fixed in R3/R5) |
| SavingsGoalsView, CategoryManagementView, CSVImportView, SettingsView, Onboarding, detail/filter views | management | token inconsistencies only; Settings gains a "Manage" section | P2 |
| AccountsView | none | **dead code, unreachable** | delete (R6) |
| DebtPayoffPlannerView, CashFlowCalendarView, TransactionDetailView, TransferDetailView | niche detail | acceptable | P3 |

Cross-cutting accessibility: hard-coded 30–64pt numerals don't scale with Dynamic Type; `twig` (#9E7348) caption text on cream fails ~4.5:1; all primary actions top-anchored (poor thumb reach); a recent a11y pass (labels, `@ScaledMetric`, AX3 caps) must be **preserved** — do not remove existing `accessibilityLabel/Value/Hidden` modifiers when rewriting views.

Cross-cutting consistency (grep-verifiable): corner radii {2,8,10,14,16,18,20} → {8,12,16}; 13 `.system(size:)` uses → 0; ≥3 shadow styles → 1; raw `.red/.green/.blue/.orange` → semantic tokens.

---

## Section 4 — Proposed Information Architecture

- **Tabs (unchanged set/order):** Home · Transactions · Budget · **Nest Egg** · Metrics. Naming unified: tab and screen title both "Nest Egg"; the metric labeled "Net worth" inside content. Home's "See All" **switches to tab 1** instead of pushing a duplicate `TransactionsListView` into Home's stack (add a `selectedTab` binding passed from `ContentView`, or `@AppStorage`-free `@Binding`; simplest: move `selectedTab` into an `@Observable` router object owned by `ContentView` and injected via environment).
- **NavigationStacks:** one per tab (unchanged). Pushes for detail screens; sheets for create/edit forms and Settings (unchanged pattern).
- **Bottom sheet:** `QuickAddSheet`, presented with detents `[.height(≈460), .large]`, from the FAB.
- **FAB:** 52pt `yolk` circle, bottom-trailing with `Space.lg` margins, on **Home and Transactions only**; other tabs keep toolbar `+` (Budget→AddBudgetView, Nest Egg→AddAccountView).
- **Toolbar strategy:** max one icon per edge outside Home; Transactions consolidates Filter/Recurring/Categories/Import into a single labeled `Menu` (ellipsis icon). Home keeps gear (Settings sheet) + sync-status icon.
- **Search:** Transactions only, native `.searchable` (unchanged).
- **Filters:** type filter chips row under the Transactions search bar (All/Expenses/Income/Transfers/Upcoming — sets `filter.type`/`hideTransfers`); full `TransactionFilterView` sheet stays behind the Menu for ranges/amounts/accounts.
- **Settings organization:** existing Data/Security/AI sections + new **"Manage"** section: Categories · Recurring · Subscription audit (fixes 3-level burial; the Transactions Menu remains the fast path).
- **Quick actions / deep links:** out of scope this cycle (Section 15.7) — `--tab` launch arg is the only deep-link mechanism and is load-bearing for screenshots; do not break it.

---

## Section 5 — Component Inventory (design system)

All live in `EggSpend/Views/Components/` unless noted. Every component: `#Preview` with `PersistenceController.previewContainer()` where data-bound; Dynamic Type through tokens; dark mode via existing adaptive palette.

| Component | Purpose | Props | States | Animation | Accessibility | Replaces / reused by |
|---|---|---|---|---|---|---|
| `DesignSystem.swift` (tokens, no view) | Section 6 constants + `nestCard()` v2 + `NestType` font helpers | — | — | `.quickFade` helper | — | `EggSpendTheme` stays for colors |
| `NestBackground` | static cream→green tint | none | light/dark | **none** (replaces TimelineView animation) | `accessibilityHidden(true)` | `AnimatedCanopyBackground` (delete in R1) |
| `SectionHeader` | overline section label | `title`, `trailing: (label, action)?` | default | none | header trait | ad-hoc `Label(...).font(.headline)` headers everywhere |
| `AmountText` | money text | `amount`, `type/sign`, `style: hero/stat/row` | positive/negative/neutral | `.contentTransition(.numericText())` | value read as currency | wraps `AmountLabel`; used by every row/tile |
| `StatTile` | Home grid cell | `label`, `value: Double`, `trend: String?`, `trendPositive: Bool?`, `destination` | plain/tappable | none | one element: "\(label), \(value), \(trend)" | new (Home 2×2 grid) |
| `LedgerRowView` | unified list row | `LedgerRow` enum (already exists in TransactionsListView — **move to Components**), `showsMeta: Set<MetaField>` (category/account/date), `style: .plain/.upcoming` | normal / upcoming(dashed) | none | existing labels preserved | `TransactionRowView`, `TransferRowView`, `UpcomingRecurringRowView` (delete after adoption) |
| `ThinProgressBar` | single progress encoding | `progress`, `color`, `height=4` | determinate | existing spring on value | `accessibilityValue("\(pct)%")` on parent | `AnimatedProgressBar` (rename+retune, keep in BudgetView file or move) |
| `CompactProgressRow` | budget/goal row | `name`, `leftAmount`, `progress`, `statusColor`, `destination` | ok/warning/over | bar spring | one element: "name, $X left, pct used(, over budget)" — copy existing `progressAccessibilityValue` logic | BudgetView rows, Home budget/goal sections; `BudgetTileView`/`SavingsGoalTileView` deleted |
| `InsightRow` | one-line narrative → MonthlyReview | `text` | template/AI | none | button trait | Home's spending-delta + 2 nav cards; **hosts the existing AI-narrative `task` machinery verbatim** (session reuse + task-id keying comments are load-bearing) |
| `EmptyStateView` | standard empty state | `title`, `icon`, `description`, `action: (label, handler)?`, `context: .listRow/.stack` | — | existing `.symbolEffect(.pulse)` | inherited from `ContentUnavailableView` | 3 hand-rolled copies (keeps `@ScaledMetric` height + `...accessibility3` cap for `.listRow`; `minHeight` for `.stack` — preserve the in-code comments explaining why) |
| `QuickAddButton` (FAB) | thumb-reach add | `action` | normal/pressed | scale 0.96 on press | label "Add transaction", 52pt target | new |
| `QuickAddSheet` | amount-first entry | `initialKind: .expense` | amount-empty(✓ disabled)/valid/saving | none beyond numericText | Section 6 of REDESIGN_PLAN §6 | new; uses `TransactionEntryService` |
| `CurrencyKeypadView` | decimal keypad | `binding to amountText` | key pressed | key highlight 0.1s | ≥44pt keys, keyboard-key traits | new |
| `SuggestionChipsRow` | merchant memory | `suggestions: [MerchantSuggestion]`, `onPick` | empty(hidden)/populated | none | hint "Fills title and category" | new |
| Buttons | — | use native `.borderedProminent`/`.bordered` with `tint(.yolk/.nestBrown)`; no custom button component | | | | |
| Charts | keep SwiftUI `Charts` as in MetricsView; no new chart component; Nest Egg sparkline reuses MetricsView's timeline computation extracted to a small helper if needed | | | | | |
| Dialogs / loading / skeletons | native `confirmationDialog`/`alert` (unchanged); no loading/skeleton states needed — SwiftData is synchronous in-process | | | | | |

---

## Section 6 — Design Tokens (normative)

```
Spacing   Space.xs=4  sm=8  md=12  lg=16  xl=24        // the ONLY padding literals allowed in Views
Radius    Radius.control=8  card=12  sheet=16          // the ONLY radii allowed
Shadow    cardShadow = nestBrown 8%, radius 6, y 2     // applied ONLY inside nestCard()
Icons     row leading: .body symbol in frame(width:28); tile: 28pt tinted circle; toolbar: default size
Motion    quickFade = .easeOut(0.2)                     // sole appearance transition
          money: .contentTransition(.numericText())
          bars:  existing .spring(response:0.6, damping:0.8)
          DELETE: appearRise modifier, AnimatedCanopyBackground timeline, BirdAnimationView on Home
Grid      screen margin Space.lg; card gap Space.lg; section gap Space.xl; StatGrid = LazyVGrid(2 flexible, spacing Space.sm)
SafeArea  FAB bottom-trailing padding Space.lg above tab bar (safeAreaInset or ZStack overlay); lists use native insets
```

**Typography (`NestType`)** — hero: `.largeTitle` rounded bold + monospacedDigit · stat: `.title3` rounded semibold + monospacedDigit · rowTitle: `.body` · amount: `.callout` semibold + monospacedDigit · meta: `.caption` secondary · overline: `.caption2` semibold uppercase tracking 0.5. **Zero `.font(.system(size:))` in Views/ after R1.**

**Color** — palette unchanged in `EggSpendTheme.swift`; add: `positive=nestLeafGreen`, `negative=Color(lightHex:"C03A2B", darkHex:"FF6B5E")`, `warningTone=yolk`, `info=eggBlue`, `textSecondaryWarm=Color(lightHex:"7A5633", darkHex:"B08F63")` (contrast-fixed twig for text). Rules: no raw `.red/.green/.blue/.orange` in Views/; `twig` only for decorative strokes/fills. Dark mode needs no extra work beyond the two new adaptive pairs (verify with the QA checklist).

---

## Section 7 — Screen-by-Screen Migration

Format: current → target · files · effort · risks · rollback · DoD. Migration order = phase order (Section 9). Rollback unit is always "revert the phase's commits" — phases don't interleave files, so reverts are clean.

### 7.1 Home (`Views/Dashboard/DashboardView.swift`) — Phase R2, effort L
- **Current:** 701 lines; nest header, net-worth hero, safe-to-spend card, 3 chips, 2 nav cards, 2 horizontal tile scrollers + PreferenceKey scrollbar, recent list, delta card w/ AI narrative task.
- **Target (wireframe B):** compact header (nav title inline + gear + sync icon) · `SafeSpendHeroCard` · `StatGrid` (Net worth→NestEgg tab, Saved, Flowed in, Flowed out) · `InsightRow` · `SectionHeader("Recent")`+5×`LedgerRowView` (See all → tab switch) · compact Goals&Budgets `CompactProgressRow`s · `SectionHeader("More")` links (Forecast · Monthly review) · FAB.
- **Deleted:** nestHeaderSection, netWorthCard, monthlySnapshotRow (→ StatGrid), both nav cards, spendingDeltaCard (→InsightRow), both scroller sections, `HorizontalScrollProgressBar`, 3 PreferenceKeys, 6 scroll `@State`s, `BudgetTileView`, `SavingsGoalTileView`, `NestMetricCard`, `formattedTileCurrency`.
- **Preserved exactly:** AI-narrative state machine (`narrativeSession` lifetime reuse, `.task(id:)` keyed on toggle+sentences, cancel-safety) — move verbatim into `InsightRow` or keep in DashboardView passing text down; sync-status toolbar icon; sheet presentations.
- **Risks:** breaking the narrative task keying (there are tests: `NarrativeGeneratorTests`, `SpendingDeltaCalculatorTests` cover the inputs; the view wiring has none — manual QA); tab-switch router touching `ContentView`.
- **DoD:** screenshot at default type size shows hero+grid+insight+≥3 recent rows above tab bar; no PreferenceKey references remain; file <400 lines.

### 7.2 Transactions (`Views/Transactions/TransactionsListView.swift`, `Components/TransactionRowView.swift`, `TransferRowView.swift`) — Phase R3, effort L
- Toolbar 4 icons → `Menu`("Filter…", "Recurring", "Categories", "Import CSV") — **keep push vs sheet behavior per item as today**. Chips row drives `filter.type` + upcoming visibility + `hideTransfers`. Day headers → caption small-caps "JUL 1 · +$4,200" via existing `dailyNetTotal`. Delete `mergedRowBackground`/shadows → plain rows + hairline. Adopt `LedgerRowView`; delete duplicate `CategoryBadgeView` from rows (badge component itself stays — used by detail screens). Add swipe Edit (opens `AddTransactionView(editingTransaction:)`) and Categorize (menu of 5 most-used categories; sets `tx.category` directly — no balance impact). FAB.
- **Risks:** onDelete offset mapping after chips filtering (rows array is recomputed — keep the existing `deleteRows(_:at:)` indirection); `.searchable` + chips interplay.
- **DoD:** `--preview-data` screenshot shows ≥9 rows; delete/edit/categorize swipes verified; recurring processing `onAppear` untouched.

### 7.3 Budget (`Views/Budget/BudgetView.swift`, `BudgetDetailView.swift`) — Phase R5, effort M
- Hero → `SummaryStrip` (44pt donut + "$spent of $budgeted · Month" + ThinProgressBar + counts caption). Rows → `CompactProgressRow` ("$X left" leading decision number). Egg ring + spent/limit pair + period column move to `BudgetDetailView` (verify they're already there; add if missing). Period chips → toolbar Menu. Remove ScrollView material wrapper. Keep: swipe/context actions (pause/resume/edit/delete), inactive collapse, empty states.
- **DoD:** ≥4 budget rows + summary visible on first screen; all swipe actions work; `BudgetTests` green.

### 7.4 Nest Egg (`Views/NetWorth/NetWorthView.swift`) — Phase R5, effort M
- Title → "Nest Egg". Delete two-bar `chartSection`; add 30-day sparkline (reuse `NetWorthCalculator.at(date:...)` bucketing — extract the small timeline builder from `MetricsView` into `Utilities/NetWorthCalculator.swift` as `timeline(accounts:transactions:snapshots:days:)` so both screens share it; pure addition, unit-testable). Unify rows: tap → edit sheet for **all** accounts; liabilities get a "Payoff planner" link row inside the edit/detail context or a trailing swipe action; delete the inline pencil button.
- **Risks:** losing planner discoverability — mitigate with swipe action + link in detail. **DoD:** `NetWorthCalculationTests` + new timeline test green; both edit paths reachable.

### 7.5 Metrics (`Views/Metrics/MetricsView.swift`) — Phase R5, effort S
- Delete `incomeVsExpenseSection` chart, keep its Net/Savings-rate numbers as a stat row under the cash-flow chart; remove the "Timeline" section header. Everything else unchanged.

### 7.6 Add/Edit + Quick Add (`Views/Transactions/AddTransactionView.swift`, new QuickAdd files, new `Utilities/TransactionEntryService.swift`) — Phase R4, effort XL (split into WPs)
- Extract save chain (both new+edit transaction & transfer paths incl. `AccountBalanceService`, `CategoryRuleEngine.recordRule`, `BudgetAlertCoordinator.checkBudgets`) into `TransactionEntryService`; `AddTransactionView` becomes a thin caller. Build keypad → chips → sheet per REDESIGN_PLAN §6. `@AppStorage("lastUsedAccountID")` (store `Account.id.uuidString`; resolve defensively — account may be deleted/archived). Merchant suggestions: computed from transactions (last 90 days, ranked frequency then recency, max 6, distinct case-insensitive titles). Category pre-fill: `CategoryRuleEngine.categoryFor(title:)`, fallback = that merchant's most recent transaction's category. "More options" dismisses into full form with state carried.
- **Rollback:** FAB/sheet are additive; the full form remains the fallback path throughout.
- **DoD:** new `TransactionEntryServiceTests` cover apply/reverse/rule/alert for create+edit+transfer; suggestion ranking unit-tested; ≤4-tap repeat-merchant flow manually verified; `TransactionAccountTests`/`TransferTests` green.

### 7.7 Settings (`Views/Settings/SettingsView.swift`) — Phase R5, effort S
- Add "Manage" section: Categories · Recurring · Subscription audit (NavigationLinks; Settings is a sheet with its own stack — verify links push correctly inside it).

### 7.8 All P2 screens — Phase R1, effort M (mechanical)
- Token sweep only: replace radii/padding/fonts/colors per Section 6, `AnimatedCanopyBackground` → `NestBackground`, delete `appearRise` call sites. No structural change.

---

## Section 8 — Repository Refactoring

- **Keep the existing folder scheme** (`Views/<Feature>/`, `Utilities/`, `Models/`) — no module restructuring in this cycle (constraint: incremental).
- New: `Views/Components/DesignSystem.swift`, `NestBackground.swift`, `SectionHeader.swift`, `AmountText.swift`, `StatTile.swift`, `LedgerRowView.swift`, `CompactProgressRow.swift`, `EmptyStateView.swift`, `QuickAddButton.swift`; `Views/QuickAdd/QuickAddSheet.swift`, `CurrencyKeypadView.swift`, `SuggestionChipsRow.swift`, `MerchantSuggestion.swift`; `Utilities/TransactionEntryService.swift`.
- Move `LedgerRow` enum from `TransactionsListView.swift` → `Views/Components/LedgerRowView.swift`.
- **Delete** (end of owning phase, never before adoption compiles): `Views/Accounts/AccountsView.swift` (R6), `Components/AnimatedCanopyBackground.swift` + `FloatingLeavesView.swift` if unreferenced after R1 (`BirdAnimationView`/`NestHeaderView` stay if Onboarding uses them — check `OnboardingView` first; if unused there too, delete), `HorizontalScrollProgressBar` + PreferenceKeys (R2), `TransactionRowView.swift`/`TransferRowView.swift` (R3, after LedgerRowView adoption), `AddAccountView` inline pencil affordance (R5).
- **Naming conventions:** components `Nest`-prefixed only when brand-specific (`NestBackground`, `NestType`); rows end `Row`, tiles `Tile`; no `View` suffix on modifiers. Previews stay in-file (`#Preview` + `previewContainer()`), per repo convention.
- **ViewModels:** intentionally not introduced — the `@Query`+static-service pattern is the house style and testable; do not add a VM layer.
- Every add/delete: update `project.pbxproj` + `generate_project.py` in the same commit.

---

## Section 9 — Implementation Phases

Each phase: independently shippable, full test suite green, screenshots regenerated (`scripts/capture_screenshots.sh`), one commit series.

| Phase | Goal | Files | Commits (expected) | Testing | Verification checklist | Complexity |
|---|---|---|---|---|---|---|
| **R0** | Tokens + component shells; zero visual change | new Components files + project sync | 3–4 | build + full suite; new components compile w/ previews | app renders identically; `xcodebuild test` green; generate_project.py in sync | S |
| **R1** | Mechanical system sweep + decoration retirement + naming | all Views, EggSpendTheme | 5–8 (one per tab/area) | full suite; screenshot diff per tab | greps: 0 `.system(size:` in Views; 0 raw `.red\|.green\|.blue\|.orange` literals in Views (allow `Color.negative` etc.); radii ∈ {8,12,16}; no `appearRise`/`AnimatedCanopyBackground` refs; "Nest Egg" title on tab+screen | M |
| **R2** | Home restructure | DashboardView, ContentView (router), new Home components | 4–6 | full suite + manual narrative QA | DoD 7.1; `--tab 0` screenshot matches wireframe B structure; See-all switches tab | L |
| **R3** | Transactions density | TransactionsListView, LedgerRowView adoption, filter chips | 4–5 | full suite; `TransactionFilterTests`, `TransactionGroupingTests` | DoD 7.2; ≥9 rows in screenshot; menu items all reachable | L |
| **R4** | Quick Add + entry service | TransactionEntryService, QuickAdd/*, AddTransactionView | 5–7 | **new** TransactionEntryServiceTests + MerchantSuggestionTests; TransactionAccountTests, TransferTests, CategoryRuleEngineTests | DoD 7.6; balances correct after quick-add/edit/delete round-trip | XL |
| **R5** | Budget / Nest Egg / Metrics / Settings | BudgetView, NetWorthView, MetricsView, SettingsView | 4–6 | BudgetTests, NetWorthCalculationTests + new timeline test, MetricsCalculationTests | DoDs 7.3–7.5, 7.7 | M |
| **R6** | Cleanup, a11y re-pass, final screenshots, docs | dead files, AddTransactionView budget section, docs | 3–4 | full suite; manual VoiceOver/AX3 pass | Section 14 metrics table all green; final acceptance checklist (Section 15.6) | M |

Dependency: R0 → everything. R1 → R2/R3/R5 (they assume tokens adopted). R4 depends only on R0 (can run parallel to R2/R3 if needed, but sequential is preferred). R6 last.

---

## Section 10 — GPT Work Packages

Global rules for every WP: don't touch `Models/` (except none); update pbxproj+generate_project.py for file adds/deletes; new strings → xcstrings; run the full test suite before marking done; preserve existing `accessibility*` modifiers when rewriting a view; **files to avoid** unless listed: `EggSpendApp.swift`, `Models/*`, `Persistence/*`, all Utilities not named.

**R0 — foundations**
- **WP-0.1 (S)** Design tokens. *Objective:* create `DesignSystem.swift` (Space/Radius/NestType/quickFade + `nestCard()` v2 using Radius.card+single shadow) and add 5 semantic colors to `EggSpendTheme.swift`. *Accept:* compiles; nestCard change is the only visual delta (18→12 radius acceptable in this WP). *Edge:* keep old `nestCard` shadow values until R1? No — change now, it's within tolerance.
- **WP-0.2 (S)** `NestBackground`, `SectionHeader`, `AmountText`. *Accept:* previews render; AmountText matches AmountLabel output for income/expense (compare in preview); nothing adopts yet.
- **WP-0.3 (M)** `StatTile`, `ThinProgressBar` (retune `AnimatedProgressBar` default height→4, token colors; keep name as alias or rename with find-replace), `CompactProgressRow` (port `progressAccessibilityValue` logic from `BudgetRowView`). *Accept:* previews for ok/warning/over states.
- **WP-0.4 (M)** `LedgerRowView` + move `LedgerRow` enum to Components. *Background:* unify the 3 row layouts; single 28pt symbol (no circle), one meta line, `AmountText`. *Accept:* preview shows transaction/transfer/upcoming variants; old rows untouched (adoption is R3). *Edge:* transfer rows have from→to accounts — meta line "From → To".
- **WP-0.5 (S)** `EmptyStateView` with `.listRow` (ScaledMetric height 340 + AX3 cap) and `.stack` (minHeight 140) contexts; **copy the explanatory comments** from `MetricsView.swift:47-53` — they document non-obvious behavior. Adopt in MetricsView, SafeToSpendView, DashboardView recent-empty. *Accept:* visual parity at default + AX3 sizes.

**R1 — sweep** (one WP per area; all *Accept:* the R1 greps for that area pass + screenshot parity-or-better)
- **WP-1.1 (M)** Components + Dashboard token sweep (fonts/radii/spacing/colors only — no restructuring).
- **WP-1.2 (M)** Transactions + Budget sweep.
- **WP-1.3 (M)** NetWorth + Metrics + all P2 screens sweep; `AnimatedCanopyBackground`→`NestBackground` everywhere; delete `appearRise` call sites + modifier.
- **WP-1.4 (S)** Naming: Nest Egg title unification; Home toolbar title stays "EggSpend". Check `Localizable.xcstrings` for affected keys.
- **WP-1.5 (S)** Decoration retirement: remove `BirdAnimationView` + nest header from Dashboard only (full restructure comes in R2); check Onboarding usage of `NestHeaderView` before deleting files (delete only if globally unreferenced).

**R2 — Home**
- **WP-2.1 (M)** `SafeSpendHeroCard` (extract from current safeToSpendCard, NestType.hero, status pill) + compute `safeSpendResult` once via `@State` refreshed in `.onChange` of query counts / `.task(id:)` on a hash of inputs. *Edge:* result must still update when a transaction is added while on-screen.
- **WP-2.2 (S)** `StatGrid` with 4 StatTiles; Net-worth tile switches to tab 3 (requires WP-2.4 router).
- **WP-2.3 (M)** `InsightRow` hosting the AI narrative task machinery **moved verbatim** (session reuse, task-id string, cancellation guard, comments). *Accept:* toggle on/off behavior identical; template rows render when narrative nil.
- **WP-2.4 (M)** Tab router: `@Observable` `TabRouter` in ContentView environment; Home "See all" + Net-worth tile use it; delete the Home→TransactionsListView push. *Files:* ContentView, DashboardView. *Edge:* `--tab` launch arg still seeds initial tab.
- **WP-2.5 (M)** Assemble new Home body per 7.1; delete retired sections/components/PreferenceKeys; add FAB (presents existing AddTransactionView until R4 swaps in QuickAddSheet). *Accept:* DoD 7.1.

**R3 — Transactions**
- **WP-3.1 (S)** Toolbar Menu consolidation. *Accept:* all four destinations reachable, labeled, correct sheet/push behavior.
- **WP-3.2 (M)** Filter chips row wired to `TransactionFilter.type` + `hideTransfers` + upcoming toggle. *Edge:* chips and the filter sheet must not fight — chips reflect sheet state (`filter.type` single source).
- **WP-3.3 (M)** Compact day headers + delete merged card backgrounds/shadows/hairline overlays → plain list. *Edge:* preserve `.onDelete` behavior and section separators.
- **WP-3.4 (M)** Adopt `LedgerRowView` everywhere in the list; delete `TransactionRowView.swift`/`TransferRowView.swift`/private upcoming row after Dashboard (R2) already adopted LedgerRowView for recent rows — verify no remaining references before deleting.
- **WP-3.5 (S)** Swipe Edit + Categorize actions. *Edge:* Categorize must not touch amount/account (no balance side effects); Edit opens prefilled form.
- **WP-3.6 (S)** FAB on Transactions.

**R4 — Quick Add**
- **WP-4.1 (M)** `TransactionEntryService` extraction + `TransactionEntryServiceTests` (create/edit transaction incl. account change reversal, create/edit transfer, rule recording, alert coordinator invoked; in-memory container). *Accept:* AddTransactionView save paths call the service; behavior identical; suite green.
- **WP-4.2 (M)** `CurrencyKeypadView` (digits, decimal per locale separator display but store canonical, backspace; `AmountParser` for parsing; `@ScaledMetric` key height ≥44). *Tests:* none beyond AmountParser (exists).
- **WP-4.3 (M)** `MerchantSuggestion` builder (pure function over `[Transaction]`: distinct case-insensitive titles, non-adjustment expense+income, 90-day window, rank frequency desc then recency, cap 6) + unit tests, incl. tie-break and empty-history cases.
- **WP-4.4 (L)** `QuickAddSheet` assembly: layout per REDESIGN_PLAN §6; chip tap fills title/category (`CategoryRuleEngine.categoryFor` → fallback merchant's last category) / account; defaults pills (category/account/date menus); `lastUsedAccountID` AppStorage read/write (resolve stale IDs → fall back to nil + no crash); save via service; ✓ disabled until amount>0 and (title non-empty). *Edge cases:* archived/deleted last account; zero accounts (account pill hidden, saves with nil account); income toggle clears expense-only category if `appliesTo` mismatches (mirror full-form logic).
- **WP-4.5 (S)** "More options" handoff → full AddTransactionView prefilled (amount/type/title/category/account carried).
- **WP-4.6 (S)** Swap FABs (Home/Transactions) to present QuickAddSheet; toolbar `+` keeps full form. Full form also gains: title `.onSubmit` category pre-fill via `categoryFor`, and last-account default for new entries.

**R5 — remaining tabs**
- **WP-5.1 (M)** Budget SummaryStrip + CompactProgressRow adoption + chips→Menu; enrich `BudgetDetailView` with anything removed from rows (egg ring, spent/limit, period). *Accept:* DoD 7.3.
- **WP-5.2 (M)** Nest Egg: extract `NetWorthCalculator.timeline(...)` + test; sparkline section replaces bar chart; row affordance unification. *Accept:* DoD 7.4.
- **WP-5.3 (S)** Metrics de-dup per 7.5.
- **WP-5.4 (S)** Settings "Manage" section.

**R6 — cleanup**
- **WP-6.1 (S)** Delete `AccountsView.swift` + any now-unreferenced components (grep before each delete); pbxproj+generator sync.
- **WP-6.2 (S)** Remove Budget picker section from AddTransactionView (decision §8.1 of REDESIGN_PLAN — default approved); ensure `BudgetTests` unaffected (matching is category-based).
- **WP-6.3 (M)** Accessibility re-pass: VoiceOver walk of all 5 tabs + QuickAdd; AX3 layout check on Home/Transactions/Budget/QuickAdd; contrast spot-check `textSecondaryWarm`; 44pt targets (FAB, chips, keypad).
- **WP-6.4 (S)** Regenerate `screenshots/iphone-6.3` + `ipad-13` via script (do **not** regenerate `alternates-*` variants — their capture setting is undocumented); update CHANGELOG/docs; final metrics table (Section 14) filled in.

---

## Section 11 — Automated Testing Strategy

Framework is **XCTest only** (no XCUITest target exists; do not add one this cycle — UI verification is screenshot + manual). Mocking: none needed — services are pure/static over in-memory `ModelContainer`s.

| Area | Tests | Purpose / success criteria |
|---|---|---|
| Business logic (existing) | all 29 classes | must stay green after every WP; failure = regression, fix before proceeding |
| Entry pipeline (new) | `TransactionEntryServiceTests` | create/edit/delete transaction & transfer produce correct account balances (incl. account-change reversal), record rules, trigger `BudgetAlertCoordinator`; asserts equal behavior to pre-refactor by testing the same invariants `TransactionAccountTests` covers |
| Merchant memory (new) | `MerchantSuggestionTests` | ranking (frequency>recency), 90-day window, distinct-case-insensitive, cap 6, empty history → [] |
| Net-worth timeline (new) | extend `NetWorthCalculationTests` | `timeline()` bucket count/values for known fixture; parity with MetricsView's previous inline math |
| Persistence / CloudKit | existing `CloudKitSchemaTests` | guards the no-schema-change constraint; if it fails, a model was touched — revert |
| Import/export | existing `CSVParserTests`, `DataExporterTests` | untouched paths; run per phase |
| Authentication | existing `AppLockControllerTests` | untouched |
| Charts | logic-level only (`MetricsCalculationTests`); no snapshot tests | chart data arrays, not pixels |
| Navigation / UI / Dark mode / Dynamic Type / performance | **not unit-testable here** → screenshot script (`--tab 0..4`, light run; add a dark-mode run via `xcrun simctl ui <udid> appearance dark` before capture) + Section 12 manual checklist | screenshots visually reviewed per phase; row-count metric measured on the transactions capture |
| Offline | covered by design: local-fallback container init in `EggSpendApp` is untouched; `syncStatus == .localOnly` icon verified manually | |
| Regression harness per phase | `xcodebuild test` full suite + `python3 generate_project.py` idempotency check (regenerate → `git diff --stat` shows no pbxproj drift) | |

---

## Section 12 — Manual QA Checklist (run after R2, R4, and R6; abbreviated runs after other phases)

**Navigation:** all 5 tabs load; every Menu item on Transactions reaches its screen; Settings→Manage links push; Home See-all switches tabs; back behavior consistent; `--tab 0..4` launch args land correctly; Forecast→Calendar, Recurring→Next30/SubscriptionAudit still reachable.
**Layout:** default type size — Home above-fold contract (hero+grid+insight+3 recent); Transactions ≥9 rows; Budget summary+4 rows; no clipped text at AX1–AX3; iPad 13″ renders without overlap (screenshot).
**Gestures:** swipe delete/edit/categorize (transactions); pause/edit/delete (budgets); archive/unarchive/delete (accounts); FAB reachable one-handed; sheet detents drag correctly.
**Keyboard/entry:** QuickAdd keypad in/out of decimal edge (multiple separators rejected); full-form fields focus properly; amount parsing for locale separators (`AmountParser`).
**VoiceOver:** tab bar labels; hero reads value+status; StatTiles read label+value+trend as one element; LedgerRow reads title+meta+amount; keypad keys labeled; chips announce hint; QuickAdd ✓ announces disabled state.
**Dark mode:** all 5 tabs + QuickAdd + Settings; new `negative`/`textSecondaryWarm` pairs legible; NestBackground not muddy.
**Dynamic Type:** XS and AX3 on Home/Transactions/Budget/QuickAdd; empty states don't clip CTA (regression: B27).
**Animations:** money `numericText` transitions; no residual appearRise/canopy motion; Reduce Motion honored (bars/fades degrade gracefully).
**State/persistence:** add→kill→relaunch persists; balances correct after quick-add, edit (incl. account switch), delete, transfer round-trip; recurring generation on launch unchanged; app-lock triggers on background→foreground.
**Data volume:** `--preview-data` (normal); empty install (onboarding + all empty states); large synthetic set (500+ transactions — scroll smoothness, Home load).
**Error handling:** QuickAdd with zero accounts; stale `lastUsedAccountID`; transfer with same account blocked; CSV import of malformed file (existing behavior).
**Performance/battery/memory:** no timeline animations remain (was constant redraw); Home scroll 60fps by eye; memory stable scrolling 500-row list.
**Offline/sync:** launch with iCloud unavailable → local-only icon shows; app functions fully.
**CSV import/export:** one import + all three exports round-trip after R4 (entry service must not break import's balance handling — import path uses its own service calls; verify).
**Regression:** the full checklist in `screenshots/README.md` device matrix for final captures.

---

## Section 13 — Risk Analysis

| Risk | Severity | Mitigation / rollback point |
|---|---|---|
| Entry-service extraction changes balance math | **High** | WP-4.1 is refactor-only with invariant tests written against *current* behavior first; rollback = revert WP-4.1 commits (form keeps inline chain) |
| AI-narrative task keying broken in Home move | Medium | move code verbatim incl. comments; manual QA with toggle on/off; rollback = keep delta card until parity confirmed |
| onDelete index mismatch after chip filtering | Medium | delete via row identity (existing `deleteRows` indirection), add a filtered-delete case to manual QA |
| `LedgerRowView` unification loses a per-type detail (e.g. transfer from→to) | Medium | adoption WPs list per-type meta explicitly; screenshots compared per type |
| R1 sweep introduces subtle layout breaks across 30+ files | Medium | one commit per screen area; screenshot diff per tab; parity-or-better gate |
| Tab-router change breaks `--tab` launch arg (screenshot pipeline depends on it) | Medium | WP-2.4 acceptance explicitly tests `--tab`; capture script run in-phase |
| Stale `lastUsedAccountID` (deleted/archived account) | Low | defensive resolve → nil; unit test |
| Naming change breaks localized strings | Low | WP-1.4 audits xcstrings keys |
| Performance regression from Home recompute | Low | WP-2.1 memoizes safe-spend; big-dataset manual check |
| Testing gap: no automated UI tests | Accepted | screenshot script + Section 12; do not attempt to add XCUITest this cycle |
| Data migration risk | **None** | no schema changes; `CloudKitSchemaTests` enforces |

Rollback points: every phase boundary is a safe tag (`redesign-r0` … `redesign-r6`). Within R4, WP-4.1 is the only risky commit — everything after is additive UI.

---

## Section 14 — Success Metrics (fill in at R6)

| Metric | Baseline | Target | Measure |
|---|---|---|---|
| Taps to log repeat merchant | ~10 | ≤4 | manual count |
| Transactions rows/screenful (preview data, 6.3″) | 4 | ≥9 | screenshot |
| Home above-fold: hero+4 stats+insight+3 recent | no | yes | screenshot |
| Budget rows visible with summary | 2 | ≥4 | screenshot |
| `.system(size:` in Views/ | 13 | 0 | grep |
| Distinct corner radii | 7 | 3 | grep |
| Raw `.red/.green/.blue/.orange` in Views/ | ~20 | 0 | grep |
| Card/shadow treatments | ≥3 | 1 | code review |
| Names for net-worth number | 3 | 1 (+metric label) | review |
| DashboardView line count | 701 | <400 | wc -l |
| Row components for ledger entries | 3 | 1 | review |
| Scrolling to reach any Home datum | ~2.5 screens | ≤1.5 | screenshot |
| Existing test classes green | 29 | 29 (+3 new) | xcodebuild test |

---

## Section 15 — Deliverables for GPT

**15.1 Master roadmap:** R0 foundations → R1 sweep → R2 Home → R3 Transactions → R4 Quick Add → R5 Budget/NestEgg/Metrics/Settings → R6 cleanup. (Section 9 table is normative.)

**15.2 Ordered work packages:** WP-0.1→0.5, 1.1→1.5, 2.1→2.5, 3.1→3.6, 4.1→4.6, 5.1→5.4, 6.1→6.4 (Section 10).

**15.3 Dependency graph:**
```
WP-0.1 → all WPs
WP-0.2/0.3/0.4/0.5 → R1+ WPs that adopt them
R1 (1.1–1.5) → 2.x, 3.x, 5.x
WP-2.4 (router) → WP-2.2, WP-2.5
WP-2.5 → WP-3.4 final deletions (Dashboard must adopt LedgerRowView first)
WP-4.1 → WP-4.4 → WP-4.5/4.6;  WP-4.2, WP-4.3 → WP-4.4
WP-5.2 timeline extraction → independent
WP-6.x last; WP-6.1 requires all adoption WPs merged
```

**15.4 Recommended sequence:** strictly WP order above; R4 may start after R0 if parallelism is needed, but merge after R3.

**15.5 Per-phase validation:** full test suite green · `python3 generate_project.py` produces no pbxproj diff · phase grep-gates pass · 5-tab screenshot capture reviewed (light; dark at R2/R4/R6) · abbreviated Section 12 run · commit series with descriptive messages, tagged `redesign-rN`.

**15.6 Final acceptance (before release):** Section 14 table fully green · full Section 12 checklist on iPhone 17 sim (light+dark, default+AX3) · iPad 13″ screenshot review · empty-install and 500-transaction runs · CSV import/export round-trip · app-lock and local-only-sync behaviors verified · screenshots regenerated (excluding `alternates-*`) · CHANGELOG + README/CLAUDE.md notes updated (mention retired components).

**15.7 Explicit non-goals (do NOT implement):** widgets/live activities; Siri/App Intents/deep links; XCUITest target; ViewModel layer or architecture rewrite; any SwiftData schema change (new models, fields, or renames); third-party dependencies; icon/brand redesign; iPad-specific layouts beyond "renders correctly"; localization of new languages; the E-direction dark-gradient hero, D-direction cardless system, or C-direction density mode; user-configurable dashboards; haptics pass; onboarding redesign (it keeps the nest illustration).

**Documented assumptions (per constraints):** (1) `BudgetDetailView` already shows spent/limit detail — if not, WP-5.1 adds it; (2) `NestHeaderView`/`BirdAnimationView` may be referenced by Onboarding — WP-1.5 greps before deleting; (3) the Budget-picker removal (WP-6.2) was default-approved in REDESIGN_PLAN §8; if the owner vetoes, skip WP-6.2 only; (4) sheet detent ≈460pt is a starting value — tune so keypad+chips fit without scrolling at default type size.
