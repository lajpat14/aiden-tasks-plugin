#!/usr/bin/env bash
#
# aiden-task-cli.sh — browser-free CLI for the AIDEN task/project REST surface,
# for use by the /aiden command on REMOTE sessions where the OAuth/MCP loopback
# redirect can't be captured. Signs each request with YOUR per-user key (HMAC),
# exactly like aiden-session-report.sh:
#     X-Signature = HMAC-SHA256(METHOD + PATH + TIMESTAMP + rawBody, SECRET)
#
# Required env (same as the hooks — generate at Profile -> Security -> Claude
# Session Key, then export in your shell profile):
#     AIDEN_AGENT_BASE_URL     e.g. https://clicktrackerx.com
#     AIDEN_AGENT_KEY_PREFIX   your public key prefix (aidk_...)
#     AIDEN_AGENT_HMAC_SECRET  your personal secret (signs the request)
#
# Usage:
#   aiden-task-cli.sh projects-list [--include-completed]
#   aiden-task-cli.sh projects-create <name> [description]
#   aiden-task-cli.sh tasks-find <query>
#   aiden-task-cli.sh tasks-create <title> [project_id] [summary]
#   aiden-task-cli.sh tasks-update <task_id> [--status S] [--progress N] \
#                                  [--current "..."] [--next "..."] \
#                                  [--note "..."] [--project-id ID]
#
# Prints the JSON response to stdout. Exits non-zero on transport/HTTP error so
# the caller (the /aiden command) can react. Requires: curl, openssl, jq.

set -uo pipefail

BASE_URL="${AIDEN_AGENT_BASE_URL:-}"
PREFIX="${AIDEN_AGENT_KEY_PREFIX:-}"
SECRET="${AIDEN_AGENT_HMAC_SECRET:-}"

die() { echo "{\"success\":false,\"error\":\"$1\"}" >&2; exit 2; }
# Accept a plain positive integer of sane length (avoids jq tonumber emitting
# scientific notation for absurdly long digit strings).
require_numeric() { [[ "$1" =~ ^[0-9]{1,15}$ ]] || die "$2 must be a number, got '$1'"; }

[[ -z "$BASE_URL" || -z "$PREFIX" || -z "$SECRET" ]] && \
  die "AIDEN_AGENT_BASE_URL / AIDEN_AGENT_KEY_PREFIX / AIDEN_AGENT_HMAC_SECRET not set. Generate a key at Profile -> Security -> Claude Session Key and export them."
command -v jq      >/dev/null 2>&1 || die "jq is required"
command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v curl    >/dev/null 2>&1 || die "curl is required"

# signed_request METHOD PATH BODY  → prints response body, exits non-zero on HTTP >=400
signed_request() {
  local method="$1" path="$2" body="${3:-}"
  local ts sig resp code
  ts="$(date +%s)"
  sig="$(printf '%s' "${method}${path}${ts}${body}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"

  local args=(-sS -m 20 -w '\n%{http_code}' -X "$method" "${BASE_URL%/}${path}"
    -H "Accept: application/json"
    -H "X-Aiden-Key: ${PREFIX}"
    -H "X-Timestamp: ${ts}"
    -H "X-Signature: ${sig}")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "$body")
  fi

  resp="$(curl "${args[@]}")" || die "request failed (network)"
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  printf '%s\n' "$body"
  [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 1; }
}

CMD="${1:-}"; shift || true

