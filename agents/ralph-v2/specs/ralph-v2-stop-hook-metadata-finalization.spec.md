# Ralph v2 Stop Hook Metadata Finalization Spec

## Status
- Drafted: 2024-06-20
- Implementation: to be integrated to ralph-v2 workflow and testing
- Scope: Ralph v2 session metadata finalization at session end
- Priority: P0 pilot

## Problem Statement
Session `metadata.yaml` can become stale when a session ends unexpectedly or when final state reconciliation is skipped. This creates non-deterministic session outcomes and makes restart/recovery logic less reliable.
This is a demonstration of the non-determinism of LLM (not following instructions) + orchestrator (skipping steps) interactions, and the need for deterministic policy enforcement at key lifecycle events.

## Objectives
- Ensure session `metadata.yaml` is updated deterministically on every session end.
- Keep behavior consistent across Windows and Linux/WSL.
- Make finalization idempotent and auditable.
- Keep hooks as policy enforcement only (no workflow business logic migration into hooks).

## Non-Goals
- Replacing orchestrator-owned state transitions during normal workflow.
- Reconstructing complex state from transcripts.
- Full migration of all proposed hooks in `appendixes/hooks-integrations.md`.

## Requirements
1. A workspace hook must run on `Stop` lifecycle event.
2. Hook execution must use:
- PowerShell (`.ps1`) on Windows.
- Bash (`.sh`) on Linux/WSL.
3. Hook scripts must resolve the target Ralph session via `.ralph-sessions/.active-session`.
4. Hook scripts must require `.ralph-sessions/<SESSION_ID>/.hook-enabled` before modifying metadata.
5. Metadata finalization must be idempotent.
6. Writes to `metadata.yaml` must be atomic.
7. Finalization must always update `updated_at`.
8. If session is not already complete, force terminal state with:
- `status: blocked`
- `orchestrator.state: COMPLETE`
9. If session is already complete, preserve `status: completed`.
10. Hook must append deterministic JSONL audit entries to session logs.
11. Failures in hook logic must not crash the agent session; they must be logged and return allow-continue behavior.
12. For multi-chat concurrency, target-session resolution for `Stop` must use this precedence:
- binding map by hook `sessionId` (`.ralph-sessions/.hook-bindings/<HOOK_SESSION_ID>.json`)
- transcript parsing (`transcript_path`) for latest valid Ralph session mention
- `.active-session` as last fallback

## Deterministic Data Contract
### Input
- Hook stdin payload (JSON) with at least `cwd`, `sessionId`, `hookEventName`.
- Workspace-local pointer file: `.ralph-sessions/.active-session`.

### Target Files
- `.ralph-sessions/.active-session`
- `.ralph-sessions/.hook-bindings/<HOOK_SESSION_ID>.json`
- `.ralph-sessions/<SESSION_ID>/.hook-enabled`
- `.ralph-sessions/<SESSION_ID>/metadata.yaml`
- `.ralph-sessions/<SESSION_ID>/logs/hook-finalization.jsonl`

### Metadata Keys Updated
- `updated_at` (always)
- `status` (normalized)
- `orchestrator.state` (normalized)
- `finalized_at`
- `finalized_by` = `hook.stop`
- `finalize_reason` = `session_stopped`
- `finalization_version` = `1`

## Algorithm
1. Resolve repo root from script location.
2. Resolve target Ralph session using precedence:
- `.hook-bindings/<HOOK_SESSION_ID>.json` (from `UserPromptSubmit`)
- `transcript_path` parsing for latest valid Ralph session id mention
- `.active-session` fallback
3. Validate resolved session id with regex `^[0-9]{6}-[0-9]{6}$`.
4. Resolve session folder and `.hook-enabled` marker.
5. If marker is missing, return success (no-op outside Ralph-v2).
6. Resolve metadata path.
5. If metadata missing, emit warning JSONL and return success.
6. Acquire lock file `.finalize.lock` (best-effort).
7. Read metadata text.
8. Determine current `status`.
9. Apply deterministic normalization:
- `updated_at = now`
- `status = completed` if already completed; else `blocked`
- `orchestrator.state = COMPLETE`
- upsert finalization keys
10. Write `metadata.yaml` atomically (`temp` then replace).
11. Append JSONL event (`ok`, `warning`, or `error`).
12. If finalization succeeded, clear `.active-session` when it matches current session id.

