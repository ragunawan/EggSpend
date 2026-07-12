# EggSpend Redesign Plan — "Quiet Nest Dashboard"

**Direction:** Hybrid of A (Quiet Nest / Minimal Apple system) + B (Glanceable Home / Compact Dashboard) + the amount-first Quick Add sheet.
**Status:** Approved direction; planning document. No code changes until implementation is green-lit.
**Companions:** `docs/redesign/wireframes.html` — Direction B frames show the Home target; Direction A frames show the Transactions/Budget targets; the Direction E third frame shows the Quick Add sheet (re-skinned to this design system).

What each parent direction contributes:

- **From A (system):** native lists and collapsing large titles, one card treatment, toolbar consolidation, hierarchy from typography instead of boxes, retirement of ambient decoration (canopy animation, bird, nest hero, cascading reveals).
- **From B (structure):** Safe-to-Spend as the Home hero, Apple-Health-style 2×2 stat grid, one insight line replacing three nav-cards, everything critical above the fold, quick-add in thumb reach.
- **Quick Add:** amount-first sheet with merchant memory (reads the `CategoryRule` data the app already records) and remembered defaults.

---

## 1. Design tokens

New file `EggSpend/DesignSystem.swift` (tokens + modifiers), keeping `EggSpendTheme.swift` as the color source. Tokens are the *only* literals views may use.

### 1.1 Spacing scale (5 steps, nothing else)

| Token | Value | Use |
|---|---|---|
| `Space.xs` | 4 | icon–label gaps, badge padding |
| `Space.sm` | 8 | intra-row gaps, chip padding |
| `Space.md` | 12 | card internal padding, row leading/trailing |
| `Space.lg` | 16 | screen horizontal margin, card-to-card gap |
| `Space.xl` | 24 | section-to-section gap |

Replaces the 20+ ad-hoc values found in the audit. Any padding not on this scale is a review flag.

### 1.2 Corner radii (3, down from 7)

| Token | Value | Use |
|---|---|---|
| `Radius.control` | 8 | chips, small controls, keypad keys |
| `Radius.card` | 12 | cards, tiles, grouped-list look-alikes |
| `Radius.sheet` | 16 | sheets, hero card |

### 1.3 Elevation (1, down from ≥3)

- `.cardShadow` → `Color.nestBrown.opacity(0.08), radius: 6, y: 2`. Applied **only** by the `nestCard()` modifier. Rows, list content, and chips get no shadows.

### 1.4 Color semantics

Keep the existing palette (`nestBrown`, `nestCream`, `eggBlue`, `nestLeafGreen`, `yolk`, `twig`) and add semantic aliases so raw SwiftUI colors disappear from Views:

