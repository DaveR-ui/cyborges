# Protocol: Subagent Spec Template

Canonical shape for subagent definitions under `agents/`. Read this before creating a new subagent or auditing an existing one. Everything under `agents/` — recursively — is auto-loaded as an agent, so specs, templates, and partials must never live there.

## Purpose

One canonical shape for every subagent spec, so the orchestrator, human reviewers, and any future scaffolding tool can rely on a predictable structure.

## Frontmatter spec

| Field | Status | Notes |
|---|---|---|
| `description` | **required** | One line, routing-oriented — the orchestrator reads this to decide delegation. Name the discipline, the accepted task shapes, and the structured return if any. |
| `mode` | **required** | Literal value (`primary` for delivery, `subagent` for everything else). |
| `model` | optional | Fully qualified (`<provider>/<model>`). Declared in the agent's frontmatter as an explicit override; when omitted, the subagent inherits the invoking primary agent's model. Part of the cost contract — see the orchestrator's subagent table. |
| `permission` | optional | The agent-level permission block (e.g. read-only adapters, `task` fan-out grants). `task` is the subagent-dispatch gate on V2: `task: deny` blocks recursion, `task: { <agent>: allow }` grants it. Valid V2 action keys include `read`, `edit`, `glob`, `grep`, `list`, `bash`, `task`, `webfetch`, `websearch`, `question`, `external_directory`, `lsp`, `skill`, `doom_loop` — `webfetch`/`websearch` are first-class, not legacy. |
| `output_schema` | optional | Relative path to the sibling JSON Schema (`./<id>.schema.json`) — see the bridge below. |

There is deliberately **no `temperature`**. On V2 an agent `temperature` is not sent with model requests, so the field would be dead config; agents omit it.

## Canonical full shape

Body sections, in canonical order, grouped into 3 macro sections with grep-stable HTML comment anchors. Each macro heading MUST carry its anchor on the same line; the comment is part of the heading and must not be removed. Ordering is checked by anchor, not by bare heading text.

### The 3-section shell

The 7+1 canonical headings are grouped into 3 macro sections. The mapping is lossless — no heading is removed, only grouped:

| Macro | Anchor (on `##` line) | Contains (`###` sub-headings) | Purpose |
|---|---|---|---|
| 1 — Init / Preconditions | `<!-- Section 1: Init -->` | `### Role`, `### Scope`, `### Stack / Context` | identity + acceptance + knowledge |
| 2 — Execution / Standards | `<!-- Section 2: Execution -->` | `### Standards`, `### Anti-Patterns`, (slot) role-specific operational sections | how to work + what to avoid |
| 3 — Finalization / Return | `<!-- Section 3: Finalization -->` | `### Structured Return`, `### Rules` | output contract + hard rules |

Frontmatter remains the single source of truth for per-agent config (`description`, `mode`, `model`, `permission`, `output_schema`). `opencode.json` carries top-level runtime only, never a per-agent block. A manually created subagent MUST emit the three macro anchors.

Canonical order of the headings:

1. `## Role` — who the agent is (1–3 sentences). The H1 title plus a short preamble may sit above it.
2. `## Scope` — the accept / decline contract: which task shapes it takes, which it re-routes (and to whom).
3. `## Stack / Context` — knowledge: stack facts, versions, project-doc pointers.
4. `## Standards` — checklists, principles, definitions of done.
5. `## Anti-Patterns` — what to avoid, phrased as prohibitions with brief reasons.
6. *(slot)* Role-specific sections, if any.
7. `## Structured Return` — the output contract (see the bridge below).
8. `## Rules` — hard behavioral rules, terse, one per line.

