# Live Signals Implementation Map (Minimap)

This document maps all **Live Signal Checkpoints** in the Ralph v2 agent system. Use this as a reference when fine-tuning signal responsiveness or adding new polling locations.

> **Cross-reference**: Signal type definitions, STEER decision tree, ABORT cleanup checklist, and the hybrid polling model rationale are in [LIVE-SIGNALS-DESIGN.md](LIVE-SIGNALS-DESIGN.md).

## Agent Classification (Hybrid Polling Model)

Subagents have a **dual role** in signal handling, formalized as the Hybrid Polling Model (see LIVE-SIGNALS-DESIGN.md §4). This resolves the previous inconsistency where subagents were classified as "context consumers" but actually polled `signals/inputs/` directly.

| Agent              | Universal Signals (STEER, INFO, PAUSE, ABORT) | State-Specific Signals (APPROVE, SKIP)    | Role                                                                         |
| ------------------ | ---------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------- |
| **Orchestrator**   | Direct poller (state boundaries)               | Direct poller (KNOWLEDGE_APPROVAL only)   | **Primary poller** — owns `signals/inputs/`, routes targeted signals         |
| **Executor**       | Direct poller (step boundaries)                | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Planner**        | Direct poller (mode start)                     | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Questioner**     | Direct poller (cycle/loop boundaries)          | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Reviewer**       | Direct poller (step boundaries)                | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Librarian**      | Direct poller (stage/gate boundaries)          | Context consumer                          | Direct poller for universal; context consumer for state-specific             |

**Why hybrid?** When the Orchestrator invokes a long-running subagent, the Orchestrator is BLOCKED waiting for the return. Direct polling by subagents ensures universal signals (STEER, PAUSE, ABORT, INFO) are handled within the subagent's execution, not delayed until return.

## 1. Ralph-v2 (Orchestrator)

| State                | Location            | Code Block                     | Behavior                                                                                                                     |
| -------------------- | ------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `INITIALIZING`       | Artifact Creation   | `2. State: INITIALIZING`       | Creates `signals/inputs/` & `signals/processed/` directories.                                                                |
| `PLANNING`           | Top of State        | `3. State: PLANNING`           | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Update plan notes before routing.<br>**INFO**: Log and continue.           |
| `EXECUTING_BATCH`    | Pre-Loop            | `6. State: EXECUTING_BATCH`    | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Logs message and passes to Executor context.<br>**INFO**: Append to context. |
| `REVIEWING_BATCH`    | Pre-Loop            | `7. State: REVIEWING_BATCH`    | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**INFO**: Log and continue.                                                          |
| `KNOWLEDGE_APPROVAL` | Approval Wait Loop  | `9. State: KNOWLEDGE_APPROVAL` | **APPROVE**: Invoke Librarian PROMOTE mode.<br>**SKIP**: Transition to COMPLETE.<br>**ABORT**: Exit with cleanup (§3.4).     |

> **Target-Aware Routing**: At every checkpoint above, the Orchestrator applies peek-check-route logic (see LIVE-SIGNALS-DESIGN.md §2.3). Signals targeting a specific subagent are buffered for delivery at the next invocation.

## 2. Ralph-v2-Executor

