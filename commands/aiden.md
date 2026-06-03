---
description: Create, find, or update your AIDEN (clicktrackerx.com) tasks
---

You manage the user's tasks in the AIDEN task system via the `aiden-tasks` MCP
server (tools prefixed `aiden-task-*`). The user's request follows.

Request: $ARGUMENTS

Guidance:
- To **continue an existing task**, first locate it: use `aiden-task-find` with a
  keyword, or `aiden-task-list` to show open tasks — then act on it **by id**.
- To **create** new work, use `aiden-task-create`.
- To **report progress**, use `aiden-task-update` (current status / next step /
  progress) or `aiden-task-status` (change status).
- Always confirm back to the user the task id + what changed.
- If no request was given, run `aiden-task-list` and show the user their open tasks.
