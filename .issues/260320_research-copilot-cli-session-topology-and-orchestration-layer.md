---
date: 2026-03-20
type: Task
severity: High
status: Done
completed_at: 2026-03-26
---

# Task: Reverse engineer Copilot CLI session topology and orchestration layer

## Objective
Analyze the anatomy of a Copilot CLI session from the metadata exposed by `/session`, then correlate that view with authoritative sources to build a durable mental model of how Copilot CLI persists session state, workspace artifacts, logs, checkpoints, and orchestration data.

The immediate goal is not to change the product. The goal is to document how a session is structured, what each metadata field likely represents, and how the orchestration layer uses the session workspace across resumes, restarts, and long-running work.

The motivation of this task is to build solid foundational knowledge that will be used to re-build the Ralph-v2 in CLI runtime. This re-build attempt will utilize the same underlying mechanisms that the Copilot CLI uses for session management. Specifically, we must not use `.ralph-sessions/` for storing Ralphv-2 orchestration's shared artifacts and state, because that would introduce an upper Ralph-v2 orchestration layer on top of current Copilot CLI's orchestration layer (Copilot CLI session inside Ralph-v2 session) and this would create unnecessary complexity and potential for bugs. Instead, we will leverage the same session management approach that Copilot CLI uses, which means understanding how Copilot CLI manages its session state and artifacts in its own workspace under `~/.copilot/`.

## Background
Observed session metadata includes fields such as `Name`, `ID`, `Duration`, `Created`, `Modified`, `Directory`, `Log`, `Session`, `Workspace`, `Plan`, `Checkpoints`, `Files`, `Usage`, and code-change totals.

Current working hypotheses to validate:

- there are two primary actors: the human and Copilot CLI
- the human primarily cares about artifacts in the working directory
- Copilot CLI cares about both the working directory and its own session workspace under `~/.copilot/`
- each Copilot CLI session is persisted in a dedicated UUID-named folder so it can survive host restarts and support resume
- the Copilot CLI orchestration layer likely binds checkpoints, logs, events, and generated files into a session-scoped state machine

## Research Questions
- What is the canonical structure of a Copilot CLI session directory and which files are required versus optional?
- What does each field in the `/session` output map to internally?
- How are logs, event streams, checkpoints, and generated artifacts related to each other?
- What guarantees does the Copilot CLI orchestration layer provide for persistence, resume, and recovery after interruption?
- Which parts of the session state are user-facing versus internal implementation details?
- What evidence exists in official Copilot CLI documentation, repository sources, or runtime artifacts that confirms or refines the current mental model?

## Tasks
- [x] Collect authoritative documentation or source references that describe Copilot CLI session persistence and orchestration behavior.
- [x] Inspect representative session-state folders and identify recurring files, naming conventions, and lifecycle markers.
- [x] Map each `/session` metadata field to the underlying artifact or runtime concept where possible.
- [x] Distinguish stable conventions from speculative inferences so the final write-up separates fact from hypothesis.
- [x] Draft a concise anatomy diagram or table that shows the relationship between human working directory, Copilot CLI workspace, session state, logs, and checkpoints.
- [x] Record any operational implications for session resume, debugging, and long-running orchestration flows.

## Acceptance Criteria
- [x] The repository contains a clear markdown note that explains the session topology and the orchestration model in plain language.
- [x] The note distinguishes confirmed behavior from assumptions or reverse-engineered hypotheses.
- [x] The note includes references to authoritative sources or runtime artifacts used during the investigation.
- [x] The note captures the practical implications for session resume, persistence, and artifact discovery.
- [x] The issue remains scoped to analysis and documentation, without implementing product changes.

## Outcome

Research completed and documented in the workspace wiki:

- **Explanation doc**: [Copilot CLI Session Topology and Orchestration Layer](../.docs/explanation/copilot/cli/copilot-cli-session-topology.md) — mental model, lifecycle, orchestration topology, Ralph-v2 implications
- **Reference doc**: [Copilot CLI Session State Schema Reference](../.docs/reference/copilot/cli/copilot-cli-session-state-schema.md) — full field-level schema for all session artifacts with evidence tier tags

### Key findings
- Session topology confirmed: `~/.copilot/session-state/<uuid>/` with `workspace.yaml`, `events.jsonl`, `checkpoints/`, `files/`, `rewind-snapshots/`, `inuse.<pid>.lock`
- `session-store.db` is a global catalog (officially documented); per-session `session.db` exists but is undocumented
- `/session` field mapping fully reverse-engineered against filesystem artifacts
- **Critical implication for Ralph-v2**: `.ralph-sessions/` creates a redundant orchestration layer; the correct approach uses `~/.copilot/session-state/<uuid>/files/` natively
- Three-tier evidence model applied throughout: `[official]` / `[empirical]` / `[hypothesized]`

## References
- Copilot CLI `/session` metadata snapshot as following:

```text
<copilot-cli-session-metadata>
﻿ Session
Name: Agentic Chat V3 Research
ID: d3c1c3cf-8256-4918-a1a5-3be77e41e711
Duration: 58h 59m 23s
Created: 3/17/2026, 11:58:26 PM
Modified: 3/17/2026, 11:58:26 PM
Directory: /home/arisng/src/agent-framework
Log: /home/arisng/.copilot/logs/process-1773978966438-24701.log
Session: /home/arisng/.copilot/session-state/d3c1c3cf-8256-4918-a1a5-3be77e41e711/events.jsonl

Workspace
Path: /home/arisng/.copilot/session-state/d3c1c3cf-8256-4918-a1a5-3be77e41e711
Plan: yes
Checkpoints (9): 9. Finishing validation waves
1. Validation waves and hardening
2. Hardening command palette
3. Fixing validation regressions
4. Phase 12 autonomy controls implemented
...

Files (24):
aguidojo-initial.png
aguidojo-response.png
phase10-attachment-preview.png
phase10-chat-response.png
phase11-stream-metrics.png
...

Usage
Total usage est: 0 Premium requests
API time spent: 0s
Total session time: 58h 59m 23s
Total code changes: +2285 -294
</copilot-cli-session-metadata>
```

- `~/.copilot/session-state/<session-id>/events.jsonl`
- `~/.copilot/logs/process-*.log`
- Copilot CLI workspace root under `~/.copilot/`
