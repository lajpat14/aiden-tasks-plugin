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
#   aiden-task-cli.sh users-list [search]                       # surface org users
#   aiden-task-cli.sh assign <user_id> --task <id> | --project <id>   # share/assign
#   aiden-task-cli.sh teams-list
#   aiden-task-cli.sh team-create <name> [description]
#   aiden-task-cli.sh team-add-member <team_id> <user_id> [role]
#   aiden-task-cli.sh project-assign-team <project_id> <team_id|0>
#   aiden-task-cli.sh vault-list                       # accessible vaults (+project_id)
#   aiden-task-cli.sh vault-items <vault_id>           # masked items (NO secrets)
#   aiden-task-cli.sh vault-get <item_id>              # DECRYPTED secret (audited)
#
# The vault-* commands hit /api/agent/vault (gated server-side by
# vault.agent.access; vault-get additionally needs vault.secrets.reveal and is
# audited + throttled). vault-get prints the secret to stdout — the caller is
# responsible for handling it safely (never log it, never commit it).
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

  users-list)
    # GET with optional ?q= (query not part of the signed path — server signs path()).
    Q="${1:-}"
    ts="$(date +%s)"
    sig="$(printf '%s' "GET/api/agent/users${ts}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"
    url="${BASE_URL%/}/api/agent/users"
    [[ -n "$Q" ]] && url="${url}?q=$(jq -rn --arg q "$Q" '$q|@uri')"
    resp="$(curl -sS -m 20 -w '\n%{http_code}' -X GET "$url" \
      -H "Accept: application/json" -H "X-Aiden-Key: ${PREFIX}" -H "X-Timestamp: ${ts}" -H "X-Signature: ${sig}")" \
      || die "request failed (network)"
    code="$(printf '%s' "$resp" | tail -n1)"; printf '%s\n' "$(printf '%s' "$resp" | sed '$d')"
    [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 1; }
    ;;

  assign)
    # assign <user_id> (--task <id> | --project <id>)
    [[ $# -ge 1 ]] || die "usage: assign <user_id> --task <id> | --project <id>"
    UID_="$1"; shift; require_numeric "$UID_" "user_id"
    TID=""; PID=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --task)    [[ $# -ge 2 ]] || die "--task needs a value"; TID="$2"; shift 2;;
        --project) [[ $# -ge 2 ]] || die "--project needs a value"; PID="$2"; shift 2;;
        *) die "unknown flag '$1' for assign";;
      esac
    done
    [[ -n "$TID" ]] && require_numeric "$TID" "--task"
    [[ -n "$PID" ]] && require_numeric "$PID" "--project"
    [[ -n "$TID" || -n "$PID" ]] || die "provide --task <id> or --project <id>"
    BODY="$(jq -cn --arg u "$UID_" --arg t "$TID" --arg p "$PID" \
      '{user_id:($u|tonumber)}
        + (if $t!="" then {task_id:($t|tonumber)} else {} end)
        + (if $p!="" then {project_id:($p|tonumber)} else {} end)')"
    signed_request POST /api/agent/assign "$BODY"
    ;;

  teams-list)
    ts="$(date +%s)"
    sig="$(printf '%s' "GET/api/agent/teams${ts}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"
    resp="$(curl -sS -m 20 -w '\n%{http_code}' -X GET "${BASE_URL%/}/api/agent/teams" \
      -H "Accept: application/json" -H "X-Aiden-Key: ${PREFIX}" -H "X-Timestamp: ${ts}" -H "X-Signature: ${sig}")" \
      || die "request failed (network)"
    code="$(printf '%s' "$resp" | tail -n1)"; printf '%s\n' "$(printf '%s' "$resp" | sed '$d')"
    [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 1; }
    ;;

  team-create)
    [[ $# -ge 1 && -n "${1:-}" ]] || die "name required: team-create <name> [description]"
    NAME="$1"; DESC="${2:-}"
    BODY="$(jq -cn --arg n "$NAME" --arg d "$DESC" '{name:$n} + (if $d!="" then {description:$d} else {} end)')"
    signed_request POST /api/agent/teams "$BODY"
    ;;

  team-add-member)
    # team-add-member <team_id> <user_id> [role]
    [[ $# -ge 2 ]] || die "usage: team-add-member <team_id> <user_id> [role]"
    TEAM="$1"; MUID="$2"; ROLE="${3:-}"
    require_numeric "$TEAM" "team_id"; require_numeric "$MUID" "user_id"
    BODY="$(jq -cn --arg u "$MUID" --arg r "$ROLE" '{user_id:($u|tonumber)} + (if $r!="" then {role:$r} else {} end)')"
    signed_request POST "/api/agent/teams/${TEAM}/members" "$BODY"
    ;;

  project-assign-team)
    # project-assign-team <project_id> <team_id|0>
    [[ $# -ge 2 ]] || die "usage: project-assign-team <project_id> <team_id (0 to unassign)>"
    PROJ="$1"; TEAM="$2"
    require_numeric "$PROJ" "project_id"; require_numeric "$TEAM" "team_id"
    if [[ "$TEAM" == "0" ]]; then
      BODY='{"team_id":null}'
    else
      BODY="$(jq -cn --arg t "$TEAM" '{team_id:($t|tonumber)}')"
    fi
    signed_request PATCH "/api/agent/projects/${PROJ}" "$BODY"
    ;;

  vault-list)
    # GET, no body — mirror teams-list. Returns {success,data:[{id,name,type,project_id,items_count}]}.
    ts="$(date +%s)"
    sig="$(printf '%s' "GET/api/agent/vault${ts}" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')"
    resp="$(curl -sS -m 20 -w '\n%{http_code}' -X GET "${BASE_URL%/}/api/agent/vault" \
      -H "Accept: application/json" -H "X-Aiden-Key: ${PREFIX}" -H "X-Timestamp: ${ts}" -H "X-Signature: ${sig}")" \
      || die "request failed (network)"
    code="$(printf '%s' "$resp" | tail -n1)"; printf '%s\n' "$(printf '%s' "$resp" | sed '$d')"
    [[ "$code" =~ ^2 ]] || { echo "HTTP $code" >&2; exit 1; }
    ;;

  vault-items)
    # vault-items <vault_id> — masked item list (NO secrets). GET, empty body.
    [[ $# -ge 1 && -n "${1:-}" ]] || die "vault_id required: vault-items <vault_id>"
    require_numeric "$1" "vault_id"
    signed_request GET "/api/agent/vault/${1}/items" ""
    ;;

  vault-get)
    # vault-get <item_id> — DECRYPTED secret (audited, gated vault.secrets.reveal,
    # throttled 30/min server-side). The secret is in data.secret_fields. GET, empty body.
    [[ $# -ge 1 && -n "${1:-}" ]] || die "item_id required: vault-get <item_id>"
    require_numeric "$1" "item_id"
    signed_request GET "/api/agent/vault/items/${1}" ""
    ;;

  *)
    die "unknown command: '$CMD' (projects-list|projects-create|tasks-find|tasks-create|tasks-update|users-list|assign|teams-list|team-create|team-add-member|project-assign-team|vault-list|vault-items|vault-get)"
    ;;
esac
