# Hooks Integrations for Deterministic Ralph v2 Workflows

This appendix details proposed GitHub Copilot Hooks integrations to increase determinism, enforce guardrails, and improve auditability.

> **Scope Statement (v2.2.0):** Only **P0 hooks** are in scope for v2.2.0 implementation. P1 hooks are proposed for the next release cycle. P2 hooks are aspirational design proposals for future consideration. This document preserves all 33 hook proposals as a reference pick-list, but implementation priority is strictly tiered to prevent scope creep.

## Goals

- Enforce SSOT integrity for session artifacts.
- Prevent out-of-scope or destructive tool usage.
- Provide reproducible audit trails for prompts and tool runs.
- Support deterministic recovery (timeouts, retries, task splitting).

## Execution Model

This document uses the **GitHub Copilot Hooks API** lifecycle model with 5 native hook types:

1. **Session Start** — fires when a session begins
2. **User Prompt Submitted** — fires when the user sends a prompt
3. **Pre-Tool Use** — fires before any tool executes (enforcement point)
4. **Post-Tool Use** — fires after a tool completes (telemetry point)
5. **Error Occurred** — fires on tool or agent errors

All hooks follow the **Git-style pre-/post- lifecycle pattern**: narrow, script-based policy checks that run at defined lifecycle points. Hooks are policy enforcement, not business logic.

> **Note on State Transition Hooks (items 24-26):** These are NOT native GitHub Copilot Hooks — the Copilot Hooks API does not expose state machine transitions as lifecycle events. Items 24-26 would need to be implemented as **explicit checks within the Orchestrator's state machine** (e.g., guard conditions before `setState()` calls), not as external hook scripts. They are included in this document for completeness but follow a different execution model.

## Priority Tiers

| Tier   | Criteria                                                                                                                                         | Count | Scope                      |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----- | -------------------------- |
| **P0** | Prevents the most dangerous failures: state corruption, scope violations, schema drift. Failure to enforce = broken session or silent data loss. | 7     | **v2.2.0 — implement now** |
| **P1** | Important for auditability, safety, and recovery, but failure is recoverable or detectable without hooks.                                        | 10    | Next release cycle         |
| **P2** | Aspirational. Adds polish, governance depth, or advanced telemetry. Left as design proposals.                                                    | 16    | Future / deferred          |

### Priority Assignment Rationale

