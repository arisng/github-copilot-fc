# Copilot CLI Session Topology and Orchestration Layer

> **Last verified**: Copilot CLI v1.0.10 (March 2026) — empirical filesystem inspection on Windows + official GitHub Docs (`github/docs`)
> **Audience**: Developers building orchestration layers (e.g., Ralph-v2) on top of Copilot CLI
> **Related**: [About CLI Plugins](./about-cli-plugins.md) · [Fleet Mode as Prompt Injection](./fleet-mode-as-prompt-injection.md) · [CLI vs VS Code Customization](../../shared/copilot-cli-vs-vscode-customization.md)

---

## Overview

Every Copilot CLI session is more than a conversation thread. The official documentation frames it this way: *"Every GitHub Copilot CLI session is persisted as a set of files in the `~/.copilot/session-state/` directory on your machine. The data for each session contains a complete record of the session. These files allow you to resume an interactive CLI session."* The phrase "a complete record" is the right starting mental model — not a log, not a cache, not a summary: a record.

What the documentation does not explain is *why* the session is structured as it is, or what that structure implies for builders. Every Copilot CLI session is a **structured runtime container** — a combination of a UUID-keyed directory on disk, an append-only event stream, a workspace manifest, and optional checkpoints and files. Understanding this infrastructure is a prerequisite for building anything on top of Copilot CLI, because the decisions you make about where to store shared state, how to correlate session runs, and how to hand off context between agents all depend on knowing what the session layer already provides.

This document explains the mental model behind Copilot CLI's session topology — what each layer is for, why it is designed that way, and what that means for orchestration layers like Ralph-v2. The goal is not to catalog every file (see the reference doc for that), but to explain *why* the session is structured the way it is and what implications flow from that structure.

