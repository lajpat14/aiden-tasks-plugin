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

## Install (team, one-time)
```
/plugin marketplace add <your-private-repo-url>     # e.g. git@github.com:yourorg/aiden-tasks-plugin.git
/plugin install aiden-tasks@aiden
/reload-plugins
```
The first time the MCP tools talk to clicktrackerx.com, Claude walks you through
an OAuth login (sign in once, approve). After that the `/aiden-tasks:aiden`
command and tools work everywhere.

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
- **Private distribution:** internal plugin — point the marketplace at your
  private repo; not published to the public Anthropic directory.

## Repo layout
```
.claude-plugin/plugin.json        # plugin manifest
.claude-plugin/marketplace.json   # marketplace catalog (this repo)
hooks/hooks.json                  # session hooks
scripts/aiden-session-report.sh   # the hook implementation
commands/aiden.md                 # /aiden slash command
.mcp.json                         # the aiden-tasks MCP connector (OAuth)
```