## Cross-Platform Commands
### Windows (PowerShell)
`pwsh -NoProfile -File hooks/scripts/ralph-v2-finalize-session-stop.ps1`

### Linux/WSL (Bash)
`bash hooks/scripts/ralph-v2-finalize-session-stop.sh`

## Acceptance Criteria
- Hook file exists in `hooks/` and uses `Stop` event.
- Windows command uses `.ps1` script.
- Linux command uses `.sh` script.
- Re-running script on same session does not corrupt metadata.
- Session without `.hook-enabled` remains untouched (hook exits no-op).
- Script handles missing pointer and missing metadata with warning logs.
- Existing metadata fields unrelated to finalization are preserved.
- Audit JSONL file contains one line per execution.

## Verification Plan
1. Run script against a fixture metadata file with `status: completed`.
2. Run script against a fixture metadata file with `status: in_progress`.
3. Re-run script on same fixture to validate idempotence.
4. Validate keys and timestamps in output metadata.
5. Validate JSONL logging format.
6. Validate `Stop` resolution from hook-session binding file.
7. Validate `Stop` resolution from transcript parsing when binding is missing.

## Risks and Mitigations
- Risk: simplistic YAML mutations could break formatting.
- Mitigation: targeted key upsert rules with minimal structural edits.
- Risk: wrong session chosen.
- Mitigation: binding map keyed by hook `sessionId`, transcript fallback, then `.active-session` fallback.
- Risk: hook runs for non-Ralph chats due to workspace-wide Stop lifecycle.
- Mitigation: require session marker `.hook-enabled` before any metadata mutation.
- Risk: hook runtime differences across OS.
- Mitigation: separate native scripts (`.ps1` and `.sh`) plus common contract.

## Self-Critique Loop (Spec)
### Pass 1 Findings
- Missing explicit lock semantics.
- Missing pointer lifecycle ownership.

### Pass 1 Resolutions
- Added best-effort lock step in algorithm.
- Defined orchestrator ownership of `.active-session` lifecycle in implementation tasks.

### Pass 2 Findings
- Windows runtime assumptions were too broad; wrappers now avoid version-specific Python launchers and prefer `python`.

### Pass 2 Resolutions
- Enforced Python invocation policy (`python` first, fallback `py`) in Windows wrapper and fixture tests.

### Pass 3 Findings
- None.

## Implementation Tasks
1. Create `hooks/ralph-v2-stop-finalizer.hooks.json` with `Stop` hook configuration.
2. Implement Windows script: `hooks/scripts/ralph-v2-finalize-session-stop.ps1`.
3. Implement Linux/WSL script: `hooks/scripts/ralph-v2-finalize-session-stop.sh`.
4. Add lightweight deterministic fixture tests under `hooks/scripts/tests/`.
5. Update `agents/ralph-v2/ralph-v2.agent.md` to maintain `.active-session` pointer:
- Set on initialize/resume.
- Clear on `COMPLETE` exit.
 - Set and clear `.hook-enabled` marker for Ralph-only hook applicability.
6. Update `agents/ralph-v2/appendixes/hooks-integrations.md` with pilot hook entry and deployment notes.
7. Publish hook with `scripts/publish/publish-hooks.ps1` and validate output.
8. Add `UserPromptSubmit` hook to maintain `.hook-bindings/<HOOK_SESSION_ID>.json` from user chat input.
9. Add transcript parsing fallback for `Stop` hook when binding is missing.
