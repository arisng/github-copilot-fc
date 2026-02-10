# Hooks Integrations for Deterministic Ralph v2 Workflows

This appendix details proposed GitHub Copilot Hooks integrations to increase determinism, enforce guardrails, and improve auditability.

## Goals

- Enforce SSOT integrity for session artifacts.
- Prevent out-of-scope or destructive tool usage.
- Provide reproducible audit trails for prompts and tool runs.
- Support deterministic recovery (timeouts, retries, task splitting).

## Hook Overview

Below is an expanded, pick-and-choose list of potential hook integrations. Each item is intentionally narrow so you can cherry-pick without pulling in a full policy bundle.

## Suggested Hook Integrations (Pick List)

### Session Start

1. **Session Directory Guard**
	- Validate `.ralph-sessions/<SESSION_ID>/` exists; if not, create it and the minimal folder scaffold.
	- Block if `<SESSION_ID>` fails strict regex `^\d{6}-\d{6}$` or contains path separators.

2. **Session Header Stamp**
	- Append a single-line header to `logs/session.log` with timestamp, cwd, session id, and prompt hash.

3. **Session Instruction Presence Check**
	- If `.ralph-sessions/<SESSION_ID>.instructions.md` exists, log its hash and last modified time.

### User Prompt Submitted

4. **Prompt Capture (Raw)**
	- Append raw prompt to `logs/prompts.log` with timestamp and session id.

5. **Prompt Hash Index**
	- Write `logs/prompts.index.jsonl` entries with `prompt_hash`, `timestamp`, and `session_id`.

6. **Prompt Size Guard**
	- Reject prompts above a configurable size threshold (e.g., 50 KB) with a clear error message.

### Pre-Tool Use (Enforcement)

7. **Path Allowlist Enforcement**
	- Allow edits only inside `.ralph-sessions/<SESSION_ID>/` and `agents/ralph-v2/` unless explicitly approved.

8. **SSOT File Write Guard**
	- Block edits to `progress.md` and `metadata.yaml` unless schema validation passes.

9. **Single-Mode Subagent Guard**
	- Reject any subagent call that includes more than one MODE or multiple TASK_IDs.

10. **Reviewer Single-Task Guard**
	- Block reviewer invocations that include multiple tasks in one call.

11. **Destructive Command Denylist**
	- Deny tool invocations containing `rm -rf`, `format`, `DROP TABLE`, `git reset --hard`, or equivalent.

12. **Workspace Boundary Guard**
	- Reject file edits that resolve outside the workspace root after path normalization.

13. **Task File Existence Check**
	- Before executor or reviewer runs, verify `tasks/<task-id>.md` exists.

14. **Progress Status Mutation Guard**
	- Block any status writes other than `[ ]`, `[/]`, `[P]`, `[x]`, `[F]`, `[C]`.

15. **Plan Snapshot Integrity Check**
	- Prevent overwriting `plan.iteration-N.md` once created.

16. **Iteration Metadata Guard**
	- Validate `iterations/<N>/metadata.yaml` timing fields are ISO8601 and monotonic.

### Post-Tool Use (Telemetry)

17. **Tool Usage Ledger**
	- Append tool name, args, duration, and exit status to `logs/tool-usage.jsonl`.

18. **Determinism Checksum**
	- Hash updated files and append to `logs/checksums.jsonl` with tool context.

19. **Policy Denial Audit**
	- Record any denied tool invocation with rule id and reason to `logs/policy-denials.jsonl`.

20. **Subagent Output Digest**
	- Hash the subagent response and record along with session id and timestamp.

### Error Occurred

21. **Timeout Ledger**
	- Log timeouts with tool name, call count, and backoff step to `logs/timeouts.jsonl`.

22. **Retry Budget Guard**
	- If retries exceed configured max, force a replanning or task-splitting path.

23. **Failure Snapshot**
	- On failure, snapshot `progress.md`, `metadata.yaml`, and active task file to `logs/failures/`.

### State Transition Hooks

24. **State Transition Ledger**
	- On state change, append previous and next state to `logs/state-transitions.jsonl`.

25. **Replanning Trigger Guard**
	- When feedbacks are detected, require a valid `feedbacks.md` before entering REPLANNING.

26. **Session Review Gate**
	- Block SESSION_REVIEW if any tasks remain `[ ]`, `[/]`, or `[P]`.

### Feedback Intake

27. **Feedback Directory Schema Check**
	- Validate `iterations/<N>/feedbacks/<timestamp>/feedbacks.md` frontmatter and required sections.

28. **Feedback Artifact Index Check**
	- Verify the `Artifacts Index` table references files that exist in the same folder.

### Live Signals

29. **Signal File Schema Check**
	- Validate signal type is one of `STEER`, `PAUSE`, `STOP`, `INFO` and message is non-empty.

30. **Signal Ordering Guard**
	- Enforce FIFO processing by timestamp; reject out-of-order signals.

### Governance and Compliance

31. **Manual Edit Checklist Hook**
	- If a human edits SSOT files, require a short checklist entry in `logs/manual-edits.md`.

32. **Policy Version Stamp**
	- Record hook policy version in `metadata.yaml` on session start and on updates.

33. **Session ID Sanitization Audit**
	- Log rejected session ids with reason and source command.

### Session Start Hook

**Purpose:** Initialize or validate session structure and capture session header metadata.

**Suggested actions:**
- Validate `.ralph-sessions/<SESSION_ID>/` exists or create it.
- Log a session header line with timestamp, cwd, and initial prompt hash.

### User Prompt Submitted Hook

**Purpose:** Record the raw prompt for replayability and governance.

**Suggested actions:**
- Append prompt to `logs/prompts.log` with timestamp and session id.
- Store a hash of the prompt in a separate index for reproducibility checks.

### Pre-Tool Use Hook (Enforcement)

**Purpose:** Enforce deterministic guardrails before any tool executes.

**Suggested policy checks:**
- Deny edits outside `.ralph-sessions/<SESSION_ID>/` and approved agent folders.
- Deny edits to `progress.md` and `metadata.yaml` unless schema validation passes.
- Deny multi-task reviewer invocations (more than one `TASK_ID`).
- Deny destructive commands (e.g., `rm -rf`, `format`, `DROP TABLE`).

### Post-Tool Use Hook (Telemetry)

**Purpose:** Record tool outcomes for audit and reliability metrics.

**Suggested actions:**
- Append tool name, args, and result to `logs/tool-usage.jsonl`.
- Flag repeated failures for deterministic recovery review.

### Error Occurred Hook

**Purpose:** Centralize error telemetry for timeouts and crashes.

**Suggested actions:**
- Append error details to `logs/errors.log` with timestamp and context.
- Tag session for recovery diagnostics if timeouts exceed thresholds.

## Deterministic Control Points

- **SSOT protection:** block edits to canonical files without validation.
- **Scope enforcement:** ensure single-mode and single-task invariants.
- **Recovery transparency:** track retries, backoff steps, and split decisions.
- **Auditability:** provide a stable, structured record of inputs and tool outputs.

## Governance Notes

- Hooks should be treated as policy enforcement, not business logic.
- Denormalized outputs must be labeled non-authoritative.
- Any hook that denies a tool execution must include a clear reason.

## Implementation Notes

- Use JSON Lines logs for deterministic replay.
- Prefer PowerShell for Windows and Bash for Linux/WSL scripts.
- Keep hook execution fast; increase timeouts only for validation steps.
