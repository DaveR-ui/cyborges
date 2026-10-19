# Protocol: Subagent Return Check

Single procedure for callers of schema-bearing children, including `delivery`'s
direct calls (especially `interpreter`), `orchestrator`, and self-fan-out callers.
This is one manual responsibility with an optional tool, not a runtime hook,
automatic gate, permission change, or substitute for semantic review/Confidence Gate.
Resolve agent-system assets against the injected `agent-system` reference.

1. Read the child's `agents/<id>.md` frontmatter and exact sibling `output_schema`.
   The frontmatter path is the SSOT. `delivery`, `orchestrator`, and `external-scout`
   deliberately have no schema: assess their prose/coordination contract instead.
2. Receive final text in memory; never write `summary.md`, `output-full.md`,
   `manifest.md`, or a temporary return file. Accept exactly one JSON value or one
   `json` fenced JSON value, with no surrounding prose. Verify its complete shape
   against the schema, not a guessed key list. Do not reinterpret malformed text.
3. Optionally pipe the existing in-memory return through
   `scripts/check-subagent-return.py --agent <id>` using an available Python
   interpreter. The script finds its root via `__file__`, resolves the schema from
   frontmatter, and emits bounded JSON diagnostics without raw child data.
   Exit **0** = valid shape; **1** = invalid return; **2** = cannot verify, including
   unsupported schema/infrastructure or distinct `no_schema` status. Exit 2 is
   never a pass: manually assess the exact schema, or return `STUCK` if verification
   remains impossible. The checker supports the current schema vocabulary only;
   it fails loudly on unknown constructs/references rather than ignoring them.
   This deliberately bounded subset is not a full normative JSON Schema engine.
   JSON decimals preserve large numbers; integral values such as `1.0` satisfy
   integer type, numeric enum equality is mathematical, and booleans are not numbers.
4. On a verified malformed/non-conforming return, allow **at most one repair
   re-invocation per original child turn**, carrying findings and the exact schema
   path. Track `(original child id, task fingerprint, repair-used)` in memory so
   launch deduplication admits this one labeled repair, but never creates a loop.
   The cap is per child, including every fan-out child, and survives dedup/restart
   state. Validate the repaired return by this same procedure.
5. Exhausted invalid return => `STUCK`, with failure log and recommended next step.
   Only demonstrable contract/authoring ambiguity requiring a human choice =>
   `NEEDS_HUMAN`, with the concrete choice; identical repeated errors alone are
   not evidence of ambiguity. Never fabricate schema validity or completed work.
6. Record what actually happened: checker invocation, resolved schema, and exit
   result if used; otherwise explicitly record a manual schema assessment and
   findings. Do not claim a command ran when it did not.

Shape success does not establish semantic correctness or trustworthy confidence.
The Confidence Gate's existing single consistency probe is separate from schema
repair: record it separately, do not reset the original child's repair budget,
and do not use either mechanism to evade the other's cap or escalation rule.

For authoring verification, `--check-examples` checks fenced JSON examples in each
schema agent's Structured Return section. It skips intentional prose-only agents;
missing examples, unsupported contracts, and infrastructure errors fail closed.
