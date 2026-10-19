# Session Recovery Protocol

> How the agent system recovers from an interrupted or STUCK session in the
> `delivery` → `orchestrator` → subagent hierarchy. This protocol is the
> **fallback** for when an orchestrator session itself dies; intra-orchestrator
> child failures are already handled by the existing `STATUS: STUCK` path in
> `agents/orchestrator.md`.

## Purpose

Sessions in opencode are persistent server-side objects. When a session is
interrupted mid-flight (HTTP timeout, credit exhaustion, manual abort, unexpected
termination), the work it was doing does not disappear — it is still addressable
via the opencode session API. This protocol defines how to inspect a failed
session, clean up its still-running children, and produce a handoff snapshot
that a fresh orchestrator instance can consume through the
`## Resume instructions (if restart)` block of
`agents/orchestrator.md#resume-instructions-if-restart`.
Without this protocol, an interrupted orchestrator forces the human
to reconstruct context by hand; with it, recovery is a mechanical API walk.

## Principle: resumability belongs to stateful seats

A seat is resumable if and only if it owns durable task state that cannot be
reconstructed from its artifacts. Only the `orchestrator` holds that state
(decomposition, checkpoints, the `agent-snapshot`). `delivery` holds no durable
state (Mode 1: nothing to recover). Every other subagent — `coder`, `tester`,
`explorer`, `documenter`, `reviewer`, `analista`, `architect`, `external-scout`,
`interpreter` — is a stateless worker: its value is the artifact it produced,
which the orchestrator already recorded.

**Consequence:** only the `orchestrator` has a resume path
(`agents/orchestrator.md#resume-instructions-if-restart`). All other subagents
are always re-instantiated as **fresh instances**, deterministically, from the
artifacts the stateful seat recorded — never resumed from memory.

**Mechanism (option A — snapshot-based):** a "resume" always means a **new**
orchestrator session seeded by the prior `agent-snapshot` (the four fields of
`## Resume instructions (if restart)`). Literal session-lineage resume — reusing
the failed session's identity via `POST /session {parentID}`, or the automated
`fork` step — is **out of scope for this protocol's resume mechanism**: recovery
never reuses a dead session's lineage. (A human may still fork a dead session
manually to discard a half-applied diff — see the Mode 2 step 10 note; that is
diff hygiene, not seat reinstatement.)

## When to apply

Apply this protocol when you observe any of the following:

- `STATUS: STUCK` returned by an orchestrator.
- A `Subagent.Interrupted` event on the EventV2 bus (see
  `agents/orchestrator.md` — Subagent outcomes block and interruption
  notes).
- `POST /session/:id/abort` triggered by `delivery` (see
  `agents/orchestrator.md` — Strategic Pauses).
- A human pastes a session URI like
  `oc://renderer/server/c2lkZWNhcg/session/ses_xxx...`.
- HTTP timeout, credit exhaustion, or unexpected termination mid-flight.

## URI parser

Session URIs have the shape:

```
oc://renderer/server/<base64>/session/<id>
```

- The `<base64>` segment is a **per-server name**. Example: `c2lkZWNhcg`
  base64-decodes to `"sidecar"`. It is safe to log.
- The `<id>` segment after `/session/` is the real **API id** used in every
  endpoint below (e.g. `ses_050bab171ffevVZj1KPclKHp3R`).

How to parse (pseudo-steps, not code):

1. Split the URI on `/session/`. The tail is the API id.
2. Take the head, split on `/server/`, base64-decode the tail to get the
   server name (informational only).
3. Use the API id from step 1 in all `GET`/`POST /session/:id/...` calls.

## Server discovery & auth

- Base URL: `OPENCODE_SERVER_URL` env var; fallback `http://127.0.0.1:4096`.
- Auth: HTTP Basic. Username `opencode` (override via
  `OPENCODE_SERVER_USERNAME`), password from `OPENCODE_SERVER_PASSWORD`.
- **The password comes from the environment only — never from disk, never from
  command-line arguments, never into logs.**
