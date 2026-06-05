#!/usr/bin/env bash
#
# aiden-vault-cleanup.sh — removes any ephemeral secret material the /aiden-vault
# command wrote during a session: temporary SSH deploy-key files under .aiden/keys/,
# a gitignored .aiden/.env.local, and the per-repo git credential cache.
#
# Wired as a SessionEnd hook (hooks/hooks.json). Fire-and-forget: NEVER fails the
# session — all paths exit 0. Reads the hook JSON from stdin to find the cwd.
#
# This script only ever DELETES local ephemeral files; it never touches the vault.

set -uo pipefail

# Resolve the working directory from the hook JSON (fallback to $PWD).
HOOK_JSON="$(cat 2>/dev/null || true)"
CWD=""
if command -v jq >/dev/null 2>&1; then
  CWD="$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[[ -z "$CWD" ]] && CWD="$(pwd)"

# Scope to the git repo root when available, else the cwd.
REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && REPO_ROOT="$CWD"

# Refuse to operate on an empty or filesystem-root path — never `rm -f /.aiden/keys/*`.
case "$REPO_ROOT" in ""|"/") exit 0 ;; esac

# Remove ephemeral key files and the local env file (only inside .aiden/, which is
# gitignored — so we never touch tracked files).
rm -f "${REPO_ROOT}/.aiden/keys/"* 2>/dev/null || true
rmdir "${REPO_ROOT}/.aiden/keys" 2>/dev/null || true
rm -f "${REPO_ROOT}/.aiden/.env.local" 2>/dev/null || true

# Flush the per-repo in-memory git credential cache, if one was started.
git -C "$REPO_ROOT" credential-cache exit 2>/dev/null || true

exit 0
