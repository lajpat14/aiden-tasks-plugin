---
description: Manage AIDEN project/user/task assets (DAM) and project contacts — list, upload, version, approve, organize, and manage key contacts
---

You manage **assets** (files: plans, logos, contracts, designs, PDFs, documents) and
**contacts** (clients, vendors, stakeholders, internal) for an AIDEN project, user, or
task. Assets support folders, versioning, and an approval workflow. This is a thin,
audited transport over the already-gated asset/contact endpoints.

Request: $ARGUMENTS

## Step 0 — Pick the transport

- If the `aiden-asset-*` / `aiden-contact-*` **MCP tools** are available (interactive
  session with OAuth), prefer them. Inline upload via MCP is capped at **8 MB** (base64).
- Otherwise use the **CLI** `scripts/aiden-task-cli.sh` (HMAC-signed, needs
  `AIDEN_AGENT_BASE_URL` / `AIDEN_AGENT_KEY_PREFIX` / `AIDEN_AGENT_HMAC_SECRET`). The CLI
  handles files up to **25 MB** and can upload from a **local path or a URL**.

## Assets

`assetable_type` is one of `project`, `user`, `task`; `assetable_id` is its numeric id.
`category`: `plan | logo | contract | design | document | image | deliverable | other`.

The MCP tool names and the CLI subcommand names differ slightly — both are listed.

| Action | MCP tool | CLI subcommand |
|---|---|---|
| List | `aiden-asset-list` | `asset-list <project\|user\|task> <id> [--folder ID] [--category C] [--approval S]` |
| Get (metadata + versions) | `aiden-asset-get` | `asset-get <asset_id>` |
| Upload | `aiden-asset-create` (base64 ≤ 8 MB) | `asset-create <project\|user\|task> <id> <file_path\|url> [--title T] [--category C] [--tags a,b] [--folder ID] [--desc D]` |
| New version (keeps history) | `aiden-asset-add-version` (base64 ≤ 8 MB) | `asset-version <asset_id> <file_path\|url> [--note N]` |
| Approval | `aiden-asset-approve` | `asset-approve <asset_id> <draft\|in_review\|approved\|archived>` |
| Move (folder_id; 0/omit = root) | `aiden-asset-move` | *(via web UI / REST)* |
| Delete (hard=true removes files, needs manage) | `aiden-asset-delete` | *(via web UI / REST)* |
| List folders | `aiden-asset-folders` | `asset-folders <project\|user\|task> <id>` |
| Create folder | `aiden-asset-create-folder` | `asset-create-folder <project\|user\|task> <id> <name> [--parent ID]` |
| Download bytes | *(no MCP tool — use the route/CLI)* | `asset-download <asset_id> <out_path>` |

- **File transfer:** MCP `*-create` / `*-add-version` take inline **base64 ≤ 8 MB**.
  For larger files (up to 25 MB) use the **CLI**, which uploads from a local **path
  or URL** and streams downloads to disk. There is no MCP download tool — bytes come
  via `asset-download` (CLI) or the authorized `/api/agent/assets/{id}/download` route.

## Contacts (project)

| Action | MCP tool | CLI subcommand |
|---|---|---|
| List | `aiden-contact-list` | `contact-list <project_id> [type]` |
| Create | `aiden-contact-create` | `contact-create <project_id> <name> [--role R] [--company C] [--email E] [--phone P] [--type T] [--user-id ID] [--notes N]` |

- `type`: `client | vendor | stakeholder | internal`.
- `--user-id` / `user_id` links the contact to an existing platform user (internal
  stakeholders); the name/email are hydrated from that user if you omit them.

## Rules

- Access is enforced server-side (project-team membership / ownership). If a call returns
  a permission error, explain it and tell the user who can grant access.
- Reference assets/contacts by **id + name** when reporting back.
- Never fabricate file contents. For an upload you must have a real local path or URL.
- Confirm category/title with the user when ambiguous; don't invent approval states.