- Advanced (not covered by this protocol): mDNS discovery via `--mdns` /
  `--mdns-domain opencode.local`.

## Recovery flow per depth level

### Mode 1 — `delivery` interrupted

Nothing to recover. `delivery` holds no durable task state; the new delivery
session reloads `docs/` on its next prompt and the human re-states the request.
One sentence of context from the human is sufficient.

### Mode 2 — `orchestrator` interrupted (PRIMARY case)

Walk the opencode session API in this order:

1. `GET /global/health` — pre-flight check that the server is reachable.
2. `GET /session/status` — map of session id → state; find whether the failed
   session is `running`, `idle`, or something else.
3. `GET /session/:id` — metadata of the failed orchestrator (title, parentID,
   timestamps).
4. `GET /session/:id/children` — list coder/tester/etc. children as
   `ChildInfo { status, summary, agentType, durationMs }`.
5. For each child still in `running`: `POST /session/:id/abort` (cleanup
   before resume).
6. If the orchestrator session itself is still `running`:
   `POST /session/:id/abort`.
7. `GET /session/:id/message?limit=20` — last 20 messages for context.
8. `GET /session/:id/todo` — pending todo list.
9. `GET /session/:id/diff` — files changed so far (optionally
   `?messageID=<msgID>` for a per-message diff).
10. Resume (option A): synthesize the recovered snapshot (see Output shape below)
    and have `delivery` launch a **new** orchestrator instance seeded with it.
    The failed session's identity/lineage is NOT reused — recovery produces a
    snapshot, not a revived session.

> `POST /session/:id/fork` at a known-good checkpoint remains available as a
> **manual human action** to discard a half-applied diff, but it is not part of
> the system's resume mechanism and does not reinstate the seat's state.

### Mode 3 — subagent child interrupted inside a LIVE orchestrator

Already handled by `STATUS: STUCK` in `agents/orchestrator.md`. This
protocol is the fallback for when the orchestrator itself died; intra-orchestrator
child failures are managed by the existing `STATUS: STUCK` path.

## Output shape

The "recovered snapshot" produced by the Mode 2 walk MUST map 1:1 to the four
fields of the `## Resume instructions (if restart)` block in
`agents/orchestrator.md#resume-instructions-if-restart`:

- **Original task** ← recovered from `GET /session/:id` title or the first
  user message.
- **Acceptance criteria still open** ← recovered from `GET /session/:id/todo`.
- **Latest state** ← one-paragraph summary synthesized from the last messages
  (`GET /session/:id/message?limit=20`).
- **Next concrete step** ← the first unchecked todo item, or inferred from the
  last assistant message.

## No helper script

No helper script ships with this protocol. Perform the API walk above manually
with any HTTP client (e.g. `curl`) — all decisions about what to do with the
returned JSON live in this protocol.

## Cross-references

- `agents/orchestrator.md` — Strategic Pauses section: existing
  `POST /session/:id/abort` mention.
- `agents/orchestrator.md#resume-instructions-if-restart` — `## Resume
  instructions (if restart)` block: consumer of this protocol's output.
- `agents/delivery.md` — Session Preflight / Interrupted Session
  Recovery note.
- <https://opencode.ai/docs/server/#sessions> (English) /
  <https://opencode.ai/docs/es/server/#sesiones> (Spanish).

## Caveats / non-goals

- **No shipped helper.** The API walk is performed manually (or by an
  orchestrator instrumenting it directly); a packaged helper script is out of
  scope.
- **Single-server assumption.** Multi-server orchestration is out of scope; the
  flow assumes one `sidecar` server.
- **No automatic invocation.** The API walk is performed manually by the user
  or by a recovering orchestrator. `delivery` and `interpreter` may **consult**
  this protocol to route recovery (e.g. `delivery` links to it before declaring
  `NEEDS_HUMAN`), but they do **not** perform the API walk themselves.
- **No auto-deletion of failed sessions.** Failed sessions are left in place.
  The user may delete them via `DELETE /session/:id` if desired (endpoint noted
  here for reference; intentionally not scripted).
