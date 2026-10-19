# Protocol: Orchestration

Pre-action thinking process for the **`orchestrator`** seat (and any coordinating seat). Apply it before you act on a handoff: **Protocol Discovery → Context Refresh → Proposal → Implementation → Verification → Documentation**.

This protocol is the single source of truth for the seat's thinking and coordination discipline.

> The stages below are **named, not Phase-numbered**. `Phase 2 (Reduce)` is [`prompt-pipeline.md`](./prompt-pipeline.md)'s label and is executed as stage 3 here; this protocol must not mint competing `Phase N` labels. See "Stage naming" below.

## When to apply

- Every non-trivial handoff routed to `orchestrator` — run the six stages before releasing any subagent.
- Any coordinating seat that must reason before delegating, as a mental checklist; the orchestrator remains the primary consumer.
- A mechanical single-file change may skip the stages whose output would be empty. The stages are a thinking discipline, not a paperwork requirement.

## Thinking rules

1. **Analyze before acting.** Read the target project's `docs/project.md` (entry point) and the relevant `docs/context/*.md` files (architecture, project rules) before writing or delegating. If the project has no `docs/` tree, treat those paths as absent and proceed from the repo itself — never create a global `docs/`.
2. **Architecture awareness.** Consult `docs/context/architecture.md` **when the project defines it**, for layering, dependency flow, and module boundaries. When it does not exist, infer the layering from imports and directory shape and record the inference as such — never invent a document.
3. **Consult the rules.** Check `docs/context/project-rules.md` **when present**, so new code follows the project's lints and security conventions.
4. **Permission system.** For auth/permission changes, read the project's permission doc under `docs/context/` (per the Slices table in `docs/project.md`).
5. **Language rule.** New documentation and comments follow the project's `doc_language` when `docs/project.md` declares one; **ENGLISH** always for agent-system files.
6. **`do-not-run-tests-from-root` guard.** Run the canonical test/typecheck/lint commands from the affected package directory, never from the repo root. Canonical commands come from `docs/project.md` (Common Commands).

## Stages

These are the orchestrator's own thinking stages. `prompt-pipeline` Step 0 (Interpret) runs upstream in `delivery`, before this seat is invoked; `prompt-pipeline` Phase 2 (Reduce) is executed as **stage 3** below. Run them in order — stage 3 is only meaningful after stages 1–2, and skipping them is the failure mode this protocol removes.

1. **Protocol Discovery** — list `protocols/` and identify the reusable conventions relevant to the task. For the permission system, go straight to the project's permission doc under `docs/context/` (thinking rule 4).
2. **Context Refresh** — read the identified protocol(s) and the relevant `docs/context/*.md` files (thinking rule 1).
3. **Proposal** — produce the scope defined by `prompt-pipeline` Phase 2 (Reduce). **This *is* Phase 2**, and the orchestrator is its sole executor; the fields and rules live in that protocol — read them there rather than re-deriving them. The human-facing proposal is delivered through `delivery`, never directly.
4. **Implementation** — write code following the project's standards, through the appropriate subagents.
5. **Verification** — run the canonical commands from `docs/project.md` for the affected package directory (the `do-not-run-tests-from-root` guard, thinking rule 6).
6. **Documentation** — update the relevant docs in the project's `doc_language` (thinking rule 5; English for agent-system files).

## Stage naming

[`prompt-pipeline.md`](./prompt-pipeline.md) owns `Step 0 (Interpret)` and `Phase 2 (Reduce)` for different concepts, so this protocol uses **named stages only** — no `Phase N` labels. When you need the scope-reduction step, cite `prompt-pipeline` Phase 2 explicitly.

## Source of truth

This protocol owns the seat's thinking **procedure** (the rules and stages above). It does not own the seat's operative contract:

- `agents/orchestrator.md` is the runtime-loaded prompt and stays authoritative for **enforcement** — Decision Hierarchy, Confidence Gate, Hard Limits, Rules, Handoff Protocol, and the `do-not-run-tests-from-root` never-rule. The guard is *defined* here (thinking rule 6) and *enforced* in `agents/orchestrator.md` (`## Hard Limits`); the `## Thinking workflow` pointer only links back to this definition.
- [`prompt-pipeline.md`](./prompt-pipeline.md) owns Step 0 (Interpret) and Phase 2 (Reduce); the orchestrator is the sole Phase 2 executor (stage 3).
- The orchestrator's `## Project Context Source` and `## Rules` remain authoritative for *where* project context lives and for the seat's hard read-before-acting rule; thinking rules 1–4 state *which* files to read and *when*.

Where a rule legitimately appears in two files, the split is exactly the procedure/enforcement one above — do not restate the other file's copy.

## Cross-references

- [`prompt-pipeline.md`](./prompt-pipeline.md) — Step 0 (Interpret) and Phase 2 (Reduce).
- [`session-recovery.md`](./session-recovery.md) — resume flow when a session dies mid-stage.
- `agents/orchestrator.md` — Project Context Source, Decision Hierarchy, Confidence Gate, Hard Limits, Rules, Handoff Protocol.

## Notes

- There is no `workflows/` layer; do not reintroduce one.
- This protocol is the thinking cadence; `prompt-pipeline` is the prompt-processing pipeline. Composed: Step 0 runs in `delivery`, Phase 2 is stage 3 here, and the remaining stages govern how the orchestrator acts on the resulting scope.