| Token | Maps to | Replaces |
|---|---|---|
| `Color.positive` | `nestLeafGreen` | raw `.green` (e.g. Transactions day header) |
| `Color.negative` | new adaptive red `C03A2B / FF6B5E` | raw `.red` (12+ sites) |
| `Color.warningTone` | `yolk` | raw `.orange` |
| `Color.info` | `eggBlue` | raw `.blue` (e.g. Budget edit swipe tint) |
| `Color.textSecondaryWarm` | darkened twig `7A5633 / B08F63` | `twig` used *as text* — current light-mode twig (#9E7348) fails 4.5:1 on cream |

Rules: no `.red/.green/.blue/.orange` literals in `Views/`; `twig` remains for decorative strokes/fills only. Background: `AnimatedCanopyBackground` (TimelineView animation) is replaced by `NestBackground` — a *static* cream→subtle-green tint, both modes, zero animation.

### 1.5 Motion

- One appearance transition: `.quickFade` (0.2s ease-out) — replaces the `appearRise` 0.05–0.4s cascade (delete the modifier).
- Money values keep `.contentTransition(.numericText())`.
- `BirdAnimationView`, `FloatingLeavesView`, nest-header scale-in: retired from the money surface (components may stay for Onboarding only).

---

## 2. Typography scale

Zero `.font(.system(size:))` in Views (13 today). Every style participates in Dynamic Type.

| Token | Definition | Use |
|---|---|---|
| `NestType.hero` | `.system(.largeTitle, design: .rounded, weight: .bold)` + `monospacedDigit` | Safe-to-Spend hero, detail-screen headline numbers |
| `NestType.stat` | `.system(.title3, design: .rounded, weight: .semibold)` + `monospacedDigit` | stat-tile numbers |
| `NestType.rowTitle` | `.body` (semibold where row is a link) | list row titles |
| `NestType.amount` | `.callout.weight(.semibold)` + `monospacedDigit` | trailing amounts |
| `NestType.meta` | `.caption` + `.foregroundStyle(.secondary)` | row captions (account · date · category) |
| `NestType.overline` | `.caption2.weight(.semibold)`, uppercase, tracking 0.5 | section labels ("SAFE TO SPEND TODAY") |

All right-aligned money uses `monospacedDigit()` so columns don't shimmy.

---

## 3. Icon guidelines

- SF Symbols only, one icon per fact. The duplicate category badge inside `TransactionRowView` (icon shown twice per row) is deleted.
- Row leading icons: plain symbol, `.body` size, category color, in a fixed `frame(width: 28)` for alignment — **no 40pt tinted circles** in dense lists. Tinted circles (28pt) survive only in the Home stat tiles.
- Toolbar icons: default size/weight (drop the `.title2` overrides); max two visible items per edge; everything else behind one labeled `Menu`.
- Status icons: only inside status pills (`checkmark.circle.fill`, `exclamationmark.triangle.fill`, `hand.raised.fill`), colored by semantic tokens.
- Tab bar: unchanged, except naming (see §5.4).

---

## 4. Reusable component library

New/changed in `Views/Components/` (each new file added to `project.pbxproj` **and** `generate_project.py`):

| Component | Kind | Notes |
|---|---|---|
| `DesignSystem.swift` | new | tokens from §1–2; `nestCard()` v2 (Radius.card, single shadow) |
| `NestBackground` | new | static tint replacing `AnimatedCanopyBackground` |
| `SectionHeader` | new | overline label + optional trailing action ("See all ›") |
| `StatTile` | new | overline label, stat number, trend caption; tappable |
| `LedgerRowView` | new | **unifies** `TransactionRowView`, `TransferRowView`, and upcoming-recurring rows: 28pt symbol, title, one meta line (category · account · date as context requires), trailing `AmountText`; optional dashed-border style for upcoming |
| `AmountText` | new | wraps `AmountLabel` with monospaced digits + semantic colors |
| `ThinProgressBar` | rework | `AnimatedProgressBar` with default height 4, token colors |
| `InsightRow` | new | 💡 one-liner (template or AI narrative) + destination |
| `CompactProgressRow` | new | name + "$X left" + `ThinProgressBar` (budgets & goals, Home + Budget tab) |
| `QuickAddSheet` | new | §6 |
| `CurrencyKeypadView` | new | decimal keypad, 44pt+ keys |
| `SuggestionChipsRow` | new | recent-merchant chips |
| `EmptyStateView` | new | standardizes the `ContentUnavailableView` + `@ScaledMetric` height + AX3 cap pattern (3 copies today) |

**Retired:** `HorizontalScrollProgressBar` + the 3 `PreferenceKey`s + 6 `@State` scroll vars in `DashboardView`; `NestHeaderView`/`BirdAnimationView`/`FloatingLeavesView` from Dashboard (kept for Onboarding); `EggProgressView` demoted to Budget *detail* screen (it's the brand moment there, not a list element); `AccountsView.swift` **deleted** (unreachable dead code, confirmed).

### SwiftUI component hierarchy (target)

```
ContentView (TabView)
├─ DashboardView (NavigationStack)
│  ├─ .toolbar: gear → SettingsView (sheet)
│  ├─ SafeSpendHeroCard        (nestCard: NestType.hero + status pill + buffer meta)
│  ├─ StatGrid                 (LazyVGrid 2×2 → StatTile: Net worth·Saved·In·Out)
│  ├─ InsightRow               (→ MonthlyReviewView; hosts AI narrative)
│  ├─ SectionHeader("Recent") + LedgerRowView ×5   (→ Transactions tab via tab switch, not push)
│  ├─ SectionHeader("Goals & budgets") + CompactProgressRow ×n  (→ detail)
│  ├─ SectionHeader("More") link rows (Forecast · Monthly review · Safe-to-spend detail)
│  └─ QuickAddButton (FAB) → QuickAddSheet
├─ TransactionsListView (NavigationStack)
│  ├─ .toolbar: Menu(Filter·Recurring·Categories·Import) + search
│  ├─ type filter chips row
│  ├─ List: compact day headers + LedgerRowView (swipe: delete/edit/categorize)
│  └─ QuickAddButton (FAB) → QuickAddSheet
├─ BudgetView: SummaryStrip(donut mini + line + ThinProgressBar) + CompactProgressRow list → BudgetDetailView (EggProgressView lives here)
├─ NetWorthView ("Nest Egg"): summary card + account List (unified row affordances)
└─ MetricsView: period picker + net-worth chart + cash-flow chart + stat row
```

---

## 5. Screen-by-screen redesign plan

### 5.1 Home — `DashboardView.swift` (major)

Per Direction B wireframe. Removals: nest header section (~190pt), `BirdAnimationView`, net-worth hero card (net worth becomes a `StatTile` linking to Nest Egg tab), Cash Flow Forecast + Monthly Review nav-cards, spending-delta card (its content and the AI-narrative `task` move into `InsightRow`), both horizontal tile scrollers. Additions: `SafeSpendHeroCard` first, `StatGrid`, compact goals/budgets rows, "More" link group, FAB. The AI-narrative state machinery (`narrativeSession`, task-id keying — the load-bearing comments) transfers to `InsightRow` unchanged. Perf note: `SafeSpendCalculator` result should be computed once per data change, not per body eval (cache in `@State` keyed on inputs, or accept as-is and measure — flag for implementation).

### 5.2 Transactions — `TransactionsListView.swift`, row components (major)

- Toolbar: 4 unlabeled icons → one `Menu` (Filter… · Recurring · Categories · Import CSV) + search; `+` stays but FAB is primary.
- Type filter chips (All / Expenses / Income / Transfers / Upcoming) cover the 90% filter case; full `TransactionFilterView` sheet remains via the menu. `hideTransfers` folds into the chips.
- Day headers: headline `Text` → compact small-caps "JUL 1 · +$4,200" (~18pt); remove per-group card backgrounds/shadows (`mergedRowBackground` deleted) in favor of plain rows + hairline separators.
- Rows → `LedgerRowView`: single icon (duplicate badge deleted), one meta line, monospaced amounts. Target: ≥9 rows/screenful (4 today).
- Swipe actions: keep delete; add Edit and Categorize (menu of top categories).
- Upcoming recurring rows: keep dashed-border affordance, compact style.

### 5.3 Budget — `BudgetView.swift` (major)

- Hero card → `SummaryStrip` (~60pt): 44pt donut (replaces badge+legend) + "$0 of $1,100 · July" + `ThinProgressBar` + "4 on track · 0 watch · 0 over" caption. Five encodings → two.
- Rows → `CompactProgressRow`: name + **"$X left"** (the decision number) + thin bar. Egg ring, % text, spent/limit pair, period column move to `BudgetDetailView`.
- Period filter chips → toolbar `Menu` ("All ▾").
- Status grouping stays as sort order + section headers (Over budget first); inactive section unchanged.
- Nested container-in-container (ScrollView material wrapper) removed — plain list on `NestBackground`.

### 5.4 Nest Egg — `NetWorthView.swift` (medium)

- **Naming unification:** tab "Nest Egg", screen title "Nest Egg", Home tile "Net worth" → pick **"Nest Egg"** for tab+screen, "Net worth" as the metric label inside. No more three-names-one-number.
- Delete the 180pt two-bar chart (encodes two numbers already shown as text). Replace with a compact 30-day trend sparkline reusing `MetricsView`'s timeline data (the chart users actually want here).
- Unify edit affordances: every account row taps to a small detail (balance, type, planner link for liabilities, edit button); remove the inline pencil-button asymmetry. Swipe: Edit / Archive on both sections.

### 5.5 Metrics — `MetricsView.swift` (light)

- Delete the "Period Summary" two-bar chart (duplicates the bucketed Income & Expenses chart); keep its Net + Savings-rate numbers as a stat row under the cash-flow chart.
- Collapse the heading stack ("Metrics" → "Timeline" → chart title): section header goes, chart titles stay.

### 5.6 Add/Edit — `AddTransactionView.swift` (medium) + Quick Add (§6)

- Full form survives for **editing** and as Quick Add's "More options" target (prefilled).
- Remove the **Budget** section: it only proxies category selection (budgets already match by category via `Budget.spent(from:)`); one decision fewer. *(Flagged decision — see §8.)*
- Default account = last used (`@AppStorage("lastUsedAccountID")`); category pre-filled from `CategoryRuleEngine.categoryFor(title:)` as the title is committed.

### 5.7 Settings & secondary screens (light)

- Add a "Manage" section to `SettingsView`: Categories · Recurring · Subscription audit — so none of these depend solely on the Transactions toolbar (Subscription Audit is 3 levels deep today).
- Secondary screens (Forecast, Monthly Review, Safe-to-Spend detail, Goals, Recurring, Category management, Import, Onboarding): token sweep only in this pass (spacing/type/radius/colors, `NestBackground`), no structural redesign.

---

## 6. Quick Add sheet — specification

**Entry:** FAB (bottom-trailing, 52pt, `yolk`) on Home and Transactions → sheet with detents `[.medium-ish (~440pt), .large]`. Toolbar `+` elsewhere presents the same sheet.

**Layout (top→bottom):** grabber · amount display (`NestType.hero`, live-updating) · income/expense toggle (compact segmented, defaults expense) · `SuggestionChipsRow` · defaults pill row · `CurrencyKeypadView` · "More options ▾".

**Behavior:**

1. **Amount-first:** custom keypad is always up — no focus tap, no keyboard-mode switch.
2. **Merchant chips:** up to 6 distinct recent transaction titles (last 90 days, ranked by frequency then recency; computed from the existing `@Query` — no new model). Tap fills title + category (via `CategoryRuleEngine.categoryFor`, falling back to that merchant's last category) + that merchant's last account.
3. **Defaults pills:** Category · Account · Date, pre-filled (rule engine / last-used / today), each a `Menu` to override. New-merchant titles entered via a small text field revealed by a "Title…" chip.
4. **Save (✓):** same side-effect chain as the full form — `AccountBalanceService.apply`, `CategoryRuleEngine.recordRule`, `BudgetAlertCoordinator.checkBudgets`. **Extract this chain into `Utilities/TransactionEntryService.swift`** so Quick Add and `AddTransactionView` share one save path (test target: existing + new XCTests against the service).
5. **More options:** dismiss into full `AddTransactionView` with state carried over (amount/type/title/category/account). Transfers live only in the full form.
6. **Target:** repeat merchant logged in ≤4 taps (FAB → chip → digits → ✓).

**Accessibility:** keypad keys ≥44pt with labels; amount display is a live region; chips get `.accessibilityHint("Fills title and category")`; sheet fully Dynamic-Type capable (keypad uses `@ScaledMetric` key height, AX cap consistent with existing empty-state pattern).

---

## 7. Implementation roadmap & migration strategy

No SwiftData model changes anywhere in this plan → **zero CloudKit schema risk**. New persistence is `@AppStorage` only. Every phase is independently shippable: build + full `EggSpendTests` on the iPhone 17 simulator must pass, `generate_project.py` stays in sync with `project.pbxproj`, new user-facing strings go into `Localizable.xcstrings`, and screenshots are regenerated per phase via `scripts/capture_screenshots.sh` for before/after comparison.

| Phase | Scope | Files (primary) | Size | Gate |
|---|---|---|---|---|
| **R0** | Tokens + component shells: `DesignSystem`, `NestBackground`, `SectionHeader`, `StatTile`, `AmountText`, `LedgerRowView`, `ThinProgressBar`, `CompactProgressRow`, `EmptyStateView` | new Components files, pbxproj, generate_project.py | S | builds; no screen adopts yet, zero visual change |
| **R1** | System sweep: adopt tokens everywhere (radii/spacing/type/colors/shadow), retire `appearRise` cascade + animated background + Dashboard decorations, naming unification ("Nest Egg"), contrast fix for twig text | all Views (mechanical), EggSpendTheme | M | `grep` gates: 0 `.system(size:` in Views, 0 raw `.red/.green/.blue/.orange`, radii ∈ {8,12,16} |
| **R2** | Home restructure per §5.1 (hero, grid, insight row, compact sections, FAB) | DashboardView + new components | M | everything critical above fold at default type size; AI-narrative behavior preserved (task-id keying tests) |
| **R3** | Transactions density per §5.2 (toolbar menu, chips, compact headers, LedgerRowView, swipes) | TransactionsListView, row components, TransactionFilterView | M | ≥9 rows/screenful in `--preview-data` screenshot |
| **R4** | Quick Add per §6 + `TransactionEntryService` extraction + last-account memory + rule read-back | new QuickAdd files, AddTransactionView, Utilities | M | ≤4 taps repeat-merchant; service unit tests cover apply/reverse/rule/alert chain |
| **R5** | Budget summary strip + rows; Nest Egg chart swap + affordance unification; Metrics de-dup | BudgetView, BudgetDetailView, NetWorthView, MetricsView | M | Budget first screen shows ≥4 budget rows + summary |
| **R6** | Cleanup & polish: delete `AccountsView.swift`, remove Budget picker from full form (§8), accessibility re-pass (VoiceOver walk, AX3, contrast), final screenshot regen, docs/CHANGELOG | misc | S | audit success-metrics table below all green |

**Risk containment:** R1 is the widest phase but mechanical; do it as one commit series per tab so any regression bisects to a screen. R2–R5 are additive/replacive per screen with the old components deleted only at the end of each phase. The editing path through `AddTransactionView` stays untouched until R4's service extraction proves out under tests.

### Success metrics (from the audit baseline)

| Metric | Today | Target |
|---|---|---|
| Transactions rows per screenful | 4 | ≥9 |
| Home: hero + 4 stats + 3 recent above fold | no | yes |
| Taps to log repeat merchant | ~10 | ≤4 |
| Hard-coded font sizes in Views | 13 | 0 |
| Corner radius values | 7 | 3 |
| Card/shadow treatments | ≥3 | 1 |
| Raw non-semantic colors in Views | ~20 sites | 0 |
| Names for the net-worth number | 3 | 1 (+1 metric label) |

---

## 8. Open decisions (defaults chosen; veto before the relevant phase)

1. **Remove the Budget picker from the full add form** (R6) — default **yes**: it only sets the category, and budgets match by category. Veto keeps it as-is.
2. **Nest illustration** — default: retired from Home, kept in Onboarding as the brand moment. Veto option: 24pt static mark in the Home header.
3. **FAB vs. toolbar-only add** — default: FAB on Home + Transactions, toolbar `+` elsewhere.
4. **"Nest Egg" naming** — default: tab + screen say "Nest Egg", the number inside is labeled "Net worth".
