#!/usr/bin/env bash
# validate-agent.sh - single lean, fail-closed integrity gate for this
# repository (the global opencode agent system, installed at ~/.config/opencode).
#
# The layout is flat: agents/ at the repo root, no per-project .opencode/ prefix.
#
# Checks (all static; no network, no jq/node required):
#   1.  opencode.json parses as valid JSON.
#   2.  flat agents/ layout (no legacy agents/subagents/); no agent uses the
#       deprecated `tools:` frontmatter field.
#   3.  opencode.json declares no field the installed V2 runtime ignores, and
#       no field retired by this repo:
#         - unsupported top-level: logLevel, server, subagent_depth, layout
#         - unsupported experimental: disable_paste_summary, batch_tool,
#           openTelemetry, primary_tools, continue_loop_on_deny
#         - unsupported compaction: prune, tail_turns
#         - forbidden: `instructions` (V2 no-op; ambient reliance forbidden),
#           `small_model` (superseded by agents.title.model),
#           singular `agent` block (V2-native is plural `agents`)
#   4.  no ambient AGENTS.md anywhere in the repo (rules live in agents/ +
#       protocols/ + code-lang/; ambient instruction files are never relied upon).
#   5.  no secret-like filename in the Git index (tracked/staged NUL paths),
#       including service.json, .env, *.env, *.pem, *.key, *.secret.
#   6.  every output_schema frontmatter path resolves to an existing file.
#   7.  every permission.task target resolves to agents/<id>.md. Scalar
#       `task: allow|deny|ask` is valid (no targets); wildcard patterns are
#       skipped; a file with no permission.task is fine. Parsing is
#       fail-closed: a task block that cannot be parsed/attributed is an ERROR.
#   8.  required frontmatter (description, mode) on every agent file; mode is
#       `primary` for delivery.md and `subagent` for every other agent file.
#   9.  config `references` paths resolve (docs/ paths are WARNINGS; anything
#       missing at the repo root is an ERROR).
#   10. every *.schema.json (in agents/ and scripts/) parses as valid JSON.
#   11. schema structural closure: draft 2020-12 `$schema`, object nodes need
#       `additionalProperties: false`, a non-empty `required` array, and a
#       description on every property (recursively through properties/items).
#   12. schema enum agent targets resolve (re_route_to -> agents/<v>.md;
#       re_route_language in angular|go|css).
#   13. no dangling markdown refs: links of the form ../protocols/<x>.md,
#       ./protocols/<x>.md, ../agents/<x>.md or (inside protocols/) ./<x>.md
#       must resolve, as must code-lang/ links and relative Markdown refs
#       inside recursively scanned code-lang/. Inline-code paths
#       `agents/<x>.md`, `protocols/<x>.md`, and `code-lang/.../<x>.md`
#       must resolve; links or inline-code paths into the retired
#       workflows/ directory are ERRORs.
#   14. stdlib child-return checker unit tests pass.
#   15. schema-agent Structured Return JSON examples pass the checker.
#
# Exit code: 0 = OK (warnings allowed), 1 = one or more ERRORs.
# Pure bash + Python 3 (PYTHON override, otherwise python3 then python).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)"

AGENTS_DIR="${ROOT}/agents"

if [ -f "${ROOT}/opencode.json" ]; then
  CONFIG="${ROOT}/opencode.json"
else
  echo "ERROR: no opencode.json found at ${ROOT}" >&2
  exit 1
fi

ERRORS=0
WARNINGS=0

