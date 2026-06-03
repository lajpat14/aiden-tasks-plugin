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

# Build the JSON body ONCE. The exact bytes are both signed and sent.
# (Use jq to guarantee valid JSON + correct escaping.)
if command -v jq >/dev/null 2>&1; then
  BODY="$(jq -cn \
    --arg session_id "$SESSION_ID" \
    --arg git_branch "$BRANCH" \
    --arg cwd "$CWD" \
    '{session_id: $session_id, git_branch: $git_branch, cwd: $cwd}')"
else
  # Minimal fallback (branch/cwd only; no escaping of exotic chars).
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