P0 hooks are selected based on **failure severity**:
- **State corruption** → SSOT Write Guard (#8), Progress Status Mutation Guard (#14)
- **Scope violations** → Path Allowlist (#7), Single-Mode Guard (#9), Task File Existence Check (#13)
- **Schema drift** → Signal File Schema Check (#29)
- **Session integrity** → Session Directory Guard (#1)

## Hook Overview

Below is an expanded, pick-and-choose list of potential hook integrations. Each item is intentionally narrow so you can cherry-pick without pulling in a full policy bundle. Priority tiers are marked with badges: 🔴 P0, 🟡 P1, 🔵 P2.

## Suggested Hook Integrations (Pick List)

### Session Start

1. 🔴 **Session Directory Guard** `P0`
	- Validate `.ralph-sessions/<SESSION_ID>/` exists; if not, create it and the minimal folder scaffold.
	- Block if `<SESSION_ID>` fails strict regex `^\d{6}-\d{6}$` or contains path separators.

2. 🟡 **Session Header Stamp** `P1`
	- Append a single-line header to `logs/session.log` with timestamp, cwd, session id, and prompt hash.

3. 🔵 **Session Instruction Presence Check** `P2`
	- If `.ralph-sessions/<SESSION_ID>.instructions.md` exists, log its hash and last modified time.

### User Prompt Submitted

4. 🔵 **Prompt Capture (Raw)** `P2`
	- Append raw prompt to `logs/prompts.log` with timestamp and session id.

5. 🔵 **Prompt Hash Index** `P2`
	- Write `logs/prompts.index.jsonl` entries with `prompt_hash`, `timestamp`, and `session_id`.

6. 🔵 **Prompt Size Guard** `P2`
	- Reject prompts above a configurable size threshold (e.g., 50 KB) with a clear error message.

### Pre-Tool Use (Enforcement)

7. 🔴 **Path Allowlist Enforcement** `P0`
	- Allow edits only inside `.ralph-sessions/<SESSION_ID>/` and `agents/ralph-v2/` unless explicitly approved.

8. 🔴 **SSOT File Write Guard** `P0`
	- Block edits to `progress.md` and `metadata.yaml` unless schema validation passes.

9. 🔴 **Single-Mode Subagent Guard** `P0`
	- Reject any subagent call that includes more than one MODE or multiple TASK_IDs.

10. 🟡 **Reviewer Single-Task Guard** `P1`
	- Block reviewer invocations that include multiple tasks in one call.

11. 🟡 **Destructive Command Denylist** `P1`
	- Deny tool invocations containing `rm -rf`, `format`, `DROP TABLE`, `git reset --hard`, or equivalent.

12. 🟡 **Workspace Boundary Guard** `P1`
	- Reject file edits that resolve outside the workspace root after path normalization.

13. 🔴 **Task File Existence Check** `P0`
	- Before executor or reviewer runs, verify `tasks/<task-id>.md` exists.

14. 🔴 **Progress Status Mutation Guard** `P0`
	- Block any status writes other than `[ ]`, `[/]`, `[P]`, `[x]`, `[F]`, `[C]`.

15. 🔵 **Plan Snapshot Integrity Check** `P2`
	- Prevent accidental overwriting of `iterations/<N>/plan.md` once created.
	- **Mode-awareness:** Allow writes from the Planner in UPDATE mode (legitimate plan modifications during replanning). Block all other agents and non-UPDATE mode writes to the plan file.

16. 🔵 **Iteration Metadata Guard** `P2`
	- Validate `iterations/<N>/metadata.yaml` timing fields are ISO8601 and monotonic.

### Post-Tool Use (Telemetry)

17. 🟡 **Tool Usage Ledger** `P1`
	- Append tool name, args, duration, and exit status to `logs/tool-usage.jsonl`.

18. 🔵 **Determinism Checksum** `P2`
	- Hash updated files and append to `logs/checksums.jsonl` with tool context.

19. 🟡 **Policy Denial Audit** `P1`
	- Record any denied tool invocation with rule id and reason to `logs/policy-denials.jsonl`.

20. 🔵 **Subagent Output Digest** `P2`
	- Hash the subagent response and record along with session id and timestamp.

### Error Occurred

21. 🔵 **Timeout Ledger** `P2`
	- Log timeouts with tool name, call count, and backoff step to `logs/timeouts.jsonl`.

22. 🟡 **Retry Budget Guard** `P1`
	- If retries exceed configured max, force a replanning or task-splitting path.

23. 🟡 **Failure Snapshot** `P1`
	- On failure, snapshot `progress.md`, `metadata.yaml`, and active task file to `logs/failures/`.

### State Transition Hooks

> ⚠️ **Implementation Note:** Items 24-26 are NOT native GitHub Copilot Hooks. The Copilot Hooks API does not expose state machine transitions as lifecycle events. These guards would need to be implemented as **explicit checks embedded in the Orchestrator's state machine logic** (e.g., guard conditions evaluated before `setState()` calls in `ralph-v2.agent.md`). They are included here for completeness and to document the desired invariants, but they follow a different execution model than hooks 1-23 and 27-33.

24. 🔵 **State Transition Ledger** `P2`
	- On state change, append previous and next state to `logs/state-transitions.jsonl`.

25. 🟡 **Replanning Trigger Guard** `P1`
	- When feedbacks are detected, require a valid `feedbacks.md` before entering REPLANNING.

26. 🟡 **Session Review Gate** `P1`
	- Block SESSION_REVIEW if any tasks remain `[ ]`, `[/]`, or `[P]`.

### Feedback Intake

27. 🔵 **Feedback Directory Schema Check** `P2`
	- Validate `iterations/<N>/feedbacks/<timestamp>/feedbacks.md` frontmatter and required sections.

28. 🔵 **Feedback Artifact Index Check** `P2`
	- Verify the `Artifacts Index` table references files that exist in the same folder.

### Live Signals

29. 🔴 **Signal File Schema Check** `P0`
	- Validate signal type is one of `STEER`, `PAUSE`, `ABORT`, `INFO`, `APPROVE`, `SKIP` and message is non-empty.

30. 🔵 **Signal Ordering Guard** `P2`
	- Enforce FIFO processing by timestamp; reject out-of-order signals.

### Governance and Compliance

31. 🔵 **Manual Edit Checklist Hook** `P2`
	- If a human edits SSOT files, require a short checklist entry in `logs/manual-edits.md`.

32. 🔵 **Policy Version Stamp** `P2`
	- Record hook policy version in `metadata.yaml` on session start and on updates.

33. 🔵 **Session ID Sanitization Audit** `P2`
	- Log rejected session ids with reason and source command.

---

## P0 Interface Contracts

This section defines the full interface contract for each P0 hook. These contracts are the actionable specification for v2.2.0 implementation.

### Common Contract Structure

Every hook follows a standard contract:

```
┌─────────────────────────────────────────────────┐
│  Lifecycle Event (e.g., Pre-Tool Use)           │
│  ┌───────────────────────────────────────────┐  │
│  │  Hook Script                              │  │
│  │  1. Receive Input (context from runtime)  │  │
│  │  2. Evaluate Policy Rule                  │  │
│  │  3. Return Verdict: PASS | BLOCK | WARN   │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

**Verdict Semantics:**

| Verdict | Effect                                          | Agent Behavior                                                |
| ------- | ----------------------------------------------- | ------------------------------------------------------------- |
| `PASS`  | Hook passed validation.                         | Proceed normally.                                             |
| `BLOCK` | Hook denied the action.                         | Abort the tool invocation. Log reason. Return error to agent. |
| `WARN`  | Hook flagged a concern but allows continuation. | Log warning. Proceed with caution. Agent may self-correct.    |

**Error Behavior (all hooks):** If the hook script itself fails (crash, timeout, unhandled exception), the default behavior is **fail-open with warning** — the action proceeds but a warning is logged to `logs/hook-errors.jsonl`. This prevents hook bugs from blocking the entire workflow. Critical hooks (SSOT Write Guard, Path Allowlist) MAY be configured as **fail-closed** in production, where a hook failure blocks the action.

---

### Hook #1: Session Directory Guard `P0`

**Lifecycle:** Session Start

**Purpose:** Ensure the session directory exists and conforms to the naming convention before any work begins. Prevents session artifacts from being written to invalid or unexpected locations.

**Input Schema:**
```jsonc
{
  "session_id": "string",       // e.g., "260215-173319"
  "session_path": "string",     // e.g., ".ralph-sessions/260215-173319/"
  "workspace_root": "string"    // Absolute path to workspace
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK",
  "reason": "string | null",    // Required if BLOCK
  "actions_taken": [             // Optional: auto-remediation actions
    "Created directory: .ralph-sessions/260215-173319/",
    "Created scaffold: signals/inputs/, signals/processed/, logs/"
  ]
}
```

**Policy Rules:**
1. `session_id` MUST match regex `^\d{6}-\d{6}$`. → BLOCK if no match.
2. `session_id` MUST NOT contain path separators (`/`, `\`). → BLOCK if found.
3. If `session_path` does not exist, create it with the minimal scaffold (`signals/inputs/`, `signals/processed/`, `logs/`). → PASS with `actions_taken`.
4. If `session_path` exists, validate scaffold directories are present. → WARN if missing subdirectories.

**Error Behavior:** Fail-open. If the hook crashes, the session proceeds (the Orchestrator's own Session Resolution step will detect missing directories).

**Example Enforcement:**
```
INPUT:  session_id = "invalid-id"
RULE:   ^\d{6}-\d{6}$ → no match
OUTPUT: { verdict: "BLOCK", reason: "Session ID 'invalid-id' does not match required format YYMMDD-HHmmss" }
```

---

### Hook #7: Path Allowlist Enforcement `P0`

**Lifecycle:** Pre-Tool Use

**Purpose:** Prevent agents from editing files outside the approved scope. This is the primary scope enforcement mechanism — without it, agents can silently modify any file in the workspace.

**Input Schema:**
```jsonc
{
  "tool_name": "string",        // e.g., "create_file", "replace_string_in_file"
  "file_path": "string",        // Target file path (absolute or relative)
  "session_id": "string",       // Current session ID
  "workspace_root": "string",   // Absolute workspace root
  "allowlist_overrides": [       // Optional: additional allowed paths from session instructions
    "string"
  ]
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK",
  "reason": "string | null",
  "normalized_path": "string",  // Path after normalization (for audit)
  "matched_rule": "string | null" // Which allowlist rule matched (for debugging)
}
```

**Policy Rules:**
1. Normalize `file_path` to resolve `..`, symlinks, and relative segments.
2. Normalized path MUST be inside `workspace_root`. → BLOCK if outside.
3. Normalized path MUST match one of the default allowlist patterns:
   - `.ralph-sessions/<session_id>/**` — session artifacts (children of the session directory)
   - `.ralph-sessions/<session_id>.instructions.md` — session-specific custom instructions (sibling file, created by Planner at session init)
   - `agents/ralph-v2/**` — agent definition files
   - Any path in `allowlist_overrides`
4. If no pattern matches → BLOCK.
5. Read-only tools (`read_file`, `grep_search`, `list_dir`) are **exempt** — this hook only applies to write operations.

**Error Behavior:** **Fail-closed.** If the hook crashes, the write is blocked. Scope violations are too dangerous to allow on hook failure.

**Example Enforcement:**
```
INPUT:  file_path = "../../etc/passwd", tool_name = "create_file"
RULE:   Normalize → resolves outside workspace_root
OUTPUT: { verdict: "BLOCK", reason: "Path resolves outside workspace root after normalization" }
```

```
INPUT:  file_path = ".ralph-sessions/260215-173319/progress.md", tool_name = "replace_string_in_file"
RULE:   Matches .ralph-sessions/<session_id>/**
OUTPUT: { verdict: "PASS", matched_rule: ".ralph-sessions/<session_id>/**" }
```

```
INPUT:  file_path = ".ralph-sessions/260215-173319.instructions.md", tool_name = "create_file"
RULE:   Matches .ralph-sessions/<session_id>.instructions.md (sibling file)
OUTPUT: { verdict: "PASS", matched_rule: ".ralph-sessions/<session_id>.instructions.md" }
```

---

### Hook #8: SSOT File Write Guard `P0`

**Lifecycle:** Pre-Tool Use

**Purpose:** Protect SSOT (Single Source of Truth) files from writes that would corrupt session state. `progress.md` and `metadata.yaml` are the two most critical artifacts — invalid writes cause state machine routing failures, incorrect task status, and unrecoverable sessions.

**Input Schema:**
```jsonc
{
  "tool_name": "string",        // e.g., "replace_string_in_file"
  "file_path": "string",        // Target file path
  "new_content": "string",      // The content being written (full or partial)
  "session_id": "string",
  "file_type": "string"         // "progress" | "metadata" | "other" (hook determines from path)
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK | WARN",
  "reason": "string | null",
  "validation_errors": [         // Detailed schema violations
    {
      "field": "string",
      "expected": "string",
      "actual": "string"
    }
  ]
}
```

**Policy Rules:**
1. Detect `file_type` from path:
   - `**/progress.md` → `"progress"`
   - `**/metadata.yaml` → `"metadata"`
   - All others → `"other"` (PASS, not in scope)
2. For `progress.md`:
   - Each task line MUST match pattern `- \[([ /PxFC])\] task-\d+` → BLOCK if malformed.
   - Status values MUST be one of: `[ ]`, `[/]`, `[P]`, `[x]`, `[F]`, `[C]` → BLOCK if invalid status.
   - Task IDs referenced MUST NOT be duplicated → WARN if duplicates found.
3. For `metadata.yaml`:
   - `orchestrator.state` MUST be a valid state name → BLOCK if unknown state.
   - `iteration` MUST be a positive integer → BLOCK if invalid.
   - Timing fields MUST be ISO8601 → WARN if malformed.

**Error Behavior:** **Fail-closed.** SSOT corruption is the most dangerous failure mode. If the hook crashes, the write is blocked.

**Example Enforcement:**
```
INPUT:  file_path = "iterations/1/progress.md", new_content contains "- [Z] task-1"
RULE:   Status "Z" not in allowed set [ /PxFC]
OUTPUT: { verdict: "BLOCK", reason: "Invalid status '[Z]' for task-1. Allowed: [ ], [/], [P], [x], [F], [C]" }
```

---

### Hook #9: Single-Mode Subagent Guard `P0`

**Lifecycle:** Pre-Tool Use

**Purpose:** Enforce the single-mode invariant — each subagent invocation handles exactly one MODE and one TASK_ID. Multi-mode or multi-task calls violate the workflow's isolation guarantees and produce unpredictable results.

**Input Schema:**
```jsonc
{
  "tool_name": "string",        // e.g., "@agent Ralph-v2-Executor"
  "invocation_text": "string",  // Full invocation prompt text
  "agent_target": "string",     // Target agent name
  "parsed_params": {             // Extracted parameters (best-effort parse)
    "modes": ["string"],         // e.g., ["EXECUTE"]
    "task_ids": ["string"],      // e.g., ["task-1"]
    "session_path": "string"
  }
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK",
  "reason": "string | null",
  "modes_found": ["string"],    // For debugging
  "task_ids_found": ["string"]  // For debugging
}
```

**Policy Rules:**
1. `parsed_params.modes` MUST contain exactly 1 element → BLOCK if 0 or >1.
2. `parsed_params.task_ids` MUST contain exactly 0 or 1 element → BLOCK if >1.
   - 0 is valid for modes that don't require a task (e.g., Planner INITIALIZE, Questioner BRAINSTORM).
3. If `agent_target` is `Ralph-v2-Reviewer`, apply additional Reviewer Single-Task Guard logic (see Hook #10).

**Error Behavior:** Fail-open with warning. Parsing invocation text is best-effort; false positives from parsing errors should not block valid invocations.

**Example Enforcement:**
```
INPUT:  invocation_text contains "MODE: EXECUTE" and "TASK_ID: task-1, task-2"
RULE:   task_ids = ["task-1", "task-2"] → count > 1
OUTPUT: { verdict: "BLOCK", reason: "Multiple TASK_IDs detected: [task-1, task-2]. Each subagent call must handle exactly one task." }
```

---

### Hook #13: Task File Existence Check `P0`

**Lifecycle:** Pre-Tool Use

**Purpose:** Verify that the task definition file exists before the Executor or Reviewer begins work. Running a subagent against a nonexistent task produces undefined behavior — the subagent may create arbitrary files, read stale data, or silently fail.

**Input Schema:**
```jsonc
{
  "tool_name": "string",        // e.g., "@agent Ralph-v2-Executor"
  "agent_target": "string",     // "Ralph-v2-Executor" | "Ralph-v2-Reviewer"
  "task_id": "string",          // e.g., "task-1"
  "session_path": "string",     // e.g., ".ralph-sessions/260215-173319/"
  "iteration": "number"         // Current iteration number
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK",
  "reason": "string | null",
  "expected_path": "string",    // Where the task file was looked for
  "file_exists": "boolean"
}
```

**Policy Rules:**
1. Construct expected path: `<session_path>/iterations/<iteration>/tasks/<task_id>.md`
   - Fallback (pre-normalization sessions): `<session_path>/tasks/<task_id>.md`
2. File MUST exist at expected path → BLOCK if not found at either location.
3. File MUST be non-empty (size > 0 bytes) → WARN if empty.

**Error Behavior:** Fail-open. If the hook crashes (e.g., filesystem error), the subagent proceeds — it will fail naturally when attempting to read the task file.

**Example Enforcement:**
```
INPUT:  task_id = "task-99", session_path = ".ralph-sessions/260215-173319/", iteration = 1
RULE:   File not found at iterations/1/tasks/task-99.md or tasks/task-99.md
OUTPUT: { verdict: "BLOCK", reason: "Task file not found: iterations/1/tasks/task-99.md" }
```

---

### Hook #14: Progress Status Mutation Guard `P0`

**Lifecycle:** Pre-Tool Use

**Purpose:** Ensure that status values written to `progress.md` are valid. Invalid status characters break the Orchestrator's task routing logic (which pattern-matches on `[ ]`, `[/]`, `[P]`, `[x]`, `[F]`, `[C]`) and cause tasks to be silently skipped or re-executed.

**Input Schema:**
```jsonc
{
  "tool_name": "string",        // e.g., "replace_string_in_file"
  "file_path": "string",        // Must match **/progress.md
  "old_content": "string",      // The content being replaced
  "new_content": "string"       // The replacement content
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK",
  "reason": "string | null",
  "invalid_statuses": [          // List of invalid status values found
    {
      "task_id": "string",
      "status": "string"
    }
  ]
}
```

**Policy Rules:**
1. Only applies when `file_path` matches `**/progress.md`.
2. Parse `new_content` for task status lines matching `- \[(.)\] task-`.
3. Each extracted status character MUST be one of: ` `, `/`, `P`, `x`, `F`, `C` → BLOCK if any other character found.
4. Status transitions should follow valid paths (optional WARN):
   - `[ ]` → `[/]` (started)
   - `[/]` → `[P]` (pending review) or `[F]` (failed)
   - `[P]` → `[x]` (qualified) or `[/]` (rework)
   - Invalid transitions (e.g., `[ ]` → `[x]` skipping in-progress) → WARN.

**Error Behavior:** Fail-open. Status validation is important but progress.md writes happen frequently; hook crashes should not disrupt flow.

**Example Enforcement:**
```
INPUT:  new_content = "- [✓] task-1 (completed)"
RULE:   Status "✓" not in allowed set [ /PxFC]
OUTPUT: { verdict: "BLOCK", reason: "Invalid status '✓' for task-1. Use [x] for completed tasks." }
```

---

### Hook #29: Signal File Schema Check `P0`

**Lifecycle:** Pre-Tool Use (when creating signal files) / Session Start (when validating existing signals)

**Purpose:** Validate that signal files in `signals/inputs/` conform to the expected schema. Invalid signals cause the Orchestrator's Poll-Signals routine to crash, misroute, or silently ignore signals — breaking the live feedback loop.

**Input Schema:**
```jsonc
{
  "file_path": "string",        // e.g., "signals/inputs/signal.260215-180000.yaml"
  "file_content": "string",     // Raw YAML content of the signal file
  "session_id": "string"
}
```

**Output Schema:**
```jsonc
{
  "verdict": "PASS | BLOCK | WARN",
  "reason": "string | null",
  "validation_errors": [
    {
      "field": "string",
      "expected": "string",
      "actual": "string"
    }
  ],
  "parsed_signal": {             // Successfully parsed signal (if PASS/WARN)
    "type": "string",
    "target": "string",
    "message": "string"
  }
}
```

**Policy Rules:**
1. File MUST be valid YAML → BLOCK if parse fails.
2. `type` field MUST exist and be one of: `STEER`, `PAUSE`, `ABORT`, `INFO`, `APPROVE`, `SKIP` → BLOCK if missing or invalid.
3. `message` field MUST exist and be non-empty (trimmed length > 0) → BLOCK if missing or empty.
4. `target` field SHOULD exist. If missing, default to `ALL` → WARN if missing.
5. If `iteration` field is present, it MUST be a positive integer → WARN if invalid.
6. Filename MUST match pattern `signal.<YYMMDD-HHmmss>.yaml` → WARN if non-conformant (signal is still processed).

**Error Behavior:** Fail-open. Invalid signals should be rejected, but a hook crash should not prevent the Orchestrator from polling.

**Example Enforcement:**
```
INPUT:  file_content = "type: INVALID\nmessage: test"
RULE:   type "INVALID" not in allowed set
OUTPUT: { verdict: "BLOCK", reason: "Invalid signal type 'INVALID'. Must be one of: STEER, PAUSE, ABORT, INFO, APPROVE, SKIP" }
```

```
INPUT:  file_content = "type: STEER\nmessage: ''"
RULE:   message is empty after trim
OUTPUT: { verdict: "BLOCK", reason: "Signal message must be non-empty" }
```

---

## Priority Summary

### P0 Hooks (v2.2.0 — Implement Now)

| #   | Hook                           | Lifecycle     | Fail Mode       | Key Risk Mitigated         |
| --- | ------------------------------ | ------------- | --------------- | -------------------------- |
| 1   | Session Directory Guard        | Session Start | Fail-open       | Session integrity          |
| 7   | Path Allowlist Enforcement     | Pre-Tool Use  | **Fail-closed** | Scope violations           |
| 8   | SSOT File Write Guard          | Pre-Tool Use  | **Fail-closed** | State corruption           |
| 9   | Single-Mode Subagent Guard     | Pre-Tool Use  | Fail-open       | Isolation violations       |
| 13  | Task File Existence Check      | Pre-Tool Use  | Fail-open       | Undefined behavior         |
| 14  | Progress Status Mutation Guard | Pre-Tool Use  | Fail-open       | State routing failures     |
| 29  | Signal File Schema Check       | Pre-Tool Use  | Fail-open       | Signal processing failures |

### P1 Hooks (Next Release)

| #   | Hook                         | Lifecycle         | Rationale                                          |
| --- | ---------------------------- | ----------------- | -------------------------------------------------- |
| 2   | Session Header Stamp         | Session Start     | Audit trail — important but not blocking           |
| 10  | Reviewer Single-Task Guard   | Pre-Tool Use      | Scope safety — partially covered by #9             |
| 11  | Destructive Command Denylist | Pre-Tool Use      | Safety net — dangerous but rare in practice        |
| 12  | Workspace Boundary Guard     | Pre-Tool Use      | Scope safety — partially covered by #7             |
| 17  | Tool Usage Ledger            | Post-Tool Use     | Telemetry — valuable for debugging                 |
| 19  | Policy Denial Audit          | Post-Tool Use     | Governance — tracks hook denials                   |
| 22  | Retry Budget Guard           | Error Occurred    | Recovery — prevents infinite retries               |
| 23  | Failure Snapshot             | Error Occurred    | Recovery — preserves failure context               |
| 25  | Replanning Trigger Guard     | State Transition* | Workflow correctness — prevents invalid replanning |
| 26  | Session Review Gate          | State Transition* | Workflow correctness — prevents premature review   |

*\* Items 25-26 are state transition guards implemented in the Orchestrator, not native Copilot Hooks.*

### P2 Hooks (Future / Deferred)

| #   | Hook                               | Lifecycle             | Notes                             |
| --- | ---------------------------------- | --------------------- | --------------------------------- |
| 3   | Session Instruction Presence Check | Session Start         | Nice-to-have audit                |
| 4   | Prompt Capture (Raw)               | User Prompt Submitted | Replayability — aspirational      |
| 5   | Prompt Hash Index                  | User Prompt Submitted | Replayability — aspirational      |
| 6   | Prompt Size Guard                  | User Prompt Submitted | Edge case protection              |
| 15  | Plan Snapshot Integrity Check      | Pre-Tool Use          | Low risk of accidental overwrite  |
| 16  | Iteration Metadata Guard           | Pre-Tool Use          | Schema enforcement — low severity |
| 18  | Determinism Checksum               | Post-Tool Use         | Advanced telemetry                |
| 20  | Subagent Output Digest             | Post-Tool Use         | Advanced telemetry                |
| 21  | Timeout Ledger                     | Error Occurred        | Telemetry — nice to have          |
| 24  | State Transition Ledger            | State Transition*     | Advanced audit trail              |
| 27  | Feedback Directory Schema Check    | Pre-Tool Use          | Schema enforcement — low severity |
| 28  | Feedback Artifact Index Check      | Pre-Tool Use          | Data integrity — low severity     |
| 30  | Signal Ordering Guard              | Pre-Tool Use          | FIFO enforcement — edge case      |
| 31  | Manual Edit Checklist Hook         | Pre-Tool Use          | Governance — aspirational         |
| 32  | Policy Version Stamp               | Session Start         | Governance — aspirational         |
| 33  | Session ID Sanitization Audit      | Session Start         | Partially covered by #1           |

*\* Item 24 is a state transition guard implemented in the Orchestrator, not a native Copilot Hook.*

---

## Lifecycle Hook Summaries

### Session Start Hook

**Purpose:** Initialize or validate session structure and capture session header metadata.

**Suggested actions:**
- Validate `.ralph-sessions/<SESSION_ID>/` exists or create it. (→ P0 Hook #1)
- Log a session header line with timestamp, cwd, and initial prompt hash. (→ P1 Hook #2)

### User Prompt Submitted Hook

**Purpose:** Record the raw prompt for replayability and governance.

**Suggested actions:**
- Append prompt to `logs/prompts.log` with timestamp and session id. (→ P2 Hook #4)
- Store a hash of the prompt in a separate index for reproducibility checks. (→ P2 Hook #5)

### Pre-Tool Use Hook (Enforcement)

**Purpose:** Enforce deterministic guardrails before any tool executes.

**Suggested policy checks:**
- Deny edits outside `.ralph-sessions/<SESSION_ID>/` and approved agent folders. (→ P0 Hook #7)
- Deny edits to `progress.md` and `metadata.yaml` unless schema validation passes. (→ P0 Hook #8)
- Deny multi-mode or multi-task subagent invocations. (→ P0 Hook #9)
- Verify task file exists before executor/reviewer runs. (→ P0 Hook #13)
- Validate signal file schema on creation. (→ P0 Hook #29)
- Deny destructive commands (e.g., `rm -rf`, `format`, `DROP TABLE`). (→ P1 Hook #11)

### Post-Tool Use Hook (Telemetry)

**Purpose:** Record tool outcomes for audit and reliability metrics.

**Suggested actions:**
- Append tool name, args, and result to `logs/tool-usage.jsonl`. (→ P1 Hook #17)
- Flag repeated failures for deterministic recovery review.

### Error Occurred Hook

**Purpose:** Centralize error telemetry for timeouts and crashes.

**Suggested actions:**
- Append error details to `logs/errors.log` with timestamp and context.
- Tag session for recovery diagnostics if timeouts exceed thresholds. (→ P1 Hook #22)
- Snapshot SSOT files on failure for post-mortem analysis. (→ P1 Hook #23)

## Deterministic Control Points

- **SSOT protection:** block edits to canonical files without validation. (P0: Hooks #8, #14)
- **Scope enforcement:** ensure single-mode and single-task invariants. (P0: Hooks #7, #9, #13)
- **Schema integrity:** validate signal files and session structure. (P0: Hooks #1, #29)
- **Recovery transparency:** track retries, backoff steps, and split decisions. (P1: Hook #22)
- **Auditability:** provide a stable, structured record of inputs and tool outputs. (P1: Hooks #2, #17, #19)

## Governance Notes

- Hooks should be treated as policy enforcement, not business logic.
- Denormalized outputs must be labeled non-authoritative.
- Any hook that denies a tool execution must include a clear reason.
- P0 hooks with **fail-closed** behavior (Hooks #7, #8) must be thoroughly tested before deployment to avoid blocking valid operations.

## Implementation Notes

- Use JSON Lines logs for deterministic replay.
- Prefer PowerShell for Windows and Bash for Linux/WSL scripts.
- Keep hook execution fast; increase timeouts only for validation steps.
- Hook scripts should be stateless — all context comes via input schema, no global state.
- Reference the [hybrid polling model](../LIVE-SIGNALS-DESIGN.md#4-agent-integration--hybrid-polling-model) for signal integration patterns.
