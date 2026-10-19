# Protocol: Dispatch

Turn-entry procedure for the **`delivery`** seat: the interpreter-first gate, the "about to ask" tripwire, and the hand-off into the pipeline. It is the first thing `delivery` reads on every turn.

This protocol is the single source of truth for the dispatch **procedure**; the seat's **enforcement** of it stays in `agents/delivery.md` (see "Source of truth").

> The steps below are the turn-entry gates, not pipeline stages. `Step 0 (Interpret)` and `Phase 2 (Reduce)` are [`prompt-pipeline.md`](./prompt-pipeline.md)'s labels; this protocol must not mint competing `Step N` / `Phase N` labels. See "Step naming" below.

## When to apply

Every turn, on **every prompt**, without exception. The gate is the entry point of the delivery turn, not an opt-in for complex work.

## Why this protocol exists

The costliest failure modes of the delivery seat are:

- engaging the human with clarifying questions — or reading files — before the `interpreter` subagent has normalized the prompt; and
- burning the turn deliberating about whether the prompt is "trivial enough" to skip the interpreter.

There is no classification step. The interpreter is cheap, a misrouted prompt is expensive, and the deliberation itself is wasted budget — that deliberation is the exact failure mode this protocol removes.

## Steps

1. **Interpreter first (hard gate).** The first agent invocation of every turn is the `interpreter` subagent, before any other tool — every prompt, no exceptions, no pre-classification. The enforcement wording (the FIRST-invocation rule and the forbidden-tool list) lives in `agents/delivery.md`; this protocol owns the procedure, not a second copy of the rule.
2. **Do not pre-classify.** The trivial/non-trivial verdict is an *output* of the interpreter's routing packet, never a precondition for invoking it. The rule and its failure mode are enforced in `agents/delivery.md` §"Dispatch & Prompt Pipeline".
3. **The "about to ask" tripwire.** About to ask the human a clarifying question? That urge means the interpreter was skipped — the enforcement wording is the tripwire bullet in `agents/delivery.md`.
4. **Continue the pipeline.** With the routing packet in hand, follow [`prompt-pipeline.md`](./prompt-pipeline.md), which owns the routing branch (trivial vs non-trivial) and the hand-off to `orchestrator`.

## Step naming

`Step 0 (Interpret)` and `Phase 2 (Reduce)` belong to [`prompt-pipeline.md`](./prompt-pipeline.md); the gates above are the turn-entry gates around them and must not mint competing `Step N` / `Phase N` labels for pipeline stages.

## Source of truth

This protocol owns the dispatch **procedure** (the steps and rationale above). It does not own:

- **Enforcement** — the non-negotiable seat rules live in `agents/delivery.md` §"Dispatch & Prompt Pipeline" (the runtime-loaded prompt): the FIRST-invocation rule, the **forbidden-tool list** (owned there, not here), the never-classify rule, and the tripwire. The procedure above is *defined* here and *enforced* there; the agent file does not restate this procedure.
- **Pipeline semantics** — Step 0 (Interpret), the routing packet, and Phase 2 (Reduce) are owned by [`prompt-pipeline.md`](./prompt-pipeline.md). This protocol points at it rather than restating the routing table, the packet fields, or the Phase 2 scope.

Where a rule legitimately appears in two files, the split is exactly the procedure/enforcement one above — do not restate the other file's copy.

## Cross-references

- [`prompt-pipeline.md`](./prompt-pipeline.md) — Step 0 (Interpret) and Phase 2 (Reduce).
- `agents/delivery.md` — Dispatch & Prompt Pipeline (enforcement), Delegation table, Agent-system changes require review.
- `agents/orchestrator.md` — the Phase 2 executor and the handoff contract.

## Notes

- There is no `workflows/` layer; do not reintroduce one. This protocol gates the turn; [`orchestrate.md`](./orchestrate.md) is the orchestrator's thinking cadence; `prompt-pipeline` interprets then reduces. Composed: dispatch runs first (gate), prompt-pipeline runs second (Step 0 → Phase 2), and orchestrate governs the seat that executes the reduction.
