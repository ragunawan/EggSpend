# EggSpend — Feature Backlog

Prioritized feature work lives in `docs/task-backlog.md` (T7–T24) and is tracked in `IMPLEMENTATION_PLAN.md`. This file holds the strategy summary and the unprioritized inbox for ideas discovered during the loop.

## Product direction (decided)
1. **"Cash Calm"** — Safe-to-Spend + Forecast + subscription intelligence as the hero loop (build first).
2. Subscription leakage detection (T16).
3. Plain-English "What changed this month?" (T18), on-device-AI-enrichable (T19).

Constraints (resolved 2026-07-08): Plaid = long-term only; AI = on-device only behind capability-gated toggle; accounts archive, never hard-delete by default; currency display-only.

## Unprioritized inbox
(The Documentation Agent appends here; the Planner promotes items into docs/task-backlog.md + IMPLEMENTATION_PLAN.md.)

- Rollover budgets; overall monthly budget across categories
- Budget suggestions from 3-month category averages
- Transaction splitting; receipt photo attachments
- Quick-add widget / App Intents shortcut
- Asset classes for net worth (property, vehicle); milestones
- Price-change detection on subscriptions (partially in T16)
- Safe-to-spend morning summary notification (opt-in); goal-milestone celebrations
- Anomaly flags (unusually large transaction for its category)
- Weekly digest notification
- Configurable budget week anchor (see B19)
- Product decision needed: how should a positive-balance liability account (e.g. an overpaid credit card) be treated in net worth — still counted as debt today, pre-existing behavior surfaced during T1 code review
