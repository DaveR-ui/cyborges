# Protocol: Prompt Pipeline

Two-stage analysis convention for the Delivery agent. **Every prompt** passes through Step 0 (Interpret) before any handling or delegation — no prompt skips the interpreter. The trivial/non-trivial verdict is an output of the interpreter's routing packet: trivial prompts (single-line fixes, factual lookups, unambiguous doc edits) are handled directly by Delivery AFTER Step 0, without Phase 2.

This protocol defines the two stages conceptually; the executor of each step may vary:

- **Step 0: Interpret** is executed by the [`interpreter`](../agents/interpreter.md) subagent. The interpreter reconciles vocabulary via grep/glob, captures constraints, and may ask the human one batch of clarifying questions.
- **Phase 2: Reduce** (this protocol) is executed by the **`orchestrator`** for every non-trivial prompt. `delivery` never performs Phase 2 — Reduce delegating it is a one-line subagent call, and doing it on the cheap tier is the failure mode this protocol removes.

## When to apply

Always. Step 0 (Interpret) runs on **every prompt** — it is the entry point of the delivery turn, not an opt-in for complex work. Delivery never pre-classifies a prompt to skip the interpreter; that deliberation is the failure mode the hard gate removes. The turn-entry gate procedure itself is owned by the [`dispatch` protocol](./dispatch.md); this protocol owns the pipeline stages.

The only branch happens AFTER Step 0, based on the interpreter's routing packet:

- **Packet says trivial** (single-line fix, factual lookup, "how do I...", pure doc edit with unambiguous scope) -> Delivery handles it directly per its Delegation table; Phase 2 is skipped.
- **Packet says non-trivial** -> Delivery delegates to `orchestrator`, which runs Phase 2 (Reduce) and then decomposes the work. Phase 2 never runs on `delivery`.

## Ambient instructions (never relied upon)

This system **never** relies on auto-loaded ambient instruction files. There is no global
`AGENTS.md` in this repository and creating one is forbidden, and `opencode.json` carries
no `instructions` entry. Project context is read **on demand** from explicit paths
(`docs/project.md`, `docs/context/*.md`). This is deliberate: on opencode V2 the
`instructions` config field is accepted but **not loaded**, and `AGENTS.md` is V2's only
ambient instruction source — silently discovered, injected, and invisible in the prompt
inventory. Step 0 reads `docs/project.md` explicitly; never assume ambient context.

This bans *ambient* files, not *on-demand* reads: explicit `docs/context/*.md` reads
remain expected. The same boundary scopes `AGENTS.md` itself: *this* repository's own
`AGENTS.md` (the agent-system repo installed at `~/.config/opencode`) is a forbidden
ambient channel — it must not exist and must never be read — while a **consumer
project's** root `AGENTS.md` is an allowed *on-demand* read and is the canonical
source of that project's conventions (read explicitly, never relied upon ambiently).

## Step 0: Interpret (executed by the `interpreter` subagent)

The `delivery` agent invokes the `interpreter` subagent with the raw prompt. The interpreter:

