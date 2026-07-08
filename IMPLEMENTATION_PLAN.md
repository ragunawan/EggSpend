# EggSpend — Implementation Plan (living document)

Owned by the Planner Agent. Detailed specs live in `docs/task-backlog.md` (T1–T24); audit context in `docs/audit-and-roadmap.md`. This file tracks execution state only.

**Loop protocol:** Planner selects → Repo Analyst inspects → Implementer changes → QA verifies → Code Review approves → Docs update → commit. A task advances only on QA pass + review approval. Stop conditions: destructive migration, missing product decision, credentials required, risky financial-data mutation, or unrelated build/test failure.

**Environment constraint:** this container has no Swift toolchain. QA is static; `xcodebuild test` must run on CI/macOS (see T11) before merging to `main`.

## Status board

| ID | Task | Priority | Status | Depends on | Approval needed |
|----|------|----------|--------|------------|-----------------|
| T1 | Shared NetWorthCalculator + liability sign fix | P0-1 | in_progress | — | no |
| T2 | Restrict net-worth reconstruction to account-linked transactions | P0-2 | pending | T1 | no |
| T3 | CSV amount/type parsing fixes | P0-3 | pending | — | no |
| T4 | Recurring end-date + infinite-loop guards | P0-4 | pending | — | no |
| T5 | Locale-safe amount entry | P0-5 | pending | — | no |
| T6 | Surface save failures in critical paths | P0-6 | pending | — | no |
| T7 | Archive accounts instead of delete | P1-1 | pending | T1 | no (decision resolved: archive) |
| T8 | CSV import: account selection + balance application | P1-2 | pending | T2, T3 | no |
| T9 | CSV import duplicate detection | P1-3 | pending | T8 | **yes — dedupe strictness** |
| T10 | Balance edits as explicit adjustments | P1-4 | pending | — | **yes — ledger/metrics visibility** |
| T11 | CI: GitHub Actions test workflow | P1-5 | pending | — | no |
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

**Next up:** T1.

## Completed

(none yet)

## Discovered follow-ups / new tickets

(none yet)

## Blockers awaiting user decision

- T9: duplicate-match strictness (recommend exact same-day + amount + normalized title).
- T10: are balance-adjustment transactions visible in ledger / included in cash-flow stats? (Recommend visible in ledger, excluded from metrics.)
- T19: minimum iOS target acceptable if on-device model framework requires raising it.
