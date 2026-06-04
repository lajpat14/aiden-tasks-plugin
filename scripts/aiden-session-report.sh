#!/usr/bin/env bash
#
# aiden-session-report.sh — reports a Claude Code session event to the AIDEN
# task system (api/agent/sessions/*). Wired via .claude/settings.json hooks.
#
# Reads the hook JSON from stdin, derives the git branch, HMAC-signs the request
# (METHOD + PATH + TIMESTAMP + raw body) with YOUR personal secret, and POSTs it.
# The task is owned by you (the key identifies you — no org/email needed).
#
# Required env (export before Claude Code starts, e.g. in your shell profile).
# Generate these on your AIDEN profile page → Security → Claude Session Key:
#   AIDEN_AGENT_BASE_URL     e.g. https://clicktrackerx.com
#   AIDEN_AGENT_KEY_PREFIX   your public key prefix (aidk_...)
#   AIDEN_AGENT_HMAC_SECRET  your personal secret (signs the request)
#
# Usage (in settings.json hook): aiden-session-report.sh <endpoint>
#   where <endpoint> is one of: start | heartbeat | activity | end
#
# This script NEVER fails the session: all errors exit 0.

set -uo pipefail

ENDPOINT="${1:-heartbeat}"
BASE_URL="${AIDEN_AGENT_BASE_URL:-}"
PREFIX="${AIDEN_AGENT_KEY_PREFIX:-}"
SECRET="${AIDEN_AGENT_HMAC_SECRET:-}"

# Soft no-op if not configured — never disrupt the session.
if [[ -z "$BASE_URL" || -z "$PREFIX" || -z "$SECRET" ]]; then
  exit 0
fi

# Read the hook JSON from stdin.
HOOK_JSON="$(cat || true)"

# Extract fields with jq if available, else fall back to empty.
if command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // empty')"
  CWD="$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty')"
else
  SESSION_ID=""
  CWD="$(pwd)"
fi
[[ -z "$CWD" ]] && CWD="$(pwd)"

# Derive the git branch from the session's working directory.
BRANCH="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"

# Read the per-repo binding written by the `/aiden` first-run picker, if present.
# It binds this repo to one AIDEN task/project so heartbeats attach to it instead
# of branch-auto-creating a fresh task. Contains only ids/names — no secrets.
# Check the git repo root first, then the cwd.
BIND_TASK_ID=""
BIND_PROJECT_ID=""
if command -v jq >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  PREV_DIR=""
  for DIR in "$REPO_ROOT" "$CWD"; do
    [[ -z "$DIR" || "$DIR" == "$PREV_DIR" ]] && continue
    PREV_DIR="$DIR"
    BIND_FILE="${DIR}/.aiden/task.json"
    if [[ -f "$BIND_FILE" ]]; then
      BIND_TASK_ID="$(jq -r '.task_id // empty' "$BIND_FILE" 2>/dev/null || true)"
      BIND_PROJECT_ID="$(jq -r '.project_id // empty' "$BIND_FILE" 2>/dev/null || true)"
      [[ -n "$BIND_TASK_ID" || -n "$BIND_PROJECT_ID" ]] && break
    fi
  done
fi

# Build the JSON body ONCE. The exact bytes are both signed and sent.
# (Use jq to guarantee valid JSON + correct escaping.) Include the binding ids
# only when present and numeric — the server pins them to the caller's org and
# ignores anything cross-org, so an unbound repo keeps today's branch-auto-create.
if command -v jq >/dev/null 2>&1; then
  BODY="$(jq -cn \
    --arg session_id "$SESSION_ID" \
    --arg git_branch "$BRANCH" \
    --arg cwd "$CWD" \
    --arg task_id "$BIND_TASK_ID" \
    --arg project_id "$BIND_PROJECT_ID" \
    '{session_id: $session_id, git_branch: $git_branch, cwd: $cwd}
      + (if ($task_id    | test("^[0-9]+$")) then {task_id:    ($task_id    | tonumber)} else {} end)
      + (if ($project_id | test("^[0-9]+$")) then {project_id: ($project_id | tonumber)} else {} end)')"
else
  # Minimal fallback (branch/cwd only; no escaping of exotic chars; no binding).
  BODY="{\"git_branch\":\"${BRANCH}\",\"cwd\":\"${CWD}\"}"
fi

PATH_PART="/api/agent/sessions/${ENDPOINT}"
TS="$(date +%s)"
SIG="$(printf '%s' "POST${PATH_PART}${TS}${BODY}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"

# Fire-and-forget. --data-binary sends the EXACT bytes we signed (never -d,
# which mangles newlines). Short timeout so a slow server never stalls a turn.
curl -sS -m 5 -X POST "${BASE_URL%/}${PATH_PART}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Aiden-Key: ${PREFIX}" \
  -H "X-Timestamp: ${TS}" \
  -H "X-Signature: ${SIG}" \
  --data-binary "$BODY" >/dev/null 2>&1 || true

exit 0
