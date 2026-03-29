---
date: 2026-03-29
type: RFC
severity: High
status: Open for Comment
---

# RFC: Rebuild Ralph-v2 CLI on native Copilot session topology

## Summary
Rebuild the Ralph-v2 CLI variant from scratch so the Copilot CLI session becomes the only session container for a run. Instead of creating and maintaining a parallel `.ralph-sessions/` lifecycle, the CLI runtime should use the Copilot session UUID as its correlation key, store Ralph-v2 session-scoped artifacts under `~/.copilot/session-state/<uuid>/files/`, and use Copilot CLI's existing session history mechanisms for cross-session lookups.

This proposal is intentionally scoped to the CLI runtime. VS Code and other runtimes can continue to use runtime-appropriate storage and orchestration patterns.

## Motivation
The current Ralph-v2 CLI shape duplicates infrastructure that Copilot CLI already provides:

- Session identity is tracked twice.
- Session artifacts are split across two containers.
- Resume and recovery semantics are harder to reason about.
- Cross-session analysis has no single authoritative store.
- Smoke tests and debugging have to reconcile Ralph-v2 state with Copilot CLI state.

The session topology research completed in March 2026 established that Copilot CLI already provides the correct substrate for session persistence, auditability, resume, checkpointing, and historical lookup. Continuing to evolve the CLI variant around `.ralph-sessions/` would preserve the wrong abstraction boundary. A rebuild is preferable to incremental patching because the duplicate-session assumption affects the runtime's identity model, artifact layout, lifecycle, and tests.

## Detailed Design

### 1. Runtime identity model
- Use the active Copilot CLI session UUID as the primary run identifier.
- Discover the UUID from the active session context rather than generating a Ralph-specific session ID.
- Treat Ralph-v2 metadata as session-local data attached to that Copilot session, not as the root of a separate session model.

### 2. Artifact placement model
- Store Ralph-v2 session-scoped artifacts under the active session's `files/` directory.
- Reserve the Git working tree for user-facing outputs that are meant to be version-controlled.
- Do not create new `.ralph-sessions/<id>/` directories for CLI runs.

Suggested layout inside `files/`:

```text
~/.copilot/session-state/<uuid>/files/
└── ralph-v2/
    ├── metadata.yaml
    ├── plan.md
    ├── progress.md
    ├── iterations/
    │   └── <n>/
    │       ├── tasks/
    │       ├── reviews/
    │       ├── reports/
    │       └── knowledge/
    └── logs/
```

The exact sub-layout can be refined during implementation, but the boundary should remain stable: per-run orchestration state belongs in the active Copilot session workspace.

### 3. Lifecycle model
- Remove Ralph-v2 CLI assumptions that it owns session creation, session shutdown, or separate resume semantics.
- Express Ralph-v2 progress through artifacts and events inside the existing Copilot session lifecycle.
- On resume, rediscover Ralph-v2 state from the active Copilot session workspace rather than from a parallel Ralph session folder.

### 4. Cross-session memory model
- Use Copilot CLI's `session-store.db` and supported session analytics surfaces for historical lookup.
- Prefer querying the existing session history over building a Ralph-specific cross-session index.
- Treat `events.jsonl` and the session workspace as the canonical per-session record, with the session store as the searchable historical projection.

### 5. Migration and compatibility
- New CLI runs should stop writing fresh state into `.ralph-sessions/`.
- Existing `.ralph-sessions/` data may remain readable during a transition period, but it should be treated as legacy input, not the write target.
- Tests, diagnostics, and documentation should be updated to validate the native Copilot session layout.
- Rebuild the CLI runtime around the new storage contract instead of wrapping the current design with compatibility shims as the primary architecture.

### 6. Validation strategy
- Update smoke tests to assert that Ralph-v2 session artifacts land under the active Copilot session `files/` path.
- Validate resume behavior against a reused Copilot session ID.
- Validate that reviewer, planner, executor, and librarian handoffs work through the shared session workspace.
- Validate that historical lookups can be satisfied through Copilot CLI session history tooling instead of Ralph-owned indexing.

## Alternatives Considered
- **Keep `.ralph-sessions/` as the primary CLI state store**: Rejected because it preserves dual sources of truth for identity, artifacts, and lifecycle.
- **Mirror data between `.ralph-sessions/` and the Copilot session workspace**: Rejected because synchronization logic would add failure modes without fixing the architectural duplication.
- **Partially migrate artifacts but keep Ralph-owned session lifecycle**: Rejected because it still leaves Copilot CLI and Ralph-v2 competing to define the same run.
- **Incrementally patch the existing CLI implementation in place**: Rejected as the primary strategy because the current design centers on the wrong session boundary; a clean rebuild reduces hidden coupling and migration debt.

## Unresolved Questions
- [ ] What is the most reliable runtime mechanism for discovering the active Copilot session UUID inside the CLI agent flow?
- [ ] Which current Ralph-v2 artifacts should remain session-scoped versus become durable repository artifacts?
- [ ] How much read-only compatibility with legacy `.ralph-sessions/` data is actually needed for tests and diagnostics?
- [ ] Should the rebuilt CLI runtime preserve the current Ralph iteration directory semantics exactly, or simplify them while moving into `files/ralph-v2/`?
- [ ] What is the minimum acceptable migration path for the existing smoke harness and reviewer workflows?

## References
- Research task: [Reverse engineer Copilot CLI session topology and orchestration layer](../.issues/260320_research-copilot-cli-session-topology-and-orchestration-layer.md)
- Explanation: [Copilot CLI Session Topology and Orchestration Layer](../.docs/explanation/copilot/cli/copilot-cli-session-topology.md)
- Relevant section: `The Correct Approach for Ralph-v2 CLI`