err()  { echo "ERROR: $*" >&2;  ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN:  $*" >&2;  WARNINGS=$((WARNINGS + 1)); }

# --- helpers -----------------------------------------------------------------

probe_python() { "$1" -c 'import sys; sys.exit(0 if sys.version_info.major == 3 else 1)' >/dev/null 2>&1; }
PYTHON_BIN=""
if [ "${PYTHON+x}" = x ]; then
  if ! probe_python "${PYTHON:-}"; then
    echo "ERROR: explicit PYTHON must be an executable Python 3 interpreter; refusing fallback" >&2
    exit 1
  fi
  PYTHON_BIN="${PYTHON}"
else
  for candidate in python3 python; do
    if probe_python "${candidate}"; then
      PYTHON_BIN="${candidate}"
      break
    fi
  done
  if [ -z "${PYTHON_BIN}" ]; then
    echo "ERROR: executable Python 3 is required; python3 and python probes failed" >&2
    exit 1
  fi
fi
# Selection is fail-closed above; retained guards can never silently skip a check.
have_python() { [ -n "${PYTHON_BIN}" ]; }
export PYTHONDONTWRITEBYTECODE=1

frontmatter() {
  # Print the frontmatter block (between the first two --- lines) of a file.
  # Strip a leading UTF-8 BOM if present (breaks the ^--- anchor otherwise).
  sed '1s/^\xEF\xBB\xBF//' "$1" | awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f'
}

# --- 1. config JSON validity -------------------------------------------------

echo "== [1/15] config JSON =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot validate config JSON"
  exit 1
else
  if ! "${PYTHON_BIN}" -c 'import json,sys; json.load(open(sys.argv[1]))' "${CONFIG}"; then
    err "${CONFIG} is not valid JSON"
  else
    echo "ok: ${CONFIG}"
  fi
fi

# --- 2. flat agent layout + frontmatter cross-check --------------------------
# NOTE: model lives in the agent frontmatter, not in opencode.json.
# `model:` is an OPTIONAL per-agent override. The only hard frontmatter error
# here is the deprecated `tools:` field.

echo "== [2/15] flat agents/ layout + frontmatter (tools: check) =="
if [ -d "${ROOT}/agents/subagents" ]; then
  err "legacy agents/subagents/ layout found; agents must be flat under agents/"
fi
if [ ! -d "${AGENTS_DIR}" ]; then
  err "agents directory not found: ${AGENTS_DIR}"
else
  AGENT_FILES="$(find "${AGENTS_DIR}" -maxdepth 1 -name '*.md' | sort)"
  if [ -z "${AGENT_FILES}" ]; then
    err "no *.md agent files found in ${AGENTS_DIR}"
  fi
  while IFS= read -r md; do
    [ -f "${md}" ] || continue
    name="$(basename "${md}")"
    fm="$(frontmatter "${md}")"
    if echo "${fm}" | grep -q '^tools:'; then
      err "${name} uses deprecated 'tools:' frontmatter; use 'permission:' with allow/deny/ask instead"
    fi
  done <<< "${AGENT_FILES}"
  echo "ok: flat layout; frontmatter scanned (tools: check)"
fi

# --- 3. unsupported / forbidden config fields --------------------------------
# The unsupported lists mirror the installed runtime's config normalizer
# (core/src/config/normalize.ts, verified on v2.0.8). Re-verify against the
# runtime source if the opencode major version changes.
#
# These branches are INTENTIONALLY retained as anti-regression guards: the
# current opencode.json passes cleanly, so they never fire today — but they
# exist to catch a future re-introduction of a retired field (git history shows
# several of these were present in earlier revisions). Do NOT delete a branch
# just because it is currently dormant.

echo "== [3/15] unsupported / forbidden config fields =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot check config fields"
  exit 1
else
  PY_OUT="$("${PYTHON_BIN}" - "${CONFIG}" <<'PY'
import json, sys

try:
    cfg = json.load(open(sys.argv[1]))
except (json.JSONDecodeError, OSError):
    # Check [1] reports the malformed config; emit nothing so this check
    # cannot claim "ok" for a file it could not read.
    sys.exit(0)

# Keep in sync with core/src/config/normalize.ts (installed runtime v2.0.8).
# Retained deliberately as anti-regression guards even when the current config
# is clean; see the shell-level note above.
unsupported_top = ["logLevel", "server", "subagent_depth", "layout"]
unsupported_experimental = [
    "disable_paste_summary",
    "batch_tool",
    "openTelemetry",
    "primary_tools",
    "continue_loop_on_deny",
]
unsupported_compaction = ["prune", "tail_turns"]

if not isinstance(cfg, dict):
    sys.exit(0)

for key in unsupported_top:
    if key in cfg:
        print(f"ERROR: opencode.json has unsupported top-level field '{key}' "
              f"(ignored by V2)")

# Forbidden / retired fields.
if "instructions" in cfg:
    print("ERROR: opencode.json has 'instructions' (accepted but NOT loaded by "
          "V2; ambient reliance is forbidden)")
if "small_model" in cfg:
    print("ERROR: opencode.json has deprecated 'small_model' "
          "(superseded by agents.title.model)")
if "agent" in cfg:
    print("ERROR: opencode.json has a singular 'agent' block "
          "(V2-native is plural 'agents')")

experimental = cfg.get("experimental")
if isinstance(experimental, dict):
    for key in unsupported_experimental:
        if key in experimental:
            print(f"ERROR: opencode.json has unsupported field "
                  f"'experimental.{key}' (ignored by V2)")

compaction = cfg.get("compaction")
if isinstance(compaction, dict):
    for key in unsupported_compaction:
        if key in compaction:
            print(f"ERROR: opencode.json has unsupported field "
                  f"'compaction.{key}' (ignored by V2)")
PY
)"
  if [ -z "${PY_OUT}" ]; then
    echo "ok: no unsupported config fields"
  else
    while IFS= read -r line; do
      case "${line}" in
        ERROR:*) err "${line#ERROR: }" ;;
        WARN:*)  warn "${line#WARN: }" ;;
        *)       [ -n "${line}" ] && echo "${line}" ;;
      esac
    done <<< "${PY_OUT}"
  fi