> **Source note**: This document distinguishes three epistemic levels — see [Confirmed Facts vs. Working Hypotheses](#confirmed-facts-vs-working-hypotheses). The high-level session model (session directory, `session-store.db`, resume behavior, data locality) is **officially documented**. File-internal structures (`events.jsonl` schema, `workspace.yaml` field names, checkpoint format, rewind mechanism, `session.db` schema) are **empirically observed** from direct inspection and are internal implementation details not covered by official docs.

---

## The Two-Layer Workspace Model

Every Copilot CLI session operates across two conceptually distinct namespaces, and conflating them is the most common source of confusion when building orchestration layers.

### Layer 1 — The Working Directory (what the user cares about)

The working directory is the repository or project the user has open. It contains source code, configuration files, tests, and anything tracked by Git. This is the *target* of the session's work. The Copilot CLI agent reads and writes files here through its tool calls (`view`, `edit`, `create`, shell commands), but the session does not *own* this directory — Git does. Artifacts here are user-facing and version-controlled.

```
/home/user/my-project/        ← Working directory (Layer 1)
├── src/
├── tests/
├── package.json
└── .github/
    └── hooks/                ← Project-scoped hooks (Layer 1, Git-tracked)
```

### Layer 2 — The Session Workspace (what Copilot CLI cares about)

The session workspace is a private namespace managed entirely by Copilot CLI. It lives under `~/.copilot/` on Linux/macOS and `%USERPROFILE%\.copilot\` on Windows. This namespace has two scopes:

- **Global scope** (`~/.copilot/` root): Persistent configuration, installed plugins, installed skills, the global session catalog database, and process logs. This survives individual session deletion and persists across restarts.
- **Per-session scope** (`~/.copilot/session-state/<uuid>/`): Everything specific to one session run — the event stream, workspace manifest, checkpoints, session-scoped files, and rewind snapshots.

```
~/.copilot/                                         ← Layer 2 global root
├── session-store.db                                ← Central session catalog (SQLite)
├── agents/                                         ← User-level agent definitions
├── skills/                                         ← Installed skills
├── installed-plugins/                              ← Installed plugin components
├── logs/
│   └── process-<timestamp>-<pid>.log               ← Per-process log
└── session-state/
    └── <uuid>/                                     ← Per-session scope
        ├── workspace.yaml                          ← Session manifest
        ├── events.jsonl                            ← Append-only event stream
        ├── session.db                              ← Per-session SQLite (not always present)
        ├── inuse.<pid>.lock                        ← Exclusive-access lock
        ├── checkpoints/
        │   ├── index.md
        │   └── <n>-<title>.md
        ├── rewind-snapshots/
        │   └── index.json
        └── files/                                  ← Session-scoped artifact store
```

The critical insight: **Layer 2 is not the user's Git repository**. Nothing in `~/.copilot/session-state/` is version-controlled or visible to the user's project. It is Copilot CLI's internal operating space.

### Why Two Layers?

This separation exists for good reasons. The working directory is the user's concern — they own its lifecycle, its Git history, its CI pipeline. The session workspace is the CLI's concern — it needs a place to store ephemeral state (event streams, turn context, in-progress checkpoints) that would pollute the user's repository if stored there. The session workspace is also machine-local by design: it enables features like resume, rewind, and cross-session search without requiring the user's repository to carry session metadata.

The separation also enables a clean trust boundary: hooks and agents in the working directory's `.github/` are project-scoped and potentially team-shared, while the session workspace is always personal to the user's machine.

This personal scope is a documented design guarantee: *"All session data is stored locally in your home directory and is only accessible to your user account."* No session data leaves the machine unless you explicitly share it. For orchestration builders, this is architecturally meaningful: sensitive intermediate artifacts (credentials in task files, personal context in session notes) can live safely in the session workspace without risk of accidental Git exposure or multi-user leakage.

---

## The Session Directory Structure

The key files in a session directory and their roles:

| File                          | Role                                                                                      |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| `workspace.yaml`              | Session manifest: ID, CWD, summary, created_at, updated_at, model, branch                 |
| `events.jsonl`                | Append-only event log; the canonical record of everything that happened                   |
| `session.db`                  | Per-session SQLite; storing todo list and dependency graph, auto generated by Copilot CLI |
| `inuse.<pid>.lock`            | Advisory lock preventing concurrent access; released on shutdown                          |
| `checkpoints/<n>-<title>.md`  | Compacted context snapshots                                                               |
| `checkpoints/index.md`        | Index of all checkpoints with titles and numbers                                          |
| `rewind-snapshots/index.json` | Index of rewind points, each with a git commit hash                                       |
| `files/`                      | Free-form session-scoped artifact store                                                   |
| `plan.md`                     | The current plan for the session, generated by the `/plan` command (plan mode)            |
| `research/`                   | Directory for research artifacts generated by the `/research` command (research mode)     |

For a complete file-by-file reference, see the reference documentation. This explanation focuses on *why* each piece exists, not its schema.

> **Epistemic note**: The existence of the session directory and its high-level purpose are **officially documented**. The specific file names listed above (`events.jsonl`, `workspace.yaml`, `session.db`, `inuse.<pid>.lock`, checkpoint and rewind directory names, `files/`) are **empirically observed** internal implementation details — not covered by official documentation and subject to change across CLI versions. The officially documented session data content is: *"your prompts, Copilot's responses, the tools that were used, details of files that were modified."*

---

## The Session Lifecycle (State Machine)

A session is not just a conversation — it is a state machine with well-defined transitions. Understanding the lifecycle matters because each phase changes which artifacts are authoritative and which are in flux.

### Phase 1: Creation

When a new session starts, the CLI:
1. Generates a UUID for the session
2. Creates `~/.copilot/session-state/<uuid>/`
3. Writes `workspace.yaml` with `id`, `cwd`, `created_at`, `summary` (initially empty or auto-named), `model`, and `branch`
4. Creates `events.jsonl` and appends a `session.start` event
5. Creates `inuse.<pid>.lock` to prevent concurrent session access

At this point, the session is alive but empty. The event stream is the ground truth.

### Phase 2: Active Work

During the session, every significant action is appended to `events.jsonl`:
- User messages arrive as `user.message` events
- Tool executions produce `tool.execution_start` / `tool.execution_complete` pairs
- Subagent dispatches produce `subagent.started` / `subagent.completed` pairs
- Hook invocations produce `hook.start` / `hook.end` pairs
- Model switches produce `session.model_change` events
- `plan.md` creation or updates produce `session.plan_changed` events

This means `events.jsonl` is an audit trail, not just a log. It can reconstruct the full session history even if the in-memory context window is lost.

### Phase 3: Checkpointing

When context pressure builds — either automatically or via `/compact` — the session enters a compaction cycle:
1. `session.compaction_start` event appended
2. A checkpoint file is written to `checkpoints/<n>-<title>.md` containing a structured summary of recent context
3. `checkpoints/index.md` is updated with the new entry
4. `session.compaction_complete` event appended

Checkpoints exist because the model's context window is finite. Rather than losing earlier context as new turns accumulate, checkpoints compress history into a summary that can be reloaded without replaying every raw event. This is why checkpoints are structured documents, not raw event dumps — they must be legible to the model, not just to a machine parser.

### Phase 4: Rewind

`/rewind` creates a recovery point before a destructive operation:
1. Captures the current git commit hash of the working directory
2. Writes an entry to `rewind-snapshots/index.json` with the commit hash, timestamp, and file state
3. Allows the user to restore to this point if the subsequent operation goes wrong

Rewind is specifically tied to the working directory's git state, which is why it captures a commit hash rather than just session state. This is the cleanest example of how the two layers interact: the session layer records *where the working directory was* at a point in time, enabling cross-layer recovery.

### Phase 5: Resume

`copilot --resume <id>` or `/resume` reopens a previous session:
1. Reopens the existing `~/.copilot/session-state/<uuid>/` directory
2. Appends a `session.resume` event to `events.jsonl`
3. Reconstructs session context from `events.jsonl` + `checkpoints/`
4. Creates a new `inuse.<pid>.lock`

The official documentation is explicit about the resume guarantee: *"When you resume a session, Copilot loads the full conversation history, so you can continue exactly where you left off."* The phrase "full conversation history" matters — it is not a summary or a partial reconstruction, but the complete record.

This guarantee is what makes the append-only event stream model necessary. Because events are never deleted or modified — only appended — the session can always reconstruct its history deterministically, regardless of how many intermediate compactions have occurred. Checkpoints compress context for model efficiency, but the underlying event stream remains complete. A resumed session is not starting over; it is continuing from where it left off, with full awareness of all prior events.

### Phase 6: Shutdown

On clean exit, the CLI:
1. Appends `session.shutdown` to `events.jsonl`
2. Releases `inuse.<pid>.lock`
3. Updates `workspace.yaml:updated_at`
4. Syncs the session record to `session-store.db` (the global catalog)

---

## The Event Stream as Audit Trail

`events.jsonl` is the most important artifact in the session directory, and understanding its role shapes how you should think about session state.

Each line in `events.jsonl` is a JSON object with at minimum an `event_type` and a `timestamp`. Events are **append-only**: once written, they are never modified. This is a deliberate design choice that trades storage compactness for auditability and recoverability.

Why append-only? Because any system that overwrites its state becomes ambiguous about what happened during a run. An append-only log means:
- The sequence of events is authoritative, even if the model's in-memory context has been compacted
- Resume can reconstruct context deterministically
- Debugging a failed session means reading the event stream, not guessing
- Two concurrent readers never see a partially written state

The event stream is also the mechanism through which orchestration events are recorded. When Copilot CLI dispatches a subagent, that dispatch is an event. When a hook runs, the hook lifecycle is events. This means the event stream is not just a record of what the user typed — it is a record of the orchestration graph itself.

---

## Checkpoints and Context Compaction

Checkpoints deserve special attention because they sit at the intersection of two concerns: managing model context limits and preserving session continuity.

A checkpoint is not a "save point" in the traditional sense. It does not capture the full session state — that would be too large and too redundant with the event stream. Instead, a checkpoint is a **narrative compression**: a structured document that summarizes what has happened so far in a form the model can efficiently incorporate as context when resuming.

This design choice has practical implications for orchestration layers. If you are building on top of Copilot CLI and you want to maintain your own session summary (e.g., a Ralph-v2 iteration report), you are doing something adjacent to but distinct from what checkpoints provide. Copilot CLI checkpoints summarize the *conversation*; orchestration layer summaries might need to capture *work product* (which files changed, which tasks completed, which tasks failed). These are complementary, not redundant.

The automatic compaction trigger is not fully documented, but empirical observation suggests it fires under a combination of turn count and estimated token pressure. The `/compact` command forces compaction on demand.

---

## Rewind and Recovery

Rewind (`/rewind`) is the session layer's answer to "how do I undo work that crossed both the conversation and the filesystem." Because the conversation history is in the event stream and the filesystem state is in Git, a rewind point must capture both:

- **Conversation side**: The rewind snapshot records *where in the event stream* this recovery point was created
- **Filesystem side**: The rewind snapshot records the git commit hash of the working directory at that moment

Restoring to a rewind point means: roll back the git working tree to the captured commit, and reconstruct session context up to the captured event position. The two-layer model makes this possible — because the session workspace and the working directory are kept separate, rolling back one does not automatically corrupt the other.

This is also why rewind is scoped to the current session's git repository: it can only capture and restore the working directory state, not arbitrary filesystem state outside the git tree.

---

## The Central Session Catalog

There are two SQLite stores with different scopes and purposes, and confusing them leads to incorrect assumptions about persistence.

### Per-Session `session.db`

Present inside `~/.copilot/session-state/<uuid>/`, this database is used by the active session for immediate turn and checkpoint data. It is an operational store — used while the session is running, not for cross-session queries. It is not always present (some session configurations may not use it), and its schema is an implementation detail.

### Global `session-store.db`

Located at `~/.copilot/session-store.db`, this is the **central catalog** of all sessions ever run on this machine. It survives individual session deletion. It is indexed with FTS5 for full-text search, enabling queries like "find all sessions where I worked on authentication" or "what did I do in this repo last week?"

The official documentation describes it precisely: *"In addition to the session files, Copilot CLI stores structured session data in a local SQLite database, referred to as the session store. This data is a subset of the full data stored in the session files."*

The word **subset** establishes the ground-truth hierarchy: the session files (primarily `events.jsonl`) are the canonical record; `session-store.db` is a structured projection built from them for queryability. The database is optimized for indexed search; the session files hold the complete history. If the two ever diverge — which is possible if a session exits uncleanly — the session files are authoritative.

The global catalog is what makes cross-session tooling possible. The `sql` tool in Copilot CLI queries this store. The session history visible in CLI session management commands is drawn from this store.

Why two stores? The per-session database provides low-latency access to the current session's data without joining against potentially thousands of historical sessions. The global catalog provides the historical index without loading the full event stream of every past session into memory. The split is a practical performance decision, not an architectural accident.

---

## The `/chronicle` Command and Session Analytics

The `/chronicle` command (officially documented as experimental) is the primary interface for querying session history from within a running session. It is powered by `session-store.db` and represents the officially supported API surface for session analytics — not just a debug tool, but the intended way to derive structured insight from accumulated session data.

| Subcommand           | What it does                                                                      |
| -------------------- | --------------------------------------------------------------------------------- |
| `/chronicle standup` | Generates a standup-style summary of recent work across sessions                  |
| `/chronicle tips`    | Surfaces personalized workflow tips inferred from session history patterns        |
| `/chronicle improve` | Suggests custom instruction improvements based on observed session behavior       |
| `/chronicle reindex` | Rebuilds `session-store.db` from raw session files in `~/.copilot/session-state/` |

The `/chronicle reindex` subcommand is architecturally significant. It reveals the exact nature of the ground-truth relationship between the two stores: the session files are the **canonical source**; `session-store.db` is a **derived index** that can be fully rebuilt from them. If the database is corrupted or falls out of sync, reindex restores it completely. This is the practical proof of the official "subset" characterization — nothing in the session store can exist that isn't recoverable from the session files.

For orchestration builders, the `/chronicle` commands carry several implications:

- **Never treat `session-store.db` as a write target.** Write to the session (via actions the CLI records as events); read from `session-store.db` (for cross-session search). `/chronicle reindex` is the repair path, not the write path.
- **Session directories are expected to accumulate.** The standup and tips features only work if historical sessions remain on disk. Orchestration layers should not aggressively delete session directories; Copilot CLI is designed to build its intelligence from a growing local history.
- **`/chronicle improve` closes a useful loop.** By analyzing how sessions have been used, the CLI can suggest improvements to custom instructions. Orchestration layers that surface this output create a self-improving feedback cycle — one Ralph-v2's Librarian agent is positioned to leverage.

---

## Orchestration Coordination (Subagents, Tools, Hooks)

From inside an active session, Copilot CLI coordinates several kinds of execution, each with its own event contract:

### Tool Calls

Every tool invocation (file read, shell command, code search, etc.) produces a `tool.execution_start` event before execution and a `tool.execution_complete` event after. The events carry the tool name, inputs, and outputs. This means the event stream contains a complete record of every side effect the session produced on the filesystem.

### Subagent Dispatch and `/fleet` Orchestration

When the main agent delegates to a subagent (via the `task` tool), the dispatch produces `subagent.started` and `subagent.completed` events. Subagents run in their own context window but **share the same session workspace** — they can read and write to `files/`, see the same `workspace.yaml`, and their completions are recorded back to the parent session's event stream.

The official documentation describes the orchestration model behind `/fleet`: *"When you use the /fleet command, the main Copilot agent analyzes the prompt and determines whether it can be divided into smaller subtasks. It will assess whether these can be efficiently executed by subagents. If it decides to assign subtasks to subagents, it will act as orchestrator, managing the workflow and dependencies."*

This is the key architectural fact for orchestration: **subagents are not separate sessions**. They are workers within the same session container, coordinated by the main agent acting as orchestrator. The main agent — not the subagents — decides the decomposition strategy, manages inter-task dependencies, and synthesizes results. If you need subagents to share state, the session's `files/` directory is the correct shared store — not a separate orchestration-layer container.

### Hooks

Hook invocations produce `hook.start` / `hook.end` events. Hooks defined in `.github/hooks/` run at lifecycle points (e.g., pre-session, post-session, post-tool). Because hook execution is event-logged, hook failures are visible in the audit trail.

### Model Changes

When the user switches models mid-session (e.g., from Claude to GPT), a `session.model_change` event is appended. This matters for reproducibility — if you are reviewing a session's event stream after the fact, model switches explain why response characteristics might change mid-session.

### Plan Management

When `plan.md` is created or updated in the session workspace, a `session.plan_changed` event is appended. This gives the event stream visibility into the session's planning state without requiring the plan file itself to be parsed.

---

## Implications for Orchestration Layers

This is where the mental model becomes actionable. The critical insight is:

> **Copilot CLI's session workspace IS the orchestration substrate.**

Any upper orchestration layer that introduces its own parallel session container creates redundancy, confusion, and an impedance mismatch between its state and Copilot CLI's state.

### The Ralph-v2 Case Study

Ralph-v2 currently uses `.ralph-sessions/<uuid>/` as its session container, maintained separately from `~/.copilot/session-state/`. This creates several problems:

| Concern               | Copilot CLI provides        | Ralph-v2 duplicates                     |
| --------------------- | --------------------------- | --------------------------------------- |
| Session identity      | UUID in `workspace.yaml:id` | Own UUID in `.ralph-sessions/`          |
| Event log             | `events.jsonl`              | Session log in `.ralph-sessions/`       |
| Context persistence   | `checkpoints/`              | Iteration reports in `.ralph-sessions/` |
| Shared artifact store | `files/`                    | `.ralph-sessions/<uuid>/files/`         |
| Cross-session search  | `session-store.db` (FTS5)   | No equivalent                           |

The duplication is not just redundant storage — it creates a correlation problem. When debugging a Ralph-v2 session, you must now track two separate UUIDs and two separate event streams to understand what happened.

### The Correct Approach for Ralph-v2 CLI

Given the session topology described above, the architecturally correct approach is:

1. **Use the Copilot CLI session UUID as the correlation key**. The session UUID is available at runtime (via `/session` output or `workspace.yaml`). Ralph-v2 should use this UUID as the primary identity for a run, not generate its own.

2. **Use `~/.copilot/session-state/<uuid>/files/` for session-scoped artifacts**. Iteration outputs, task files, reviewer reports, and librarian staging should live in `files/` rather than in a parallel `.ralph-sessions/` directory. This makes them visible to the session's audit trail and eliminates the dual-container problem.

3. **Avoid creating a parallel session lifecycle**. Ralph-v2 should not maintain its own session start/stop logic — the Copilot CLI session lifecycle handles this. Ralph-v2's orchestration lifecycle should be expressed as events within the Copilot CLI session, not as a parallel container that shadows it.

4. **Leverage `session-store.db` for cross-session memory**. Instead of building its own session history store, Ralph-v2 can use the `sql` tool (which queries `session-store.db`) for historical lookups. The FTS5 index already provides the cross-session search capability Ralph-v2 would otherwise need to build.

### The General Principle

Any orchestration layer built on top of Copilot CLI should ask: *does this state belong in the working directory (Layer 1) or in the session workspace (Layer 2)?*

- **Working directory**: Team-shared hooks, project-scoped instructions, code artifacts produced by the session, Git-tracked outputs
- **Session workspace**: Per-run state, orchestration metadata, intermediate artifacts, context for model reconstruction, correlation data

Blurring this boundary — by putting session state in the working directory (polluting Git) or by creating a third layer outside both — is what produces systems that are difficult to debug, resume, and extend.

---

## Confirmed Facts vs. Working Hypotheses

This document synthesizes three kinds of knowledge. The following tables distinguish them explicitly, because the epistemic level of a fact determines how much you should rely on it when building systems.

### 📖 Officially Documented

Facts drawn from GitHub's official documentation (`github/docs`, accessed March 2026) or the CLI's own published help text. These carry the strongest epistemic weight and are least likely to change without a migration notice.

| Fact                                                                                                                     | Source                                  |
| ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------- |
| Sessions are persisted as files in `~/.copilot/session-state/`                                                           | GitHub Docs — session persistence       |
| Each session's data is "a complete record of the session"                                                                | GitHub Docs — session persistence       |
| Session files enable resume                                                                                              | GitHub Docs — session persistence       |
| Resume loads "the full conversation history" to continue "exactly where you left off"                                    | GitHub Docs — resume guarantee          |
| `session-store.db` stores "structured session data" that is "a subset of the full data stored in the session files"      | GitHub Docs — session store description |
| All session data is stored locally and "is only accessible to your user account"                                         | GitHub Docs — data locality guarantee   |
| Session data includes "your prompts, Copilot's responses, the tools that were used, details of files that were modified" | GitHub Docs — session data contents     |
| `/chronicle` command exists (experimental) and provides standup, tips, improve, and reindex subcommands                  | GitHub Docs / CLI help text             |
| `/chronicle reindex` rebuilds `session-store.db` from session files                                                      | CLI help text                           |
| `/fleet` uses the main agent as orchestrator to decompose prompts into subtasks executed by subagents                    | GitHub Docs — fleet orchestration model |

### ✅ Empirically Confirmed

Facts established through direct filesystem inspection, file content analysis, or observed CLI behavior. These are accurate for Copilot CLI v1.0.10 on Windows (March 2026) but are **internal implementation details** — not officially documented and subject to change across CLI versions without notice.

| Fact                                                                                                                                                     | Source                                               |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Session directory contains: `workspace.yaml`, `events.jsonl`, `session.db` (optional), `inuse.<pid>.lock`, `checkpoints/`, `rewind-snapshots/`, `files/` | Direct filesystem inspection, March 2026             |
| `workspace.yaml` field names: `id`, `cwd`, `summary`, `created_at`, `updated_at`, `model`, `branch`                                                      | Direct file inspection                               |
| `events.jsonl` is JSON Lines format (one JSON object per line, append-only)                                                                              | Direct file inspection                               |
| `session.db` is a SQLite file; not always present in all session directories                                                                             | Direct filesystem inspection                         |
| `inuse.<pid>.lock` is created on session start, released on clean shutdown                                                                               | Observed via process inspection                      |
| `~/.copilot/session-store.db` uses SQLite with FTS5 for full-text search                                                                                 | Confirmed via `sql` tool queries                     |
| `/session` command output fields map to `workspace.yaml` and computed values                                                                             | Confirmed by comparing `/session` output to raw file |
| Checkpoints written to `checkpoints/<n>-<title>.md` with index at `checkpoints/index.md`                                                                 | Direct filesystem inspection after `/compact`        |
| `rewind-snapshots/index.json` contains git commit hash entries                                                                                           | Direct file inspection                               |
| Subagents can read and write to the parent session's `files/` directory                                                                                  | Confirmed via multi-agent runs with file handoffs    |
| `session.resume` event is appended to `events.jsonl` when a session is reopened                                                                          | Direct inspection of `events.jsonl` after `/resume`  |

### 🔬 Inferred / Hypothesized

Inferences from naming conventions, observed patterns, or design logic. Not directly confirmed. Treat as working hypotheses pending official documentation or deeper source-level inspection.

| Hypothesis                                                                                                                                                                                                                 | Basis for inference                                                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Exact event type field values: `tool.execution_start`, `tool.execution_complete`, `subagent.started`, `subagent.completed`, `session.start`, `session.shutdown`, `session.compaction_start`, `session.compaction_complete` | Naming conventions; exact `events.jsonl` schema not fully reverse-engineered           |
| `session.plan_changed` event is appended when `plan.md` is created or updated                                                                                                                                              | Event naming convention; not directly observed                                         |
| `session.model_change` event is appended when the model is switched mid-session                                                                                                                                            | Event naming convention; not directly observed                                         |
| `hook.start` / `hook.end` events wrap hook lifecycle invocations                                                                                                                                                           | Subagent/tool event naming pattern; not directly confirmed                             |
| Automatic compaction threshold is a combination of turn count and token pressure                                                                                                                                           | Observed behavior; exact trigger undocumented                                          |
| Per-session `session.db` is synced to `session-store.db` at shutdown                                                                                                                                                       | Consistency between per-session and global data; sync mechanism not directly confirmed |

---

## Sources

1. **Official GitHub documentation** — [Using GitHub Copilot in the CLI](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli) (GitHub Docs, accessed March 2026) — authoritative source for session persistence model, resume guarantee, data locality guarantee, session data contents, and `session-store.db` relationship
2. **`github/docs` repository** — Official Copilot documentation source, March 2026 — direct source for officially documented quotes used in this document
3. **`github/copilot-cli` repository** — Source for `/chronicle` subcommands and `/fleet` orchestration model description
4. **CLI help text** — `/session`, `/resume`, `/compact`, `/rewind`, `/chronicle`, `/fleet` command outputs in Copilot CLI v1.0.10
5. **Empirical filesystem inspection** — Direct examination of `~/.copilot/session-state/` on Windows (`%USERPROFILE%\.copilot\session-state\`), Copilot CLI v1.0.10, March 2026 — source for all file structure names, field names, and format observations
6. **Session store queries** — Cross-session SQL queries via the `sql` tool against `~/.copilot/session-store.db`
7. **Ralph-v2 session artifact inspection** — Observation of session file layouts during ralph-v2 orchestration runs in this workspace
