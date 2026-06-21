---
description: Create, find, or update your AIDEN (clicktrackerx.com) tasks
---

You manage the user's tasks in the AIDEN task system. There are TWO ways to call
it — pick the one that works in this session:

- **MCP tools** (preferred when available): `aiden-task-list`, `aiden-task-find`,
  `aiden-task-by-branch`, `aiden-task-create`, `aiden-task-update`,
  `aiden-task-status`, `aiden-task-detail`, `aiden-task-list-advanced`,
  `aiden-task-comment`, `aiden-task-watch`, `aiden-task-archive` (destructive —
  pass `confirm:true`), `aiden-task-report` (`kind` = my_work | team | org |
  attention | trend | overdue | workload), `aiden-session-link`, `aiden-project-list`,
  `aiden-project-templates`, `aiden-project-get`, `aiden-project-create`, `aiden-project-update`,
  `aiden-project-assign-team`, `aiden-project-share`,
  `aiden-project-info-get`, `aiden-project-info-update`,
  `aiden-user-list`, `aiden-task-assign`, `aiden-team-list`,
  `aiden-team-members`, `aiden-team-create`, `aiden-team-add-member`,
  `aiden-user-create` (PLATFORM OWNERS — make a new user; temp password),
  `aiden-user-set-global-assignee` (PLATFORM OWNERS — grant/revoke the cross-org
  Global Task Assignee role). These need
  a one-time OAuth login in the browser. (`aiden-project-list` gives minimal
  fields; `aiden-project-get` returns one project's full state — owner, assigned
  team + members, status, progress, task counts. `aiden-team-list` gives counts;
  `aiden-team-members` lists who is on a team.
  `aiden-project-templates` lists the curated department template library (one per
  department: Accounts/Finance, HR, Sales, Operations, Logistics, Manufacturing,
  IT, Marketing, Support, Design) — pass an optional `department` name to surface
  its recommended templates first; then pass a chosen template id to
  `aiden-project-create`'s `template_id` to create a project pre-filled with that
  template's milestones + tasks (the department's standard workflow).
  `aiden-project-update` edits a project's **core** fields — name/title,
  description, status, priority (integer 1=Low 2=Medium 3=High 4=Urgent),
  color, start/due dates, visibility — i.e. the /tasks/projects/{id}/edit form;
  only the fields you pass change.
  `aiden-project-info-get` / `aiden-project-info-update` read/set a project's
  **typed info** — web (website/admin URLs, tech stack), mobile (package name,
  bundle id, store links), product (SKU, manufacturer, listings), marketing/SEO,
  or other. Secrets stay in the vault: a secret_ref field holds only a reference
  name, never the secret itself.)
  Note on "assigning/sharing a project": a project's **owner** is one user, set
  when it's created (the creating session's user). `aiden-task-assign` sets
  per-task assignees; `aiden-project-assign-team` assigns the whole project to a
  team; `aiden-project-share` grants a **specific user or team** direct access
  (role viewer|editor|admin, or revoke=true) — they can then open the project and
  its tasks **irrespective of their active org**. Sharing/assigning all make the
  grantee "connected", which is what controls visibility (not the active org).
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
"$SH" projects-templates [--dept "<name>"]       # -> {data:{templates:[{id,name,department_key,milestones}]}}
"$SH" projects-create "<name>" "[description]" [--template <id>]  # --template pre-fills milestones+tasks
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
"$SH" project-share <project_id> --user <id> [--role viewer|editor|admin]   # grant access
"$SH" project-share <project_id> --team <id> [--role ...]                   # grant a team
"$SH" project-unshare <project_id> --user <id> | --team <id>                # revoke
```
Use these in place of the matching `aiden-*` MCP tool wherever the steps below say
to call one. (There is no CLI equivalent of `aiden-task-by-branch`; on the CLI
path, skip the branch-reconcile step and rely on `tasks-find` instead.)

### Sharing / assigning to a registered user
When the user says "share <project/task> with <name>" or "assign … to <name>":
1. Resolve the name → call `aiden-user-list` / `users-list "<name>"`.
2. If 0 matches, tell the user; if >1, **list them and ask which** — never guess.
3. **Confirm the chosen user** (name + email) with the human before assigning.
4. Pick the action:
   - **task** → `aiden-task-assign` (MCP) / `assign <user_id> --task <id>` (CLI).
   - **project** → either `aiden-project-share` (MCP) / `project-share <id> --user <uid> [--role …]`
     (CLI) to grant direct access (default `viewer`; the grantee can open it
     irrespective of their active org), or `assign <user_id> --project <id>` to
     assign every open task. Sharing a project is gated to people who can manage
     it, and you can't grant a role higher than your own.
5. Report back who was granted/assigned what. (They see it in their My Work +
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

## Project modules (Q&A · Roadmap · RAID · Status updates · Links)
Each project carries these collaboration modules; use them on the BOUND project
(`.aiden/task.json` → project.id) unless the user names another:
- **Q&A** — `aiden-project-qa-list` (read open questions — check this when picking
  up a project: someone may be waiting on you), `aiden-project-qa-ask` (raise a
  question for teammates: decisions you can't make, missing context, blockers —
  the owner is notified), `aiden-project-qa-answer`, `aiden-project-qa-resolve`.
- **Roadmap / feature plan** — `aiden-project-roadmap` (read the board),
  `aiden-project-feature-propose` (file future-feature ideas discovered while
  coding instead of losing them), `aiden-project-feature-status`
  (proposed|planned|in_progress|shipped|declined), `aiden-project-feature-convert`
  (turn a feature into a real task, linked back).
- **RAID log** — `aiden-project-raid` (read), `aiden-project-raid-log` (record a
  risk with likelihood/impact/mitigation, an issue, an assumption, or a
  **decision** — log significant technical decisions made during the session),
  `aiden-project-raid-update` (close/edit).
- **Status updates** — `aiden-project-status-list` (current health + history),
  `aiden-project-status-post` (health on_track|at_risk|off_track + summary; the
  owner/team are notified). A status post at the END of a substantial session is
  good practice — it becomes the project's health chip on the dashboard.
- **Links / resources** — `aiden-project-link-list` (find the project's sheets,
  docs, drive folders, referral sites; check here for the spreadsheet/site you
  need), `aiden-project-link-add` (save a reference URL to the project —
  label + url + type sheet|doc|drive_folder|referral_site|reference|other).
  These are URLs, NOT uploaded files; for files use `/aiden-workspace:aiden-assets`.

Notes:
- `.aiden/task.json` holds only ids/names + base_url — **no secrets**. Safe to read.
- Never auto-edit the human-written `CLAUDE.md`; the machine binding lives only in
  `.aiden/task.json`.
