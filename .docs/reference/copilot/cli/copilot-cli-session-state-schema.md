# Copilot CLI Session State Schema Reference

> **Version**: Copilot CLI v1.0.10 · **Platform**: Windows · **Verified**: March 2026

## Overview

The Copilot CLI persists session state in `~/.copilot/`, a structured directory tree that combines a central SQLite catalog (`session-store.db`), per-session workspaces under `session-state/<uuid>/`, and supporting files for configuration, plugins, logs, and MCP integration. This document is a factual reference for every schema, file format, and naming convention in that tree.

Evidence quality is tagged throughout and summarized in the [Evidence Quality](#evidence-quality) section at the end. Three tiers are used:

- **[official]** — stated in GitHub or Copilot CLI official documentation
- **[empirical]** — directly observed via file inspection or sqlite3 queries across 30+ sessions
- **[hypothesized]** — reverse-engineered from behavior; not officially confirmed

---

## `~/.copilot/` Root Directory Structure

```
~/.copilot/
├── agents/                      # User-level custom agent files
├── hooks/                       # User-level hook files
├── ide/                         # IDE integration state
├── installed-plugins/           # Installed plugin bundles
├── logs/
│   ├── copilot.log              # Persistent authentication/global log
│   └── process-<ts>-<pid>.log  # Per-process structured log
├── marketplace-cache/           # Plugin marketplace cache
├── mcp-oauth-config/            # MCP OAuth tokens
├── pkg/                         # CLI runtime packages
├── prompts/                     # User-level prompt files
├── restart/                     # Restart state
├── scripts/                     # User-level scripts
├── session-state/
│   └── <uuid>/                  # One directory per session
├── skills/                      # User-level skill files
├── command-history-state.json   # CLI command history
├── config.json                  # CLI configuration
├── mcp-config.json              # MCP server configuration
├── permissions-config.json      # Permission settings
├── session-store.db             # Central session catalog (SQLite)
├── session-store.db-shm         # SQLite shared memory
└── session-store.db-wal         # SQLite WAL journal
```

---

## Session Directory Structure (`~/.copilot/session-state/<uuid>/`)

Each session occupies its own UUID-named directory:

```
<uuid>/
├── checkpoints/                         # [empirical]
│   ├── index.md                         # Checkpoint table of contents
│   └── NNN-<slug>.md                    # Numbered checkpoint files
├── files/                               # Session-scoped user artifacts [empirical]
├── research/                            # Research report outputs [empirical]
├── rewind-snapshots/                    # [empirical]
│   ├── index.json                       # Snapshot manifest
│   └── backups/
│       └── <hash>-<timestamp>           # Content-addressed file backups
├── events.jsonl                         # Append-only event stream [empirical; absent in fresh sessions]
├── inuse.<pid>.lock                     # Lock file present while session is active [empirical]
├── plan.md                              # Session plan (present only when /plan is used) [empirical]
├── session.db                           # Per-session SQLite DB [empirical; presence varies, purpose unknown]
├── vscode.metadata.json                 # VS Code integration metadata (may be {}) [empirical]
└── workspace.yaml                       # Session metadata [empirical]
```

---

## `workspace.yaml` Field Reference `[empirical]`

`workspace.yaml` is the canonical metadata file for a session. This file is **not officially documented**; all fields below are confirmed by direct inspection across 30+ sessions.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Session identifier; matches the directory name |
| `cwd` | string (path) | Working directory at session start |
| `git_root` | string (path) | Git repository root (may equal `cwd`) |
| `repository` | string | GitHub repo in `owner/repo` format |
| `host_type` | string | Authentication host type (e.g., `github`) |
| `branch` | string | Git branch name at session start |
| `summary` | string | Human-readable session name; set or updated via `/rename` |
| `summary_count` | integer | Number of compaction summaries generated for this session |
| `created_at` | ISO 8601 | Session creation timestamp |
| `updated_at` | ISO 8601 | Timestamp of last recorded activity |

---

## `events.jsonl` Event Type Catalog `[empirical]`

`events.jsonl` is an append-only newline-delimited JSON stream. This file is **not officially documented**; the schema below is derived from direct inspection of multiple rich sessions.

Each event conforms to the following envelope:

```json
{
  "type": "<event-type>",
  "data": { ... },
  "id": "<uuid>",
  "timestamp": "<ISO8601>",
  "parentId": "<uuid>|null"
}
```

The file may be absent in freshly-created sessions that have not yet recorded any events.

### Session Lifecycle Events

| Event Type | `data` Fields | Description |
|------------|--------------|-------------|
| `session.start` | `sessionId`, `version`, `producer`, `copilotVersion`, `startTime`, `context{cwd, gitRoot, branch, headCommit, repository, hostType, baseCommit}`, `alreadyInUse` | First event emitted when a new session is created |
| `session.resume` | `resumeTime`, `eventCount`, `selectedModel`, `reasoningEffort`, `context{...}`, `alreadyInUse` | Emitted when an existing session is reopened |
| `session.shutdown` | _(empty)_ | Emitted on clean session termination |
| `session.task_complete` | `summary` | Emitted when the agent marks a task done |
| `session.compaction_start` | _(empty)_ | Begins context compaction (`/compact`) |
| `session.compaction_complete` | _(not sampled)_ | Ends context compaction |

### Session State Events

| Event Type | `data` Fields | Description |
|------------|--------------|-------------|
| `session.model_change` | `newModel`, `previousReasoningEffort`, `reasoningEffort` | Model or reasoning effort changed |
| `session.info` | `infoType`, `message` | Informational message (e.g., model confirmation) |
| `session.mode_changed` | _(mode value)_ | Session mode changed (e.g., plan ↔ interactive) |
| `session.plan_changed` | `operation` (e.g., `"create"`) | `plan.md` was created or updated |

### Conversation Events

| Event Type | `data` Fields | Description |
|------------|--------------|-------------|
| `user.message` | _(user input)_ | User prompt submitted |
| `assistant.turn_start` | _(turn metadata)_ | Assistant begins processing |
| `assistant.message` | _(response content)_ | Assistant message chunk |
| `assistant.turn_end` | _(turn metadata)_ | Assistant turn complete |

### Tool and Agent Events

| Event Type | `data` Fields | Description |
|------------|--------------|-------------|
| `tool.execution_start` | `toolCallId`, `toolName`, `arguments` | Tool invocation begins |
| `tool.execution_complete` | `toolCallId`, `toolName`, `result` | Tool invocation ends |
| `subagent.started` | `toolCallId`, `agentName`, `agentDisplayName`, `agentDescription` | Subagent dispatched |
| `subagent.completed` | `toolCallId`, `agentName` | Subagent finished |
| `hook.start` | _(hook metadata)_ | Lifecycle hook begins |
| `hook.end` | _(hook metadata)_ | Lifecycle hook ends |

---

## `session-store.db` Schema `[official + empirical]`

`~/.copilot/session-store.db` is a SQLite database that serves as the canonical index of all sessions. Its existence and purpose are **officially documented**:

> "In addition to the session files, Copilot CLI stores structured session data in a local SQLite database, referred to as the session store. This data is a subset of the full data stored in the session files."

The database is accompanied by WAL journal files (`-shm`, `-wal`) following standard SQLite multi-process access patterns. The schema below is confirmed by direct `sqlite3` query.

```sql
-- Core session metadata
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    cwd TEXT,
    repository TEXT,
    branch TEXT,
    summary TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
, host_type TEXT);  -- appended column; reflects ALTER TABLE addition after initial schema

-- Full conversation turns
CREATE TABLE turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    turn_index INTEGER NOT NULL,
    user_message TEXT,
    assistant_response TEXT,
    timestamp TEXT DEFAULT (datetime('now')),
    UNIQUE(session_id, turn_index)
);

-- Checkpoint summaries
CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    checkpoint_number INTEGER NOT NULL,
    title TEXT,
    overview TEXT,
    history TEXT,
    work_done TEXT,
    technical_details TEXT,
    important_files TEXT,
    next_steps TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(session_id, checkpoint_number)
);

-- File modification tracking
CREATE TABLE session_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    file_path TEXT NOT NULL,
    tool_name TEXT,
    turn_index INTEGER,
    first_seen_at TEXT DEFAULT (datetime('now')),
    UNIQUE(session_id, file_path)
);

-- PR/commit/issue cross-references
CREATE TABLE session_refs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    ref_type TEXT NOT NULL,   -- 'commit', 'pr', 'issue'
    ref_value TEXT NOT NULL,
    turn_index INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(session_id, ref_type, ref_value)
);

-- FTS5 full-text search index
CREATE VIRTUAL TABLE search_index USING fts5(
    content,
    session_id UNINDEXED,
    source_type UNINDEXED,   -- 'turn', 'checkpoint_*', 'workspace_artifact'
    source_id UNINDEXED
);
```

---

## Checkpoint File Format `[empirical]`

These files are **not officially documented**; the format below is derived from direct inspection.

### `checkpoints/index.md`

A markdown table linking checkpoint numbers to file names:

```markdown
| # | Title | File |
|---|-------|------|
| 1 | Session summary title | 001-session-summary-title.md |
```

### `checkpoints/NNN-<slug>.md`

Each checkpoint file uses XML-tagged sections. Numbering is zero-padded to three digits; the slug is a kebab-case excerpt of the checkpoint title.

```markdown
<overview>
One-paragraph summary of the session so far, suitable for re-establishing context on resume.
</overview>

<history>
1. Numbered list of major work items completed, with tool outcomes.
2. ...
</history>

<work_done>
Files created/modified, with brief descriptions.
</work_done>

<technical_details>
Key technical choices, APIs used, error patterns encountered.
</technical_details>
```

The `checkpoints` table in `session-store.db` mirrors these sections as individual columns (`overview`, `history`, `work_done`, `technical_details`, `important_files`, `next_steps`).

---

## `rewind-snapshots/index.json` Structure `[empirical]`

```json
{
  "version": 1,
  "snapshots": [
    {
      "snapshotId": "<uuid>",
      "eventId": "<event-uuid>",
      "userMessage": "The prompt that triggered the rewindable state",
      "timestamp": "<ISO8601>",
      "fileCount": 27,
      "gitCommit": "<sha>",
      "gitBranch": "main",
      "backupHashes": ["<hash>-<timestamp>", "..."]
    }
  ]
}
```

Backup files in `rewind-snapshots/backups/` are named `<content-hash>-<timestamp>` and store file content at the snapshot point using content-addressed storage (identical files share a single backup entry).

---

## Log File Naming and Format `[empirical]`

### Naming Convention

```
~/.copilot/logs/
├── copilot.log                    # Persistent global log (auth, updates, global events)
└── process-<timestamp>-<pid>.log  # Per-process log (startup, session init, plugin registration)
```

`<timestamp>` follows the pattern `YYYYMMDDTHHMMSSZ` (compact ISO 8601). `<pid>` is the OS process ID.

### Entry Format

```
<ISO8601> [LEVEL] [context?] Message
```

Observed levels: `INFO`, `DEBUG`, `WARN`, `ERROR`

### Example Entries

```
2026-03-22T06:52:12.090Z [INFO] Workspace initialized: 76e5073d-... (checkpoints: 0)
2026-03-22T06:52:12.194Z [INFO] Starting Copilot CLI: 1.0.10
2026-03-22T06:52:12.195Z [INFO] Node.js version: v24.11.1
```

---

## Session Management CLI Options `[official]`

The following startup flags control session resumption and are **officially documented**:

| Flag | Description |
|------|-------------|
| `copilot --continue` | Resume the most recent session automatically |
| `copilot --resume` | Choose a session to resume from an interactive list, or supply a session ID directly |

---

## `/session` Subcommands and Output Field Mapping `[official + hypothesized]`

### Officially Documented Subcommands

| Subcommand | Description |
|------------|-------------|
| `/session checkpoints [n]` | View checkpoint history; optionally limit to the last `n` checkpoints |
| `/session files` | View files modified during the session |
| `/session plan` | View the current session plan (`plan.md`) |
| `/session rename NAME` | Rename the session (updates `workspace.yaml:summary`) |

### Output Field Mapping

The top-level `/session` display computes its fields from the underlying artifacts below. Mappings marked _[hypothesized]_ are reverse-engineered from observed display values.

| `/session` Display Field | Source Artifact | Evidence |
|--------------------------|-----------------|----------|
| Name | `workspace.yaml` → `summary` | empirical |
| ID | `workspace.yaml` → `id` | empirical |
| Duration | Computed: `updated_at − created_at` | hypothesized |
| Created | `workspace.yaml` → `created_at` | empirical |
| Modified | `workspace.yaml` → `updated_at` | empirical |
| Directory | `workspace.yaml` → `cwd` | empirical |
| Log | `~/.copilot/logs/process-<ts>-<pid>.log` (current process) | empirical |
| Session | Path to `events.jsonl` | empirical |
| Workspace.Path | `~/.copilot/session-state/<id>/` | empirical |
| Workspace.Plan | Presence of `plan.md` | empirical |
| Workspace.Checkpoints | Count + titles from `checkpoints/index.md` | empirical |
| Workspace.Files | Contents of `files/` directory | empirical |
| Usage.Total usage | Computed from event stream | hypothesized |
| Usage.API time spent | Computed from `tool.execution_start`/`tool.execution_complete` events | hypothesized |
| Usage.Total session time | Computed: `updated_at − created_at` | hypothesized |
| Usage.Total code changes | Computed from file edit events | hypothesized |

---

## `/chronicle` Command `[official]`

`/chronicle` is an **officially documented** experimental slash command that reads the session store to generate reports across sessions. It does not write to session state.

| Subcommand | Description |
|------------|-------------|
| `/chronicle standup` | Generate a standup-style report of recent activity across sessions |
| `/chronicle tips` | Surface personalized workflow tips based on session history |
| `/chronicle improve` | Suggest improvements for custom instructions based on usage patterns |
| `/chronicle reindex` | Rebuild `session-store.db` from raw session files under `session-state/` |

> **Note**: `/chronicle reindex` is the recovery path if `session-store.db` becomes stale or corrupt — it replays session files into the database.

---

## Evidence Quality

### ✅ Confirmed via Official Documentation

Facts explicitly stated in GitHub or Copilot CLI official documentation:

- `session-store.db` existence and its role as "a subset of the full data stored in the session files"
- `copilot --continue` and `copilot --resume` CLI flags
- `/session checkpoints`, `/session files`, `/session plan`, `/session rename` subcommands
- `/chronicle standup`, `/chronicle tips`, `/chronicle improve`, `/chronicle reindex` subcommands

### 🔬 Confirmed via Empirical Inspection

Facts directly observed through file inspection, `sqlite3` queries, or log analysis across 30+ sessions:

- Root `~/.copilot/` directory layout
- `workspace.yaml` — all field names, types, and values
- `events.jsonl` — envelope schema and all sampled event types
- `session-store.db` — full DDL schema (queried via sqlite3)
- Log file naming pattern (`process-<ts>-<pid>.log`) and entry format
- `checkpoints/index.md` table structure
- Checkpoint file XML section format (`<overview>`, `<history>`, `<work_done>`, `<technical_details>`)
- `rewind-snapshots/index.json` top-level structure and `backups/` naming scheme
- `/session` display field-to-artifact mappings for non-computed fields

### ❓ Hypothesized / Reverse-Engineered

Facts inferred from behavior but not officially confirmed:

- Duration and usage computation methods for `/session` (reverse-engineered from display values)
- `/session` computed field sources (API time, code changes, total usage)
- `session.db` purpose — present in some sessions, absent in others; distinct from `session-store.db` but internal role is unknown
- Whether `files/` is always empty at session start vs. populated during prior work
- Whether `session.compaction_complete` carries data fields (event not sampled in available sessions)
