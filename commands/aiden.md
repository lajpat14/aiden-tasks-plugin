---
description: Create, find, or update your AIDEN (clicktrackerx.com) tasks
---

You manage the user's tasks in the AIDEN task system. There are TWO ways to call
it — pick the one that works in this session:

- **MCP tools** (preferred when available): `aiden-task-list`, `aiden-task-find`,
  `aiden-task-by-branch`, `aiden-task-create`, `aiden-task-update`,
  `aiden-task-status`, `aiden-session-link`, `aiden-project-list`,
  `aiden-project-create`, `aiden-project-assign-team`, `aiden-user-list`,
  `aiden-task-assign`, `aiden-team-list`, `aiden-team-members`,
  `aiden-team-create`, `aiden-team-add-member`. These need a one-time OAuth
  login in the browser. (`aiden-team-list` gives counts; `aiden-team-members`
  lists who is actually on a team — id/name/email/role.)
- **Key CLI** (browser-free — REQUIRED on remote sessions): the OAuth login uses a
  `http://localhost:.../callback` redirect that a **remote session can't capture**,
  so the MCP tools never finish auth there. In that case use the bundled script
  `"${CLAUDE_PLUGIN_ROOT}"/scripts/aiden-task-cli.sh`, which signs each request
  with the user's per-user key (no browser). It needs `AIDEN_AGENT_BASE_URL`,
  `AIDEN_AGENT_KEY_PREFIX`, `AIDEN_AGENT_HMAC_SECRET` in the environment (generate
  at clicktrackerx.com → Profile → Security → Claude Session Key).

**Decide the path first:** if the `aiden-task-*` MCP tools are available to you,
use them. Otherwise (they're absent, or a previous attempt to authenticate failed,
or this is a remote session), use the Key CLI. If neither the MCP tools nor the
`AIDEN_AGENT_*` env vars are present, tell the user to set the key env vars and
stop — do not attempt the OAuth flow on a remote session (it cannot complete).

### Key CLI command map (each prints JSON to stdout)
```
SH="${CLAUDE_PLUGIN_ROOT}/scripts/aiden-task-cli.sh"
"$SH" projects-list [--include-completed]        # -> {data:{projects:[{id,name,status,tasks_count}]}}
"$SH" projects-create "<name>" "[description]"   # -> {data:{id,name,...}}
"$SH" tasks-find "<query>"                        # -> {data:{tasks:[{id,title,...}]}}
"$SH" tasks-create "<title>" "[project_id]" "[summary]"
"$SH" tasks-update <task_id> --status in_progress --progress 30 \
      --current "..." --next "..." --note "..." --project-id <id>
"$SH" users-list "<search>"                       # -> {data:{users:[{id,name,email}]}}
"$SH" assign <user_id> --task <id>                # share/assign one task
"$SH" assign <user_id> --project <id>             # assign all open tasks of a project
"$SH" teams-list                                  # -> {data:{teams:[{id,name,members_count}]}}
"$SH" team-create "<name>" "[description]"
"$SH" team-add-member <team_id> <user_id> [role]  # role: member|lead|manager
"$SH" project-assign-team <project_id> <team_id>  # team_id 0 to unassign
```
Use these in place of the matching `aiden-*` MCP tool wherever the steps below say
to call one. (There is no CLI equivalent of `aiden-task-by-branch`; on the CLI
path, skip the branch-reconcile step and rely on `tasks-find` instead.)

### Sharing / assigning to a registered user
When the user says "share <project/task> with <name>" or "assign … to <name>":
1. Resolve the name → call `aiden-user-list` / `users-list "<name>"`.
2. If 0 matches, tell the user; if >1, **list them and ask which** — never guess.
3. **Confirm the chosen user** (name + email) with the human before assigning.
4. Assign: `aiden-task-assign` (MCP) / `assign <user_id> --task|--project` (CLI).
5. Report back who was assigned to what. (The assignee sees it in their My Work +
   activity; external Slack/WhatsApp/Email pings are not sent by this command.)

