# Handoff prompt — EggSpend agent loop (paste into a fresh Fable 5 session)

Copy everything below the line into a new Claude Code session opened on the EggSpend repo, branch `claude/finance-app-audit-roadmap-t8y2p4`.

---

Resume the EggSpend controlled implementation loop exactly where the previous session stopped. Do not re-audit or re-plan the app — all context you need is committed to this repo. Read these before doing anything else, in this order:

1. `IMPLEMENTATION_PLAN.md` — status board T1–T24, dependencies, "Next up" pointer, follow-ups, blockers awaiting my decision.
2. `docs/task-backlog.md` — the full spec for every task (files, steps, acceptance criteria, manual tests, risk, effort).
3. `BUGS_AND_RISKS.md`, `AGENT_LOOP_LOG.md`, `FEATURE_BACKLOG.md` — live registers; append, never rewrite history.
4. `docs/audit-and-roadmap.md` — background audit + resolved product decisions (§11). Historical; do not edit its findings.
5. `CLAUDE.md` — repo conventions (CloudKit enum pattern, positive `Transaction.amount`, negative liability balances, manual `AccountBalanceService` calls, `generate_project.py` ↔ pbxproj sync).

State at handoff: **Phase 0 is complete** — T1–T6 and T11 are done and pushed (loops 1–7 in `AGENT_LOOP_LOG.md`). Next up is **T7 (archive accounts instead of delete)**, then remaining P1 in priority order: T8, T9*, T10*, T12, T13 — then P2 (T14–T19*), then P3 (T20–T24, T23*). Asterisked tasks require my decision before coding (details in IMPLEMENTATION_PLAN.md "Blockers awaiting user decision"); when you reach one, ask me with AskUserQuestion and, if I'm unavailable, skip to the next unblocked task and leave the blocked one pending.

## The loop (per task)

Use the subagents defined in `.claude/agents/` — they load by name in a fresh session: `planner` → `repo-analyst` → `implementer` → `qa` → `code-reviewer` → `docs-agent`. Protocol per `IMPLEMENTATION_PLAN.md`: a task advances only on QA pass AND review approval; on a QA/review rejection, send the required fixes back to the same implementer agent (SendMessage) and re-verify — the loop log shows four past examples of this cycle. You (the orchestrator) commit once per completed loop with a descriptive message, and push with `git push -u origin claude/finance-app-audit-roadmap-t8y2p4` after every commit. Never leave the container with uncommitted approved work.

Environment facts (verified last session, re-verify cheaply): no Swift toolchain in the container — QA is static analysis plus Python-oracle ports of pure functions; `xcodebuild test` runs only on CI/macOS (workflow exists at `.github/workflows/test.yml`, never yet executed on a runner). `python3 generate_project.py` regenerates the pbxproj — required whenever a Swift file is added/removed, and QA must confirm regeneration is byte-identical each loop.

## Context compaction

To keep this session healthy over many loops, compact the conversation at each phase boundary:

- Immediately after the LAST task of a priority group is committed and pushed (P1 = T7–T13 done, later P2 = T14–T19, then P3 = T20–T24), first make sure `docs-agent` has flushed everything durable into IMPLEMENTATION_PLAN.md / AGENT_LOOP_LOG.md / BUGS_AND_RISKS.md / CHANGELOG.md, then run `/compact` with instructions to preserve: the current "Next up" task ID, any open user-decision blockers, any un-relayed QA/review findings, and the fact that all loop state lives in the repo files (so nothing conversational is load-bearing).
- Never compact mid-loop (between a task's implementation and its commit) — finish the loop first.
- After compaction, re-read `IMPLEMENTATION_PLAN.md` before selecting the next task rather than trusting summarized memory.

## Standing rules (from me — treat as durable authorization)

- Priorities: correctness > data integrity > security/privacy > features > polish. Small, reviewable, single-task commits. No scope creep — reviewers must flag it.
- Resolved product decisions (do not re-ask): Plaid = long-term only, keep offline-first; AI = on-device only behind a capability-gated toggle, no external APIs ever; accounts archive instead of delete; currency = display-only from locale.
- Stop and ask me (AskUserQuestion) for: destructive migrations, the three flagged decision tasks (T9 dedupe strictness, T10 adjustment visibility, T19 min iOS target), anything that deletes or bulk-mutates user financial data (T23), credentials, or a build/test failure unrelated to the current task.
- Treat all financial data as sensitive; never add network calls; never log amounts beyond existing patterns.
- Also on my wishlist when convenient: open a PR from this branch so CI runs for the first time — flag the first real `xcodebuild test` results to me, and if CI reveals failures in already-committed loops, fix them as the immediate next task before continuing the backlog.

Begin now: confirm branch and clean git state, read the five files above, then run the loop starting with the Planner selecting T7. After each completed loop, post the standard report (task, files, QA/review verdicts, follow-ups, next task). Continue until the current priority group is complete, compact as instructed, and keep going until you hit a decision blocker or P3 is done.