| Workflow Section  | Step         | Code Block                            | Behavior                                                                                                                                              |
| ----------------- | ------------ | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1. Read Context` | **Step 0**   | `Step 0: Check Live Signals`          | **ABORT**: Return blocked status.<br>**PAUSE**: Wait.<br>**STEER**: Update current execution context.<br>**INFO**: Append to context.                  |
| `2. Mark WIP`     | **Step 2**   | `2. Mark WIP`                         | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Log and continue.<br>**INFO**: Log and continue.                                          |
| `3. Implement`    | **Step 3.5** | `3.5. Verify Signals (Mid-Execution)` | **STEER**: Apply decision tree (LIVE-SIGNALS-DESIGN.md §3.1): (a) restart, (b) adjust, (c) escalate.<br>**INFO**: Append to context and continue.     |

## 3. Ralph-v2-Planner

| Mode             | Step           | Code Block                    | Behavior                                                                                                                                                  |
| ---------------- | -------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| All modes        | **Mode Start** | Before mode-specific workflow | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust mode context before proceeding.<br>**INFO**: Append to context.                        |
| `TASK_BREAKDOWN` | **Step 0**     | `Step 0: Check Live Signals`  | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust plan context and constraints before generating task files.<br>**INFO**: Log and continue. |

## 4. Ralph-v2-Questioner

| Mode                | Loop            | Code Block                                  | Behavior                                                                                                                |
| ------------------- | --------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `brainstorm`        | Pre-Generation  | `Step 1.5: Check Live Signals`              | **STEER**: Update analysis context.<br>**PAUSE**: Wait.<br>**ABORT**: Return early.<br>**INFO**: Append to analysis.     |
| `research`          | Question Loop   | `Step 2: Research each unanswered question` | **Act on**: STEER/INFO/PAUSE/ABORT inside loop.                                                                          |
| `feedback-analysis` | Issue Loop      | `Process: 2. For each critical issue`       | **Act on**: STEER/INFO/PAUSE/ABORT inside loop.                                                                          |

## 5. Ralph-v2-Reviewer

| Workflow Section | Step             | Code Block                   | Behavior                                                                                                                                   |
| ---------------- | ---------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `TASK_REVIEW`    | **Step 0**       | `Step 0: Check Live Signals` | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust review context.<br>**INFO**: Append to context.                         |
| `TASK_REVIEW`    | **Step 1.5**     | `1.5. Check Live Signals`    | **STEER**: Adjust validation context.<br>**PAUSE**: Wait.<br>**ABORT**: Return early.<br>**INFO**: Append to validation context.             |
| `TASK_REVIEW`    | **Post-Verdict** | After review decision        | **ABORT**: Skip commit, return with partial results.<br>**STEER**: Re-evaluate if verdict should change.                                    |

## 6. Ralph-v2-Librarian

| Mode      | Step                   | Code Block                         | Behavior                                                                                                                                   |
| --------- | ---------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `STAGE`   | **Gate 1 (Preflight)** | Before staging preflight           | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust staging scope/criteria.<br>**INFO**: Append to context.                 |
| `STAGE`   | **Post-Collection**    | After evidence collection (Step 1) | **ABORT**: Return blocked.<br>**STEER**: Re-filter collected knowledge based on new context.<br>**INFO**: Append to context and continue.   |
| `PROMOTE` | **Gate 2 (Preflight)** | Before promotion preflight         | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust promotion scope.<br>**INFO**: Append to context.                        |

## 7. Gap Analysis

| Agent  | Potential Location | Reason to Add                                                    |
| ------ | ------------------ | ---------------------------------------------------------------- |
| (None) |                    | All identified gaps addressed in this revision (Planner mode start, Librarian gates, Reviewer Step 0/Post-Verdict). |

## 8. Checkpoint Performance

Checkpoint overhead is **negligible**. Each checkpoint involves a single directory listing (`Get-ChildItem signals/inputs/` on Windows, `ls signals/inputs/` on Linux). When no signals are pending (the common case), this completes in <10ms.

During a typical task execution, 3–5 checkpoints fire (e.g., Executor Steps 0, 2, 3.5), totaling **~30–50ms per task** — insignificant compared to the seconds/minutes of actual task work. Adding new checkpoints (e.g., to Planner and Librarian) is safe with no measurable performance impact.

*(Source: Q-RISK-004 — Performance overhead from frequent polling is LOW.)*

## Common Polling Routine

All checkpoints follow this logic pattern (Mailbox Pattern). Signal type determines routing per the Hybrid Polling Model — subagents handle universal signals (STEER/INFO/PAUSE/ABORT) directly, while state-specific signals (APPROVE/SKIP) are left for the Orchestrator.

```markdown
Poll signals/inputs/
  - List files (sort timestamp asc)
  - For each file (FIFO):
    - Peek: Read signal type and target
    - If target != ALL and target != self → skip (leave for correct consumer)
    - Atomic Move → signals/processed/
    - Read Content
    - Act based on type: STEER / INFO / PAUSE / ABORT
    - (Orchestrator only: also handle APPROVE / SKIP in KNOWLEDGE_APPROVAL state)
```
