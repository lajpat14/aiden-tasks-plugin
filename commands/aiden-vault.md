---
description: Retrieve a task/project credential from the AIDEN vault and apply it safely (git push, deploy key, env)
---

You fetch a credential from the user's AIDEN vault and apply it for a coding-session
job — **without ever leaking it**. The vault is the SSoT for secrets; this command is a
thin, audited transport over the already-gated vault endpoints. You never invent, store,
or persist a secret beyond its ephemeral use.

Request: $ARGUMENTS

## Absolute rules (read first — these override convenience)

- **Never** write a secret to `.aiden/task.json`, to chat, to a task note/heartbeat, to
  `CLAUDE.md`, or into any command that gets logged.
- **Never** pass a secret as a command-line argument (it shows in `ps` and shell history).
  Feed secrets via **stdin / here-strings / process substitution** only.
- **Never** enable `set -x` / shell tracing while a secret is in scope, and never `echo`
  `secret_fields`. When reporting back, name an item by its **id + name** only.
- **Never** put a token in a git remote URL (`https://TOKEN@github.com/...`) or run
  `git remote set-url` with a token — it persists in `.git/config` and `git reflog`.
- Any on-disk secret goes **only** under the gitignored `.aiden/` tree, created with
  `umask 077` and `chmod 600`. Never write to `.env` (that's the server SSoT) — and never
  a repo-root `.env.local`. If a file is unavoidable, use `.aiden/.env.local` (under the
  gitignored `.aiden/` tree, so it can't be committed and SessionEnd cleanup removes it).

## Step 0 — Pick the transport (same rule as `/aiden`)

- If the `aiden-vault-list` / `aiden-vault-items` / `aiden-vault-get` **MCP tools** are
  available to you (interactive session with OAuth), use them.
- Otherwise (remote/SSH session, OAuth can't complete, or MCP tools absent) use the
  **Key CLI**: `SH="${CLAUDE_PLUGIN_ROOT}/scripts/aiden-task-cli.sh"`
  - `"$SH" vault-list`            → `{success,data:[{id,name,type,project_id,items_count}]}`
  - `"$SH" vault-items <vault_id>` → `{success,data:[ masked items ]}` (no secrets)
  - `"$SH" vault-get <item_id>`    → `{success,data:{id,type,name,url,host,username,secret_fields,notes}}`
  - Needs `AIDEN_AGENT_BASE_URL` / `AIDEN_AGENT_KEY_PREFIX` / `AIDEN_AGENT_HMAC_SECRET`
    (generate at clicktrackerx.com → Profile → Security → Claude Session Key).
- If neither the MCP tools nor the `AIDEN_AGENT_*` env vars are present, **stop** and tell
  the user to set the key — do not attempt the OAuth flow on a remote session.

Errors the CLI/tools surface (handle them, don't retry blindly):
`403` → the user lacks `vault.secrets.reveal` (list/items still work); `404` → no access
or no such item (the server returns 404 for both, on purpose — no enumeration); `429` →
reveal throttle (30/min) hit, wait and retry.

## Step 1 — Resolve which vault to use

1. Read `.aiden/task.json` at the repo root. If it has a `vault` block with `items`, you
   already know the `vault_id` and the item to use — **skip discovery, go to Step 3**.
2. Otherwise call `vault-list`. Read `project_id` from `.aiden/task.json`.
   - Prefer the vault whose `project_id` **equals** the bound project's id (that's the
     project's credential vault).
   - If there's no project binding, or no project vault matches, show the user the
     accessible vaults (`name` + `id` + `type`) and **ask which** — never guess.

## Step 2 — Choose the item

1. Call `vault-items <vault_id>` (masked — no secret values).
2. Match the user's intent to an item by `type` + `name`:
   - **git push token** → an `api_key` or `login` item (token lives in `secret_fields`).
   - **SSH deploy key** → a `server` item whose secret has a `private_key` field.
   - **deploy / API credentials** → an `api_key` item.
3. If more than one plausibly matches, **list them and ask** — don't assume.
4. Confirm the chosen item with the user by **id + name** (never reveal yet).

## Step 3 — Reveal exactly one item

Call `vault-get <item_id>`. The payload:
- `data.username`          → e.g. the git user
- `data.secret_fields`     → object: token in `.password` or `.token`; SSH key in `.private_key`
- `data.host`              → the target host (may be null; if so, derive it from `data.url`)
- `data.url`               → full URL when present

Reveal **only the one item** you need. Every reveal is audited server-side (actor=api).

## Step 4 — Apply it safely (pick the flow that matches the job)

### A. Git push without an inline token (credential cache)
Use git's in-memory credential cache so the token never touches disk, the URL, or the reflog.
```bash
# 15-min in-memory cache, scoped to THIS repo:
git config --local credential.helper 'cache --timeout=900'
# Feed the credential via stdin (NEVER as an argument). Build the host/user/token
# from the revealed payload and pipe a credential description to git:
printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' \
  "$HOST" "$GIT_USER" "$TOKEN" | git credential approve
# Now an ordinary push works for the cache TTL — no token in argv:
git push
```
Build `$HOST/$GIT_USER/$TOKEN` from the revealed JSON **inside the same Bash call** (don't
echo them in a separate command). Do not export them to the shell beyond this block.

### B. SSH deploy key
Create the key file **0600 atomically** — set `umask` and write in the SAME subshell so the
file is never world-readable for any window (don't split umask / write / chmod across
separate Bash calls). Run this as ONE Bash invocation:
```bash
KEY=".aiden/keys/${ITEM_ID}"
mkdir -p .aiden/keys
# umask + write together (subshell) so the file is born 0600; printf via stdin, not argv:
( umask 077; printf '%s\n' "$PRIVATE_KEY" > "$KEY" )
chmod 600 "$KEY"   # defensive — the subshell umask already restricts it
# Use it for ONE operation; SessionEnd cleanup removes any leftover key file:
GIT_SSH_COMMAND="ssh -i \"$(pwd)/$KEY\" -o IdentitiesOnly=yes" git push
```
`.aiden/` is already gitignored, so the key can never be committed. Tell the user the path
and that it will be removed at session end (or `rm -f "$KEY"` right after use).

### C. Ephemeral env / `.aiden/.env.local`
- For a single build/deploy command, export the value into **that command's** environment
  only (inline, e.g. `API_KEY="$VALUE" some-deploy-command`) — don't persist it.
- If a file is genuinely required, write `.aiden/.env.local` (NOT a repo-root `.env.local`,
  and never `.env`) so it sits under the gitignored `.aiden/` tree and SessionEnd cleanup
  removes it. Create it 0600 — remove any pre-existing file first, since `umask` only
  affects newly-created files (a stale `0644` file would otherwise keep its loose perms):
  ```bash
  rm -f .aiden/.env.local
  ( umask 077; printf 'API_KEY=%s\n' "$VALUE" > .aiden/.env.local )
  chmod 600 .aiden/.env.local   # defensive — reset mode in case the file pre-existed
  ```

### D. Read-only
If the user just wants the value (to paste elsewhere themselves), reveal it and hand it to
them directly. Still don't write it to any file or log.

## Step 5 — Remember the choice (non-secret pointer only)

After a successful reveal+apply, record a pointer in `.aiden/task.json` so the next run skips
discovery. **Ids and labels only — never the secret.** Merge a `vault` block into the existing
file (don't clobber the task/project keys):
```json
"vault": {
  "vault_id": 12,
  "items": [
    { "item_id": 1234, "label": "git-push",  "purpose": "git_push" }
  ]
}
```
Ensure `.aiden/` is gitignored (the `/aiden` first-run setup normally does this; if missing,
from the repo root: `grep -qxF '.aiden/' .gitignore 2>/dev/null || printf '\n.aiden/\n' >> .gitignore`).

## Step 6 — Report back

Tell the user: which item (id + name) you used, which flow you applied (cache / deploy key /
env), that the secret was **not** persisted anywhere committable, and how it expires (cache
TTL, or the key file path that SessionEnd cleanup will remove). Never print the secret value.
