# AIDEN Tasks — Claude Code plugin

Talk to Claude to create/find/update your AIDEN (clicktrackerx.com) tasks, with
optional automatic session logging.

## What it installs
- **MCP server** `aiden-tasks` → the `aiden-task-*` tools (list/find/create/update/
  status), connected to `https://clicktrackerx.com/mcp/aiden-tasks` over **OAuth**
  (you log in once in Claude; no key to copy). **Works right after install + login.**
- **`/aiden-tasks:aiden`** slash command → "create/find/update my tasks".
- **Session hooks** (SessionStart / Stop / SessionEnd) for automatic per-branch
  task logging. **Opt-in — these require a per-user key (see "Enable auto-logging"),
  because a shell hook can't perform the OAuth login the MCP tools use.**

## Install (one-time)
```
/plugin marketplace add lajpat14/aiden-tasks-plugin
/plugin install aiden-tasks@aiden
/reload-plugins
```
The first time the MCP tools talk to clicktrackerx.com, Claude walks you through
an OAuth login (sign in once, approve) — you need a clicktrackerx.com account.
After that the `/aiden-tasks:aiden` command and tools work everywhere.

## Project/task awareness (per-repo binding)
Run `/aiden-tasks:aiden` in a repo. The **first time** (no binding yet) it shows
your AIDEN projects and lets you **pick an existing project or create one**, then
creates/selects a task in it. It records the choice in a per-repo file
**`.aiden/task.json`** (project + task ids/names — **no secrets**). After that,
every `/aiden` call and every session heartbeat auto-attaches to that task/project
— no re-picking. `.aiden/` is local state; add it to your repo's `.gitignore`
(the command does this for you). Delete `.aiden/task.json` to re-bind.

New MCP tools backing this: `aiden-project-list`, `aiden-project-create`, and a
`project_id` option on `aiden-task-create` / `aiden-task-update`.

## Enable auto-logging hooks (optional)
The hooks only fire when a per-user key is present in your shell (OAuth does not
feed them). To turn them on:
1. clicktrackerx.com → **Profile → Security → Claude Session Key → Generate**.
2. Export the printed block in your shell profile (`~/.bashrc` / `~/.zshrc`):
   `AIDEN_AGENT_BASE_URL`, `AIDEN_AGENT_KEY_PREFIX`, `AIDEN_AGENT_HMAC_SECRET`.
Until set, the hooks silently no-op (they never disrupt a session). The `/aiden`
command + MCP tools work without this.

## Notes
- **Requirements on your machine (for the hooks):** `git`, `curl`, `openssl`, `jq`.
  Without `jq`, per-repo binding is ignored and session hooks fall back to
  per-branch auto-create (the `/aiden` command + MCP tools still work).
- **Who can use it:** anyone — but actual task access requires logging in with a
  **clicktrackerx.com account** (OAuth) or a per-user key. Installing the plugin
  alone grants nothing.
- **Security:** this repo contains no secrets — only config + a signing script
  that reads YOUR locally-set env vars. The server enforces all auth.

## Repo layout
```
.claude-plugin/plugin.json        # plugin manifest
.claude-plugin/marketplace.json   # marketplace catalog (this repo)
hooks/hooks.json                  # session hooks
scripts/aiden-session-report.sh   # the hook implementation (binding-aware)
commands/aiden.md                 # /aiden slash command (project/task picker)
.mcp.json                         # the aiden-tasks MCP connector (OAuth)
```

### `.aiden/task.json` (written in YOUR repo, not this one)
The `/aiden` picker writes the binding into the repo you're working in:
```json
{
  "base_url": "https://clicktrackerx.com",
  "project_id": 7,
  "project_name": "Platform UI",
  "task_id": 1104561,
  "task_title": "Make the plugin project/task-aware",
  "branch": "feat/foo",
  "bound_at": "2026-06-05T12:00:00Z"
}
```
Local state only — gitignore it; it holds ids/names, never a key or secret.
