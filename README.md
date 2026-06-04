# AIDEN Tasks — Claude Code plugin

Talk to Claude to create/find/update your AIDEN (clicktrackerx.com) tasks, with
optional automatic session logging.

## What it installs
- **`/aiden-tasks:aiden`** slash command → "create/find/update my tasks". This is
  the main entry point and it works on **every** session type (see auth below).
- **MCP server** `aiden-tasks` → the `aiden-task-*` / `aiden-project-*` tools,
  served at `https://clicktrackerx.com/mcp/aiden-tasks`. **See the auth note below —
  the OAuth/browser path only works when the server is registered with
  `claude mcp add`, not from the plugin bundle.**
- **Session hooks** (SessionStart / Stop / SessionEnd) for automatic per-branch
  task logging. Opt-in — require a per-user key (see "Auth").

## Install (one-time)
```
/plugin marketplace add lajpat14/aiden-tasks-plugin
/plugin install aiden-tasks@aiden
/reload-plugins
```
> **Updating later:** a `git push` to the marketplace repo does NOT auto-update an
> installed session. In each session run `/plugin marketplace update aiden` then
> `/plugin update aiden-tasks@aiden` (or uninstall + reinstall), and **fully restart
> Claude Code** (`/reload-plugins` reconnects the transport but does not re-pull).

## Auth — pick the path for your session
Claude Code does **not** drive the OAuth browser flow for an OAuth HTTP MCP server
that is bundled in a *plugin's* `.mcp.json` (see anthropics/claude-code#36307) — so
the `aiden-task-*` tools may show up empty/absent if you rely on the plugin bundle
alone. Use one of these instead:

### A) Local sessions — register the server yourself (browser OAuth works)
```
claude mcp add --transport http aiden-tasks https://clicktrackerx.com/mcp/aiden-tasks
```
Then in a session: `/mcp` → **aiden-tasks** → **Authenticate** → sign in once. The
tools then list and work. (This is the same URL the plugin points at; registering it
via `claude mcp add` is what makes Claude Code run the OAuth flow.)

### B) Remote sessions, or no browser — per-user key (no OAuth, no loopback)
A remote session can't capture the OAuth `localhost` callback, so use the key path:
1. clicktrackerx.com → **Profile → Security → Claude Session Key → Generate**.
2. Export in your shell: `AIDEN_AGENT_BASE_URL`, `AIDEN_AGENT_KEY_PREFIX`,
   `AIDEN_AGENT_HMAC_SECRET`.
3. Run `/aiden-tasks:aiden` — it uses the bundled `scripts/aiden-task-cli.sh`
   (browser-free, HMAC-signed) for project/task list/create/update. The session
   hooks also use this key. **This path needs no MCP tools and works everywhere.**

## Project/task awareness (per-repo binding)
Run `/aiden-tasks:aiden` in a repo. The **first time** (no binding yet) it shows
your AIDEN projects and lets you **pick an existing project or create one**, then
creates/selects a task in it. It records the choice in a per-repo file
**`.aiden/task.json`** (project + task ids/names — **no secrets**). After that,
every `/aiden` call and every session heartbeat auto-attaches to that task/project
— no re-picking. `.aiden/` is local state; add it to your repo's `.gitignore`
(the command does this for you). Delete `.aiden/task.json` to re-bind.

Backing this: `aiden-project-list` / `aiden-project-create` (+ a `project_id` option
on task create/update) on the MCP path, or the matching `projects-list` /
`projects-create` / `tasks-*` subcommands of `scripts/aiden-task-cli.sh` on the
key path — `/aiden` uses whichever your session has.

## Sharing, assignment & teams
From chat you can also surface org users and assign/share work, and manage teams:
- **Share/assign:** "share project X with Priya" → the command resolves the user
  (`aiden-user-list` / `users-list`), confirms, and assigns
  (`aiden-task-assign` / `assign <user_id> --task|--project`). The assignee sees it
  in their My Work + activity (no external channel ping from this command).
- **Teams:** create a team, add members, and put a project under a team
  (`aiden-team-create`, `aiden-team-add-member`, `aiden-project-assign-team`, or the
  matching `team-create` / `team-add-member` / `project-assign-team` CLI subcommands).
All org-scoped and permission-checked server-side (you need the relevant
tasks/teams permissions; everything is confined to your organization).

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