fi

# --- 4. ambient AGENTS.md ----------------------------------------------------

echo "== [4/15] ambient AGENTS.md =="
AMBIENT_HITS=0
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  err "ambient AGENTS.md found: ${f#${ROOT}/} (rules live in agents/ + protocols/ + code-lang/)"
  AMBIENT_HITS=$((AMBIENT_HITS + 1))
done < <(find "${ROOT}" \
  \( -path "${ROOT}/.git" -o -path "${ROOT}/node_modules" -o -path "${ROOT}/.draft" \) -prune -o \
  -type f -name 'AGENTS.md' -print 2>/dev/null)
if [ "${AMBIENT_HITS}" -eq 0 ]; then
  echo "ok: no ambient AGENTS.md"
fi

# --- 5. secret scan ----------------------------------------------------------

echo "== [5/15] Git index secret filename scan =="
SECRET_HITS=0
if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "Git index unavailable: secret filename scan requires a Git working tree"
elif ! git -C "${ROOT}" ls-files --cached -z >/dev/null 2>&1; then
  err "Git index unavailable: cannot list tracked/staged paths"
else
while IFS= read -r -d '' f; do
  [ -n "${f}" ] || continue
  base="$(basename "${f}")"
  # `.env.example` variants are the documented, committable template — allow them.
  case "${base}" in
    .env.example|*.env.example) continue ;;
  esac
  case "${base}" in
    service.json|.env|*.env|.env.*|*.env.*|*.pem|*.key|*.secret)
      err "secret-like filename present in Git index: ${f}"
      SECRET_HITS=$((SECRET_HITS + 1))
      ;;
  esac
done < <(git -C "${ROOT}" ls-files --cached -z)
if [ "${SECRET_HITS}" -eq 0 ]; then
  echo "ok: no secret-like filenames in Git index (untracked runtime state excluded)"
fi
fi

# --- 6. output_schema resolution ---------------------------------------------