case "$CMD" in
  projects-list)
    # GET with empty body; the ?include_completed query param is NOT part of the
    # signed path (server signs path() without query string), so pass it as a
    # query the controller validates, while signing the bare path.
    QS=""; [[ "${1:-}" == "--include-completed" ]] && QS="?include_completed=1"
    # Sign the path WITHOUT query (matches server: '/'.ltrim(request->path())).
    ts="$(date +%s)"
    sig="$(printf '%s' "GET/api/agent/projects${ts}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"
    resp="$(curl -sS -m 20 -w '\n%{http_code}' -X GET "${BASE_URL%/}/api/agent/projects${QS}" \
      -H "Accept: application/json" -H "X-Aiden-Key: ${PREFIX}" -H "X-Timestamp: ${ts}" -H "X-Signature: ${sig}")" \
      || die "request failed (network)"
    code="$(printf '%s' "$resp" | tail -n1)"; printf '%s\n' "$(printf '%s' "$resp" | sed '$d')"
    [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 1; }
    ;;
  projects-create)
    [[ $# -ge 1 && -n "${1:-}" ]] || die "project name required: projects-create <name> [description]"
    NAME="$1"; DESC="${2:-}"
    BODY="$(jq -cn --arg n "$NAME" --arg d "$DESC" '{name:$n} + (if $d!="" then {description:$d} else {} end)')"
    signed_request POST /api/agent/projects "$BODY"
    ;;
  tasks-find)
    [[ $# -ge 1 && -n "${1:-}" ]] || die "query required: tasks-find <query>"
    BODY="$(jq -cn --arg q "$1" '{query:$q}')"
    signed_request POST /api/agent/tasks/find "$BODY"
    ;;
  tasks-create)
    [[ $# -ge 1 && -n "${1:-}" ]] || die "title required: tasks-create <title> [project_id] [summary]"
    TITLE="$1"; PID="${2:-}"; SUMMARY="${3:-}"
    [[ -n "$PID" ]] && require_numeric "$PID" "project_id"
    BODY="$(jq -cn --arg t "$TITLE" --arg s "$SUMMARY" --arg p "$PID" \
      '{title:$t}
        + (if $s!="" then {summary:$s} else {} end)
        + (if $p!="" then {project_id:($p|tonumber)} else {} end)')"
    signed_request POST /api/agent/tasks/create "$BODY"
    ;;
  tasks-update)
    [[ $# -ge 1 && -n "${1:-}" ]] || die "task_id required: tasks-update <task_id> [--status S] [--progress N] [--current ..] [--next ..] [--note ..] [--project-id ID]"
    TID="$1"; shift
    require_numeric "$TID" "task_id"
    STATUS=""; PROGRESS=""; CURRENT=""; NEXT=""; NOTE=""; PROJECT_ID=""
    # Consume flags one at a time; a flag needs a following value or we die
    # (never blind `shift 2`, which can fail silently and loop forever).
    while [[ $# -gt 0 ]]; do
      flag="$1"; shift
      case "$flag" in
        --status|--progress|--current|--next|--note|--project-id)
          [[ $# -ge 1 ]] || die "$flag requires a value"
          val="$1"; shift
          case "$flag" in
            --status)     STATUS="$val";;
            --progress)   PROGRESS="$val";;
            --current)    CURRENT="$val";;
            --next)       NEXT="$val";;
            --note)       NOTE="$val";;
            --project-id) PROJECT_ID="$val";;
          esac
          ;;
        *) die "unknown flag '$flag' for tasks-update";;
      esac
    done
    [[ -n "$PROGRESS" ]]   && require_numeric "$PROGRESS" "--progress"
    [[ -n "$PROJECT_ID" ]] && require_numeric "$PROJECT_ID" "--project-id"
    BODY="$(jq -cn --arg tid "$TID" --arg st "$STATUS" --arg pr "$PROGRESS" \
                   --arg cur "$CURRENT" --arg nx "$NEXT" --arg nt "$NOTE" --arg pid "$PROJECT_ID" \
      '{task_id:($tid|tonumber)}
        + (if $st!=""  then {status:$st} else {} end)
        + (if $pr!=""  then {progress_percentage:($pr|tonumber)} else {} end)
        + (if $cur!="" then {current_status:$cur} else {} end)
        + (if $nx!=""  then {next_task:$nx} else {} end)
        + (if $nt!=""  then {note:$nt} else {} end)
        + (if $pid!="" then {project_id:($pid|tonumber)} else {} end)')"
    signed_request POST /api/agent/tasks/update "$BODY"
    ;;
  *)
    die "unknown command: '$CMD' (projects-list|projects-create|tasks-find|tasks-create|tasks-update)"
    ;;
esac
