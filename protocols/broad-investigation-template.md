# Protocol: Broad Investigation Template

Compact scaffold for prompts that ask an agent to **map, inventory, or audit a class of thing across the whole repo** (e.g. "find every SQLite database", "audit storage coverage", "list every permission check"). Apply only when incomplete coverage is the worst failure mode.

## When to use

- The task requires a complete inventory or audit, not depth in a single area.
- The output is a structured report, not code changes.
- Coverage > speed; over-coverage > under-coverage.

## When NOT to use

- Targeted lookups ("where is `X` defined?") — `explorer` handles these directly.
- Code work — `coder` (language=angular|go|css) / `tester` / `reviewer` / `architect` have their own flows.
- Single-file edits, refactors, bug fixes, design questions.

## Template

```markdown
## Goal
[One sentence: the complete map / inventory / audit this task must produce.]

## Search Strategy
1. Start broad with `glob` / `grep` to enumerate every candidate (entry point, file pattern, keyword).
2. Recursively inspect each discovered directory.
3. Follow cross-references (imports, schema refs, migrations) before concluding.
4. Do not stop at the first match — continue until no additional entry points can be found.

## Evidence Requirements
- Every factual claim: `path/to/file.ts:Lstart-Lend` (or named symbol + path).
- Distinguish: **Verified** (read code), **Likely** (read but ambiguous), **Inferred** (not directly seen).
- If evidence is weak, mark the conclusion as Inferred explicitly.

## Coverage Checklist
[Customize per task. Default anchors:]
- [ ] <primary area, e.g. storage / permissions / session>
- [ ] relevant `docs/context/*.md`
- [ ] relevant project `AGENTS.md` rules (if the project ships one)
- [ ] runtime initialization / entry points
- [ ] schema and migration folders

## Definition of Done
- [ ] every entity in scope has a location with file:line evidence
- [ ] every entity has a brief description
- [ ] unknowns are listed explicitly (not silently omitted)
- [ ] every Coverage Checklist item is checked
```

## Notes

- The template is a **prompt-side scaffold** — the agent's return still goes through its standard structured format (`ExplorerOutput` for `explorer`, free text for `external-scout`, etc.). Do not duplicate the output schema here.
- Customize the **Coverage Checklist** per task. The defaults above are storage-flavored; for permission or session audits, swap the anchors.
- This protocol complements, does not replace, the **Acceptance Criteria** from `prompt-pipeline` Step 0 and the **Verification Path** from Phase 2. Use it after both phases, when constructing the actual subagent prompt.
- The **Verified / Likely / Inferred** scale is per-finding evidence quality; it is separate from the overall `ExplorerOutput.confidence` (low / medium / high), which rates the whole return. Do not merge the two scales.
- See `agents/explorer.md` (Approach) and `agents/orchestrator.md` (Available Protocols and Skills) for the call sites that should consult this template.