echo "== [6/15] output_schema files =="
for md in "${AGENTS_DIR}"/*.md; do
  [ -f "${md}" ] || continue
  schema="$(frontmatter "${md}" | awk -F': *' '/^output_schema:/{gsub(/ /,"",$2); print $2; exit}')"
  if [ -n "${schema}" ]; then
    base="$(cd "$(dirname "${md}")" && pwd)"
    if [ ! -e "${base}/${schema}" ]; then
      err "$(basename "${md}") declares output_schema '${schema}' but the file does not exist"
    else
      echo "ok: $(basename "${md}") -> ${schema}"
    fi
  fi
done

# --- 7. permission.task targets (fail-closed) --------------------------------

echo "== [7/15] permission.task targets =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot check permission.task"
  exit 1
else
  PY_OUT="$("${PYTHON_BIN}" - "${AGENTS_DIR}" <<'PY'
import glob, os, sys

agents_dir = sys.argv[1]


def frontmatter(path):
    """Return the frontmatter lines, or None if there is no closed block."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    if lines and lines[0].startswith("\ufeff"):
        lines[0] = lines[0][1:]
    if not lines or lines[0].strip() != "---":
        return None
    body = []
    for ln in lines[1:]:
        if ln.strip() == "---":
            return body
        body.append(ln)
    return None


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


VALID_ACTIONS = ("allow", "deny", "ask")


def parse_task(block, task_idx, task_indent, name):
    """Parse the `task:` block. Returns (targets, errors). Fail-closed."""
    errors = []
    targets = []
    rest = block[task_idx].strip()[len("task:"):].strip()

    children = []
    for ln in block[task_idx + 1:]:
        if ln.strip() == "":
            continue
        ind = indent_of(ln)
        if ind <= task_indent:
            break
        children.append((ind, ln))

    if rest != "":
        # Scalar form: `task: allow|deny|ask` (no targets).
        if rest not in VALID_ACTIONS:
            errors.append(f"{name} permission.task value '{rest}' is not "
                          f"allow|deny|ask; cannot attribute targets")
            return [], errors
        if children:
            errors.append(f"{name} permission.task has both a scalar value "
                          f"'{rest}' and nested entries; cannot attribute targets")
        return [], errors

    # Map form: `task:` followed by `<agent>: <action>` children.
    for ind, ln in children:
        if ind != task_indent + 2:
            errors.append(f"{name} permission.task entry has unexpected indent "
                          f"{ind}; cannot attribute target: {ln.strip()!r}")
            continue
        s = ln.strip()
        if ":" not in s:
            errors.append(f"{name} permission.task entry is not "
                          f"'<agent>: <action>': {s!r}")
            continue
        key, _, val = s.partition(":")
        key = key.strip()
        val = val.strip()
        if not key:
            errors.append(f"{name} permission.task entry has an empty target: {s!r}")
            continue
        if val not in VALID_ACTIONS:
            errors.append(f"{name} permission.task target '{key}' has invalid "
                          f"action '{val}' (expected allow|deny|ask)")
            continue
        targets.append(key)
    return targets, errors


files = sorted(glob.glob(os.path.join(agents_dir, "*.md")))
for path in files:
    name = os.path.basename(path)
    fm = frontmatter(path)
    if fm is None:
        print(f"ERROR: {name} has no closed frontmatter block "
              f"(missing opening/closing '---'); cannot validate permission.task")
        continue

    perm_idx = None
    for i, ln in enumerate(fm):
        if indent_of(ln) == 0 and ln.strip().startswith("permission:"):
            perm_idx = i
            break
    if perm_idx is None:
        continue

    block = []
    for ln in fm[perm_idx + 1:]:
        if ln.strip() == "":
            block.append(ln)
            continue
        if indent_of(ln) == 0:
            break
        block.append(ln)

    task_idx = None
    task_indent = None
    for i, ln in enumerate(block):
        if ln.strip().startswith("task:"):
            ind = indent_of(ln)
            if ind != 2:
                print(f"ERROR: {name} permission.task is indented unexpectedly "
                      f"(indent {ind}); cannot attribute targets")
                task_idx = -1
                break
            task_idx = i
            task_indent = ind
            break

    if task_idx is None or task_idx == -1:
        continue

    targets, errors = parse_task(block, task_idx, task_indent, name)
    for e in errors:
        print(f"ERROR: {e}")

    if errors:
        continue

    bad = False
    for t in targets:
        if any(c in t for c in "*?["):
            continue  # wildcard pattern: nothing to resolve
        if not os.path.isfile(os.path.join(agents_dir, f"{t}.md")):
            print(f"ERROR: {name} grants task access to '{t}' but "
                  f"agents/{t}.md does not exist")
            bad = True
    if targets and not bad:
        print(f"ok: {name} task targets exist")
PY
)"
  if [ -z "${PY_OUT}" ]; then
    echo "ok: no permission.task targets to resolve"
  else
    while IFS= read -r line; do
      case "${line}" in
        ERROR:*) err "${line#ERROR: }" ;;
        WARN:*)  warn "${line#WARN: }" ;;
        *)       [ -n "${line}" ] && echo "${line}" ;;
      esac
    done <<< "${PY_OUT}"
  fi
fi

# --- 8. required frontmatter -------------------------------------------------

echo "== [8/15] required frontmatter =="
for md in "${AGENTS_DIR}"/*.md; do
  [ -f "${md}" ] || continue
  name="$(basename "${md}")"
  fm="$(frontmatter "${md}")"
  if ! echo "${fm}" | grep -q '^description:'; then
    err "${name} is missing 'description' in frontmatter"
  fi
  mode="$(echo "${fm}" | awk -F': *' '/^mode:/{print $2; exit}')"
  if [ -z "${mode}" ]; then
    err "${name} is missing 'mode' in frontmatter"
  fi
  if [ "${name}" = "delivery.md" ]; then
    if [ -n "${mode}" ] && [ "${mode}" != "primary" ]; then err "${name} must be mode: primary"; fi
  else
    if [ -n "${mode}" ] && [ "${mode}" != "subagent" ]; then err "${name} must be mode: subagent"; fi
  fi
done
echo "ok: frontmatter scanned"

# --- 9. references paths -----------------------------------------------------

echo "== [9/15] config references paths =="
if have_python; then
  PY_OUT="$("${PYTHON_BIN}" - "${CONFIG}" "${ROOT}" <<'PY'
import json, os, sys
try:
    cfg = json.load(open(sys.argv[1]))
except (json.JSONDecodeError, OSError):
    sys.exit(0)
root = sys.argv[2]

if not isinstance(cfg, dict):
    sys.exit(0)

for name, ref in cfg.get("references", {}).items():
    p = ref.get("path", "")
    if not os.path.exists(os.path.join(root, p)):
        is_docs = p.startswith("docs/")
        tag = "WARN" if is_docs else "ERROR"
        print(f"{tag}: reference '{name}' path '{p}' does not exist")
    else:
        print(f"ok: reference '{name}'")
PY
)"
  while IFS= read -r line; do
    case "${line}" in
      ERROR:*) err "${line#ERROR: }" ;;
      WARN:*)  warn "${line#WARN: }" ;;
      *)       [ -n "${line}" ] && echo "${line}" ;;
    esac
  done <<< "${PY_OUT}"
fi

# --- 10. schema JSON files ---------------------------------------------------

echo "== [10/15] schema JSON files =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot validate schema JSON"
  exit 1
else
  for f in "${AGENTS_DIR}"/*.schema.json "${SCRIPT_DIR}"/*.schema.json; do
    # `[ -f ]` also skips an unmatched glob literal (e.g. no scripts/*.schema.json).
    [ -f "${f}" ] || continue
    if ! "${PYTHON_BIN}" -c 'import json,sys; json.load(open(sys.argv[1]))' "${f}" 2>/dev/null; then
      err "invalid JSON schema: ${f}"
    else
      echo "ok: $(basename "${f}")"
    fi
  done
fi

# --- 11. schema structural closure -------------------------------------------

echo "== [11/15] schema structural closure =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot check schema closure"
  exit 1
else
  PY_OUT="$("${PYTHON_BIN}" - "${AGENTS_DIR}" "${ROOT}" <<'PY'
import glob, json, os, sys
agents_dir = sys.argv[1]
root = sys.argv[2]

files = sorted(
    glob.glob(os.path.join(agents_dir, "*.schema.json"))
    + glob.glob(os.path.join(root, "scripts", "*.schema.json"))
)
if not files:
    print("WARN: no *.schema.json files found under agents/ or scripts/")

def walk(node, ptr, rel, errors):
    if not isinstance(node, dict):
        return
    if node.get("type") == "object" or "properties" in node:
        if node.get("additionalProperties") is not False:
            errors.append(f"{rel}#{ptr} is missing 'additionalProperties': false")
        required = node.get("required")
        if not isinstance(required, list) or not required:
            errors.append(f"{rel}#{ptr} is missing a non-empty 'required' array")
        for name, sub in node.get("properties", {}).items():
            pptr = f"{ptr}/properties/{name}"
            if not isinstance(sub, dict):
                continue
            desc = sub.get("description")
            if not isinstance(desc, str) or not desc.strip():
                errors.append(f"{rel}#{pptr} is missing 'description'")
            walk(sub, pptr, rel, errors)
    items = node.get("items")
    if isinstance(items, dict):
        walk(items, f"{ptr}/items", rel, errors)

for f in files:
    rel = os.path.relpath(f, root)
    try:
        schema = json.load(open(f))
    except json.JSONDecodeError:
        continue  # check 10 already reports malformed JSON
    errors = []
    uri = schema.get("$schema")
    if not isinstance(uri, str) or "2020-12" not in uri:
        errors.append(f"{rel} is missing a '$schema' containing '2020-12'")
    walk(schema, "", rel, errors)
    if errors:
        for e in errors:
            print(f"ERROR: {e}")
    else:
        print(f"ok: {rel}")
PY
)"
  while IFS= read -r line; do
    case "${line}" in
      ERROR:*) err "${line#ERROR: }" ;;
      WARN:*)  warn "${line#WARN: }" ;;
      *)       [ -n "${line}" ] && echo "${line}" ;;
    esac
  done <<< "${PY_OUT}"
fi

# --- 12. schema enum agent targets resolve -----------------------------------

echo "== [12/15] schema enum agent targets resolve =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot check schema enum targets"
  exit 1
else
  PY_OUT="$("${PYTHON_BIN}" - "${AGENTS_DIR}" "${ROOT}" <<'PY'
import glob, json, os, sys
agents_dir = sys.argv[1]
root = sys.argv[2]

files = sorted(glob.glob(os.path.join(agents_dir, "*.schema.json")))

def collect(node, found):
    if not isinstance(node, dict):
        return
    for key, sub in node.get("properties", {}).items():
        if isinstance(sub, dict):
            if key in ("re_route_to", "re_route_language") and isinstance(sub.get("enum"), list):
                found.append((key, sub["enum"]))
            collect(sub, found)
    items = node.get("items")
    if isinstance(items, dict):
        collect(items, found)

for f in files:
    rel = os.path.relpath(f, root)
    try:
        schema = json.load(open(f))
    except json.JSONDecodeError:
        continue  # check 10 already reports malformed JSON
    found = []
    collect(schema, found)
    errors = []
    has_re_route_to = False
    for key, values in found:
        if key == "re_route_to":
            has_re_route_to = True
            for v in values:
                if not os.path.isfile(os.path.join(agents_dir, f"{v}.md")):
                    errors.append(f"{rel} re_route_to enum value '{v}' has no agents/{v}.md")
        else:  # re_route_language
            for v in values:
                if v not in ("angular", "go", "css"):
                    errors.append(
                        f"{rel} re_route_language enum value '{v}' is not one of angular|go|css"
                    )
    if errors:
        for e in errors:
            print(f"ERROR: {e}")
    elif has_re_route_to:
        print(f"ok: {rel} re_route_to targets resolve")
    else:
        print(f"ok: {rel} (no re_route_to enum)")
PY
)"
  while IFS= read -r line; do
    case "${line}" in
      ERROR:*) err "${line#ERROR: }" ;;
      WARN:*)  warn "${line#WARN: }" ;;
      *)       [ -n "${line}" ] && echo "${line}" ;;
    esac
  done <<< "${PY_OUT}"
fi

# --- 13. dangling markdown refs ----------------------------------------------

echo "== [13/15] dangling refs =="
if ! have_python; then
  err "selected Python interpreter unavailable; cannot check dangling references"
  exit 1
else
  PY_OUT="$("${PYTHON_BIN}" - "${ROOT}" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
agents_dir = os.path.join(root, "agents")
protocols_dir = os.path.join(root, "protocols")
code_lang_dir = os.path.join(root, "code-lang")

link_re = re.compile(r"\]\(([^)]+)\)")
# Inline-code agent-system paths, e.g. `agents/delivery.md` or
# `code-lang/angular/standards.md`. The name class excludes glob/placeholder
# forms (`agents/<id>.md`, `agents/*.schema.json`, `code-lang/*/standards.md`),
# which are diagrams, not references. Backticked `workflows/<x>.md` is banned
# like a workflows/ link.
inline_re = re.compile(
    r"`((?:agents|protocols|workflows)/[A-Za-z0-9._-]+\.md|"
    r"code-lang/(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.md)`"
)
relative_inline_re = re.compile(
    r"`((?:\.\.?/)+(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.md|"
    r"[A-Za-z0-9._-]+\.md)`"
)