1. Reads the prompt verbatim (the raw prompt arrives in the human's language).
2. Normalizes vocabulary and aliases against the codebase (`grep`) and `docs/project.md`.
3. Captures hard constraints and explicit non-goals.
4. Identifies the smallest actionable slice, the hidden assumption, and expected output.
5. Optionally calls the `question` tool ONCE, with a batch of all blocking questions, if the route would materially change based on the answer.
6. Returns a compact routing packet written entirely in English (see [`interpreter.md`](../agents/interpreter.md) for the full shape).

The full process and the routing packet schema are defined in [`agents/interpreter.md`](../agents/interpreter.md). Do not duplicate it here.

## Phase 2: Reduce

**Goal:** turn the routing packet from Step 0 into a concrete scope, complexity level, hot-spot map, and verification path — the minimum a subagent needs to start work.

### Inputs

1. Routing packet from Step 0 (produced by the `interpreter` subagent).
2. Project context from `docs/project.md` and relevant `docs/context/*.md` (read on demand).

### Process

1. **Module scope** — declare which modules are IN and which are OUT. A module is IN if: directly mentioned, functional dependency, data dependency, UI/UX boundary, or API boundary.
2. **Inputs / outputs / state** — for each in-scope module: what flows in, what flows out, what state changes, what side effects, where the source of truth lives.
3. **Complexity level** — pick the lowest level that matches:
   - **Baja** — single file, isolated logic, no dependencies.
   - **Media** — 2-3 files cross-module, known patterns, clear boundaries.
   - **Media-Alta** — conditional branching by env/type, state changes.
   - **Alta** — multi-environment behavior, external integrations, shared state.
   - **Muy Alta** — data migration, schema changes, breaking changes.
4. **Hot spots** — flag any critical decision point. Each hot spot needs: the decision, two approaches with risk/benefit, a mandatory A/B question — and a **branch-map** entry (§ "Branch map (machine-readable)"): a closed-choice question with enumerated outcomes.
   - State ownership pivot.
   - Breaking refactor (>900 lines touched).
   - Ambiguous data flow.
   - Standard supremacy violation (plan contradicts project rules).
   - Compute guard (>5 files with logic changes).
   - Security/guardrail bypass.
5. **Dependencies** — upstream (what this depends on) and downstream (what depends on this).
6. **Boundaries** — explicit OUT-of-scope list with reasons. Be specific with module names and file paths.
7. **Verification path** — how success is measured. Tests that should pass. Observable behavior that proves completion.

### Output (scope + plan)

```markdown
## Scope

**Complexity:** <Baja|Media|Media-Alta|Alta|Muy Alta>
**Hot spots:** <count> (<one-line summary each>)

**In scope:**
- <module> — <why>

**Out of scope (explicit):**
- <module> — <why excluded>

**Key files:**
- <path> — <purpose> — <read|modify|create>

**Verification path:**
- <how success is measured>
- <tests that should pass>
- <observable behavior>
```

### Branch map (machine-readable)

When the scope has one or more hot spots, the scope also emits a **branch map**:
each hot spot is a closed-choice decision with enumerated outcomes, so downstream
consumers (the Typed-Decision Panel, the Confidence Gate) read fields instead of
re-parsing prose. The map is the machine-readable twin of the `**Hot spots:**`
line — the prose stays for humans; the map is what the orchestrator branches on.

```json
{
  "hot_spots": [
    {
      "id": "HS1",
      "decision": "state ownership pivot",
      "locus": "design",
      "question": "Should X own the state, or Y?",
      "outcomes": ["x-owns", "y-owns"],
      "load_bearing": true,
      "chosen": null
    }
  ]
}
```

- `locus` is `design` (boundaries, layering, pattern choice) or `proposal` (is
  this plan sound / which alternative) — it selects the panel seat
  (`architect` / `analista`) per `agents/orchestrator.md` → `## Typed-Decision Panel`.
  A hot spot that is both is recorded as `design`.
- `outcomes` is the enum: two or more mutually exclusive, closed-choice results.
- `load_bearing` mirrors the Phase 2 hot-spot test and feeds the Confidence Gate.
  Every emitted hot spot is load-bearing by definition, so the field is always
  `true` on emitted entries — it is written explicitly, not as a discriminator.
- `chosen` stays `null` until the panel/stakeholder resolves the branch.
- No hot spots → no branch map (omit it; an empty `hot_spots` array is equivalent).

## Decision Rules

- **No validation, no execution** — for Alta / Muy Alta complexity, the plan MUST be validated by the human before any implementation begins.
- **Standard supremacy** — if the proposed scope contradicts established project rules, flag it as a hot spot automatically.
- **Compute guard** — plans touching >5 files are hot spots by default.
- **Hidden assumption is mandatory** — the routing packet from Step 0 already carries the hidden assumption. If the assumption feels load-bearing, surface it again in the scope.
- **Hot spots are cumulative** — multiple hot spots bump the complexity level.
- **One question block** — never ask the human 5 questions across 5 turns. Group all clarifications into a single message. The interpreter already follows this rule for Step 0; Phase 2 must follow it too.
- **Confidence gate** — every decision-returning subagent return carries a calibrated `confidence` (0–1). A *load-bearing* decision (Phase 2 hot spot or an irreversibility class — see step 4) at `confidence < 0.5` MUST surface as `STATUS: NEEDS_HUMAN`; only a *reversible* decision may proceed on a documented default. Never silently treat low confidence as certain — see `agents/orchestrator.md` → Confidence Gate.
- **Typed-decision panel** — when a scope has 2+ independent A/B hot spots, the orchestrator may release one `analista`/`architect` instance per hot spot against the frozen routing packet and the scope's **branch map**; the panel is advisory and stays internal (one question block, no extra human rounds).

## Integration

The Delivery agent runs the two stages in sequence:

```
Raw prompt -> Step 0 (interpreter subagent) -> routing packet -> [non-trivial only] delegate to orchestrator -> Phase 2 (Reduce) -> scope + plan -> decompose
```

The Delivery's system prompt is small on purpose. Sections in the system prompt that say "see prompt-pipeline.md" or "call interpreter first" are anchors into this protocol. This file is the source of truth.

After Step 0, Delivery picks the delegation target:

- **Trivial** (post-Step 0) -> handle directly (doc edit, simple lookup).
- **Non-trivial** (1-2 files OR multi-step) -> delegate to `orchestrator` with the routing packet as the handoff. The orchestrator runs Phase 2 (Reduce), produces the scope, and decomposes (releasing `coder` (language=angular|go|css), `tester`, `reviewer`, etc. in parallel). Do not route 1-2 file work to a coder directly — the reduce step is the orchestrator's job.

## Notes

- Edge cases are practical, not theoretical.
- Acceptance criteria are testable, not vague.
- The hidden assumption is the most important thing Step 0 surfaces — it is what nobody is thinking about. Phase 2 must carry it forward.