### Teams
- "create a team <name>" → `team-create`; "add <name> to team <T>" → resolve the
  user (users-list), then `team-add-member <team_id> <user_id>`.
- "put project <P> under team <T>" → `team-list` to get the id, then
  `project-assign-team <project_id> <team_id>`.

Request: $ARGUMENTS

## Project/task awareness — do this FIRST, before handling the request

This repo can be **bound** to one AIDEN project + task via a per-repo file
`.aiden/task.json` at the repo root. Use it so the user never re-picks.

1. **Read `.aiden/task.json`** in the current repo root (use the Read/Bash tool).
   - **If it exists and has a `task_id`:** that is the active task. Operate on it
     directly (e.g. `aiden-task-update` by that id) — do NOT prompt for a project.
     You may briefly confirm "Working on task #<id> in project <project_name>".
   - **If it does NOT exist (first run in this repo):** run the **first-run setup**
     below before acting on the request.

2. **First-run setup (no binding yet):**
   a. **Reconcile first:** get the current git branch (`git branch --show-current`)
      and the origin remote (`git config --get remote.origin.url`), then call
      `aiden-task-by-branch` with **both** `git_branch` and `git_remote`. Passing
      the remote scopes the lookup to THIS repo, so a common branch name like
      `main` in another repo never resolves to the wrong task. The session hooks
      may have already auto-created a `"Session: <branch>"` task for this branch —
      if `found:true`, **reuse that task id** (don't create a duplicate); you'll
      just bind it to a project and optionally retitle it below.
   b. Call `aiden-project-list` to fetch the user's existing projects.
   c. **Show the user the list** (name + id + open task count) and ask them to
      either **pick an existing project** or **create a new one**. Wait for their
      choice — do not assume.
   d. If they choose to create: call `aiden-project-create` with the name they
      give → note the returned project id.
   e. Put the task in that project:
      - If step (a) found an existing branch task → `aiden-task-update` it with
        `project_id` set to the chosen project (and a clearer title via the
        request if appropriate).
      - Otherwise → `aiden-task-create` with `project_id` set, `git_branch` set
        to the current branch, and `git_remote` set to the origin URL (so future
        heartbeats attach to the right repo's task). If the user names an existing
        task instead, `aiden-task-find` it and reuse its id. `aiden-task-find`
        matches all the words in your query across title + description, so a
        partial phrase like "attribution alert" still finds the task.
   f. **Write the binding** to `.aiden/task.json` (create the `.aiden/` dir if
      needed) with this exact shape (use the REAL project id and task id — they
      are different numbers):
      ```json
      {
        "base_url": "https://clicktrackerx.com",
        "project_id": <the chosen project id>,
        "project_name": "<project name>",
        "task_id": <the task id>,
        "task_title": "<task title>",
        "branch": "<current git branch>",
        "bound_at": "<ISO-8601 timestamp>"
      }
      ```
   g. Gitignore the binding (it's local state — never commit it). Run, from the
      repo root:
      ```bash
      grep -qxF '.aiden/' .gitignore 2>/dev/null || printf '\n.aiden/\n' >> .gitignore
      ```
   h. Tell the user the task id + project it's now bound to.

## Handling the request (after awareness)
- To **continue the bound task**, act on it by id with `aiden-task-update`
  (current status / next step / progress) or `aiden-task-status` (status).
- To **find** a different task: `aiden-task-find` (keyword) or `aiden-task-list`.
- To **create** genuinely new work: `aiden-task-create` (pass `project_id` so it
  lands in the right project — discover ids with `aiden-project-list`).
- Always confirm back the task id + project + what changed.
- If no request was given and a binding exists, show the bound task's current
  state; otherwise run the first-run setup, then `aiden-task-list`.

Notes:
- `.aiden/task.json` holds only ids/names + base_url — **no secrets**. Safe to read.
- Never auto-edit the human-written `CLAUDE.md`; the machine binding lives only in
  `.aiden/task.json`.
