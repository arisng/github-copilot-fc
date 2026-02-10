# Hooks Integrations for Deterministic Ralph v2 Workflows

This appendix details proposed GitHub Copilot Hooks integrations to increase determinism, enforce guardrails, and improve auditability.

## Goals

- Enforce SSOT integrity for session artifacts.
- Prevent out-of-scope or destructive tool usage.
- Provide reproducible audit trails for prompts and tool runs.
- Support deterministic recovery (timeouts, retries, task splitting).

## Hook Overview

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