def scan_file(path, base_dir, in_protocols):
    errors = []
    rel = os.path.relpath(path, root)
    in_code_lang = rel.startswith("code-lang" + os.sep)
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return errors
    for m in link_re.finditer(text):
        raw = m.group(1).strip()
        target = raw.split()[0] if raw.split() else raw
        target = target.split("#")[0].split("?")[0]
        if not target:
            continue
        if target.startswith(("http://", "https://", "mailto:", "tel:", "#")):
            continue
        if "workflows/" in target or target.rstrip("/").endswith("workflows"):
            errors.append(f"{rel}: link points into retired 'workflows/' directory: {raw!r}")
            continue
        resolved = None
        if target.startswith("./protocols/"):
            resolved = os.path.join(root, target[2:])
        elif target.startswith("./agents/"):
            resolved = os.path.join(root, target[2:])
        elif target.startswith("../protocols/"):
            resolved = os.path.normpath(os.path.join(base_dir, target))
        elif target.startswith("../agents/"):
            resolved = os.path.normpath(os.path.join(base_dir, target))
        elif target.startswith(("./code-lang/", "code-lang/")):
            ref = target[2:] if target.startswith("./") else target
            resolved = os.path.join(root, ref)
        elif target.startswith("../code-lang/"):
            resolved = os.path.normpath(os.path.join(base_dir, target))
        elif in_code_lang and target.endswith(".md") and not os.path.isabs(target):
            resolved = os.path.normpath(os.path.join(base_dir, target))
        elif in_protocols and target.startswith("./") and target.endswith(".md"):
            resolved = os.path.normpath(os.path.join(base_dir, target))
        else:
            continue
        if not os.path.exists(resolved):
            errors.append(
                f"{rel}: dangling link {raw!r} -> {os.path.relpath(resolved, root)}"
            )
    for m in inline_re.finditer(text):
        ref = m.group(1)
        if ref.startswith("workflows/"):
            errors.append(
                f"{rel}: inline-code path points into retired 'workflows/' directory: `{ref}`"
            )
            continue
        resolved = os.path.join(root, ref)
        if not os.path.exists(resolved):
            errors.append(
                f"{rel}: dangling inline-code path `{ref}` -> {ref}"
            )
    if in_code_lang:
        for m in relative_inline_re.finditer(text):
            ref = m.group(1)
            resolved = os.path.normpath(os.path.join(base_dir, ref))
            if not os.path.exists(resolved):
                errors.append(f"{rel}: dangling inline-code path `{ref}` -> "
                              f"{os.path.relpath(resolved, root)}")
    return errors


