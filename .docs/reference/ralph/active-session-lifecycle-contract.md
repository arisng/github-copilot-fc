---
category: reference
---

# `.active-session` Lifecycle Contract

The `.ralph-sessions/<SESSION_ID>/.active-session` file is a bare-text pointer containing only the session ID string (e.g., `260309-125554`). It enables hook loggers to discover the active session without scanning the directory tree.

## Lifecycle Owners

| Event | Owner | Location in Instructions |
|-------|-------|--------------------------|
| **New session** | Planner (INITIALIZE mode) | `ralph-v2-planner.instructions.md` — Step 1.5 in `<init_mode>`, after `metadata.yaml` creation |
| **Resumed session** | Orchestrator (Session Resolution) | `ralph-v2-orchestrator.instructions.md` — ELSE branch of Session Resolution step 1, before guardrail loading |
| **Session complete** | Orchestrator (COMPLETE state) | `ralph-v2-orchestrator.instructions.md` — State 9 block start, before signal finalization |
| **Crash recovery** | Stop-hook | Finalization safety net — clears stale pointer if process exits abnormally |

## Format Contract

- **Content**: Bare session ID string (e.g., `260309-125554`), no metadata, no newline padding.
- **Consumers**: Bash logger reads via `tr -d '[:space:]'`; PowerShell logger reads via `Get-Content`.
- **Constraint**: SES-004 — only one session MAY be active at a time; no concurrent locking needed.

## State Transitions

```
[No session]
    │
    ▼  Planner INITIALIZE
[.active-session created]  ← bare session ID
    │
    ├── Orchestrator resumes → re-writes .active-session (idempotent refresh)
    │
    ▼  Orchestrator COMPLETE (State 9)
[.active-session deleted]
    │
    └── Stop-hook clears if still present (crash safety net)
```

## Design Decisions

- **Bare format over structured**: Loggers depend on raw `Get-Content` / `tr -d '[:space:]'` parsing. Adding metadata would break existing consumers.
- **Early resume-write**: Placed before guardrail loading so the pointer is set even if guardrails fail, allowing the stop-hook to use it for cleanup.
- **COMPLETE-only clear**: SES-003 defines only 3 session statuses (active, paused, completed) — no ABORTED or CANCELLED states exist.
- **Shared instructions, not wrappers**: Both edits target shared instruction files that propagate to VS Code and CLI runtimes via `<!-- EMBED: -->` markers.
