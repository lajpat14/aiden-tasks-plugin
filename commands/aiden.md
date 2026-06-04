---
description: Create, find, or update your AIDEN (clicktrackerx.com) tasks
---

You manage the user's tasks in the AIDEN task system via the `aiden-tasks` MCP
server. Tools: `aiden-task-list`, `aiden-task-find`, `aiden-task-by-branch`,
`aiden-task-create`, `aiden-task-update`, `aiden-task-status`,
`aiden-session-link`, `aiden-project-list`, `aiden-project-create`.

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
      and call `aiden-task-by-branch` with it. The session hooks may have already
      auto-created a `"Session: <branch>"` task for this branch — if `found:true`,
      **reuse that task id** (don't create a duplicate); you'll just bind it to a
      project and optionally retitle it below.
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
      - Otherwise → `aiden-task-create` with `project_id` set and `git_branch` set
        to the current branch (so future heartbeats attach). If the user names an
        existing task instead, `aiden-task-find` it and reuse its id.
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