targets = [
    (p, agents_dir, False) for p in sorted(glob.glob(os.path.join(agents_dir, "*.md")))
] + [
    (p, protocols_dir, True) for p in sorted(glob.glob(os.path.join(protocols_dir, "*.md")))
] + [
    (p, os.path.dirname(p), False)
    for p in sorted(glob.glob(os.path.join(code_lang_dir, "**", "*.md"), recursive=True))
]
# Include the readme's agent, protocol, and code-lang links.
readme = os.path.join(root, "readme.md")
if os.path.isfile(readme):
    targets.append((readme, root, False))

for path, base_dir, in_protocols in targets:
    errs = scan_file(path, base_dir, in_protocols)
    if errs:
        for e in errs:
            print(f"ERROR: {e}")
    else:
        print(f"ok: {os.path.relpath(path, root)}")
PY
)"
  while IFS= read -r line; do
    case "${line}" in
      ERROR:*) err "${line#ERROR: }" ;;
      WARN:*)  warn "${line#WARN: }" ;;
      *)       [ -n "${line}" ] && echo "${line}" ;;
    esac
  done <<< "${PY_OUT}"
fi

# --- 14. return checker unit tests --------------------------------------------

echo "== [14/15] child-return checker unit tests =="
if ! "${PYTHON_BIN}" -B "${SCRIPT_DIR}/test_check_subagent_return.py"; then
  err "child-return checker unit tests failed"
fi

# --- 15. schema-agent return examples -----------------------------------------

echo "== [15/15] Structured Return JSON examples =="
if ! "${PYTHON_BIN}" -B "${SCRIPT_DIR}/check-subagent-return.py" --check-examples; then
  err "schema-agent Structured Return examples could not be verified"
fi

# --- summary -----------------------------------------------------------------

echo ""
if [ "${ERRORS}" -gt 0 ]; then
  echo "FAIL: ${ERRORS} error(s), ${WARNINGS} warning(s)" >&2
  exit 1
fi
echo "PASS: 0 errors, ${WARNINGS} warning(s)"
exit 0