Existing sections keep working names where renaming adds no value (e.g. reviewer's `## Checklist` serves as `## Standards`); the audit harmonizes, it does not churn.

### Anchor contract

- Pattern: `<!-- Section N: <Name> -->` where `N ∈ {1,2,3}` and `<Name>` is `Init`, `Execution`, or `Finalization`.
- Placement: on the same line as the `## N — <Title>` heading, trailing after a space. Example: `## 1 — Init / Preconditions  <!-- Section 1: Init -->`.
- Order: anchors, when present, must be strictly increasing `1 < 2 < 3`, with no duplicates. A file with fewer than 3 macros (thin variants) passes if its present anchors are ordered.
- Scope: anchors are required for NEW and edited subagent specs going forward. Existing subagents are not mass-retrofitted.

## Macro section details

## 1 — Init / Preconditions  <!-- Section 1: Init -->

### Role

Who the agent is (1–3 sentences). The H1 title plus a short preamble may sit above it.

### Scope

The accept / decline contract: which task shapes it takes, which it re-routes (and to whom).

### Stack / Context

Knowledge: stack facts, versions, project-doc pointers.

## 2 — Execution / Standards  <!-- Section 2: Execution -->

### Standards

Checklists, principles, definitions of done.

### Anti-Patterns

What to avoid, phrased as prohibitions with brief reasons.

### (slot) Role-specific operational sections

If any, describe HOW the role operates; they do not change with the stack. Examples: `## Sampling and Fan-out` (`explorer`, `reviewer`), `## Approach` (`explorer`), `## Contract` (thin Variant B).

## 3 — Finalization / Return  <!-- Section 3: Finalization -->

### Structured Return

The output contract (see the bridge below).

### Rules

Hard behavioral rules, terse, one per line.

## Thin variants inside the 3-section shell

A subagent that is a **thin adapter over a single capability** — no `output_schema` or a contract that fits in ~50 lines — MAY use a reduced form INSIDE the same 3-section shell. The shell is not bypassed: macros are omitted by design. Do not force the full 7-section form onto thin adapters (it would bloat 43–61L adapters to 79–128L, ~60% overhead, and contradict the decision to delegate stack knowledge to `docs/context/`).

Two sanctioned variants:

| Variant | Shell sections used | Sub-headings present | Example files | When to use | Must contain |
|---|---|---|---|---|---|
| Variant A: Stack/Context-delegating coder/tester | 1 (partial) + 3 | Sec1: only `### Stack / Context`; Sec2: omitted or only slot; Sec3: `### Rules` + `### Structured Return` | `coder.md`, `tester.md` | Specialist delegating language baselines to agent-owned on-demand protocols and project facts to `docs/project.md` / `docs/context/` | `Stack / Context` with exact baseline pointers resolved against `agent-system` where applicable and project docs as truth for versions, layout, commands, and explicit conventions; `Rules`, `Structured Return` via sibling schema, frontmatter with `output_schema` |
| Variant B: Contract minimal relay | 1 (merged) + 2/3 (partial) | `### Contract` (Role+Scope merged) + `### When to use` / `### When NOT to use` (+ `### Model` if needed) | `external-scout.md` | Single-capability relay/scout: one package+version lookup, no `output_schema`, text return, deny `edit`/`bash` | `Contract` (one capability), `When to use`, `When NOT to use`, `Model`; permission deny as needed |

Rules for thin variants:

- Variant A is explicitly exempt from `### Role` and `### Scope` in Sec1 — its role/routing remain in the spec while project scope routes through the Slices table in `docs/project.md`. Language baselines live in agent-owned protocols; project facts and explicit conventions take precedence. Do not add empty `Role`/`Scope` to satisfy the shell.
- Variant B's `### Contract` is the merged Role+Scope; it is NOT an alias for `### Structured Return` — the return is prose/text described in the contract.
- Both variants remain valid inside the 3-section shell via omitted macros. The full shape (3 macros, all H3s) remains the default for all other subagents — the **six** grandfathered agents (`architect`, `explorer`, `reviewer`, `documenter`, `analista`, `interpreter`), which predate the mandatory macro anchors and are not mass-retrofitted (see "Anchor contract"); `coder` and `tester` are Variant A.

## The `output_schema` ↔ sibling schema bridge

- The schema lives in a **sibling file** `agents/<id>.schema.json`, referenced from the subagent's frontmatter via `output_schema: ./<id>.schema.json`. The `.md` frontmatter is the single source of truth for the return contract.
- The subagent's `## Structured Return` section documents the JSON shape, names the schema, shows an example, and points at the sibling file.
- The two MUST stay in sync: change one, change the other. The `.md` frontmatter and its sibling schema are authored together.
- Subagents without an `output_schema` return plain text (or markdown); their `## Structured Return` (full shape) or `## Contract` (thin Variant B) describes the expected return in prose. Current subagents without a schema, **by design**: `delivery` (markdown turn contract), `orchestrator` (markdown agent-snapshot), `external-scout` (plain-text contract). These three are **prose-only contracts** — no `output_schema` is intended. `delivery` and `orchestrator` additionally carry a **typed coordination envelope** on the two hops between them (typed `status` / `files_changed` / `subagent_outcomes` around the markdown report), defined in `agents/orchestrator.md` → `## Handoff Protocol`; the envelope is a convention the two seats read, not an `output_schema` (V2 would not enforce it either way), so the prose-only statement still holds.
- **`output_schema` is NOT runtime-enforced.** On opencode V2 it is not a recognized agent field: it is captured as a legacy rest key and routed to `request.body` (preserved, not sent), and the subagent tool returns the child's final text as an opaque string without validating it (JSON is a convention, not a runtime contract). The runtime does not preserve raw text for diagnostics. This spec owns the behavior explanation; callers (`delivery`, `orchestrator`, and fan-out callers) follow the single manual responsibility in [`subagent-return-check.md`](./subagent-return-check.md), optionally tool-assisted. The orchestrator's Hard Limits and delivery's direct-call rule enforce that procedure: at most one repair per original child, no reinterpretation or fabricated validity, and no uncapped competing loop. Never write `summary.md` / `output-full.md` / `manifest.md` to disk — the runtime captures returns on the EventV2 bus.

## `opencode.json` — top-level runtime knobs only

`opencode.json` carries **top-level runtime config only**: `$schema`, `default_agent`, `permissions` (global), `references`, `compaction`, `experimental`, `mcp`, `model`, and `agents` (the built-in `title` model slot ONLY — not a per-agent block; `agents.title.model` supplies the title-generation model and is also read at dispatch time by the orchestrator as the cheap, different-family model-independence slot for `reviewer`/`analista` and the Typed-Decision Panel). There is **no per-agent block** — every per-agent field (including `model`) lives in the agent's `.md` frontmatter.

Every per-agent field lives in the agent's `.md` frontmatter:

| Field | Home |
|---|---|
| `description`, `mode`, `model`, `permission` | The agent `.md` frontmatter |
| `output_schema` | Frontmatter path → sibling `<id>.schema.json` |
| `permission.task` fan-out (which subagents `delivery` / `orchestrator` may call) | Frontmatter of `delivery.md` / `orchestrator.md` |
| Global `permissions` rules (`{action, resource, effect}`) | Stay in `opencode.json` |

**To change a model**: edit the agent's frontmatter (`agents/<id>.md`), then restart opencode. `opencode.json` is untouched.

Rationale: the `.md` is the canonical artifact the runtime loads; keeping `model` in the agent file makes each agent self-contained — one file to read for everything about that agent, with no frontmatter↔JSON drift. `opencode.json` shrinks to true runtime config.

## Naming convention

- Parent keeps the plain role name (e.g. `coder.md`).
- No specialization files exist today: the coder is centralized into a single language-parameterized `coder.md` (Variant A) that branches by a `language=angular|go|css` task payload, and the tester does the same by `framework=…`.

## Rules

- New subagents MUST follow this spec (full or thin shape) from day one — this file is the shape authority for any new subagent (and for any future scaffolding tool).
- Audits fill missing sections with sensible content; they do NOT rewrite sections that already work.
- All agent-system files in ENGLISH.
