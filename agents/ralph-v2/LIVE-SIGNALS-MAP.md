# Live Signals Implementation Map (Minimap)

This document maps all **Live Signal Checkpoints** currently implemented in the Ralph v2 agent system. Use this as a reference when fine-tuning signal responsiveness or adding new polling locations.

## 1. Ralph-v2 (Orchestrator)

| State             | Location          | Code Block                  | Behavior                                                                                       |
| ----------------- | ----------------- | --------------------------- | ---------------------------------------------------------------------------------------------- |
| `INITIALIZING`    | Artifact Creation | `2. State: INITIALIZING`    | Creates `signals/inputs/` & `signals/processed/` directories.                                  |
| `PLANNING`        | Top of State      | `3. State: PLANNING`        | **STOP**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Update plan notes before routing.            |
| `EXECUTING_BATCH` | Pre-Loop          | `6. State: EXECUTING_BATCH` | **STOP**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Logs message and passes to Executor context. |
| `REVIEWING_BATCH` | Pre-Loop          | `7. State: REVIEWING_BATCH` | **STOP**: Exit.<br>**PAUSE**: Wait.                                                            |

## 2. Ralph-v2-Executor

| Workflow Section  | Step         | Code Block                            | Behavior                                                                                             |
| ----------------- | ------------ | ------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `1. Read Context` | **Step 0**   | `Step 0: Check Live Signals`          | **STOP**: Return blocked status.<br>**PAUSE**: Wait.<br>**STEER**: Update current execution context. |
| `2. Mark WIP`     | **Step 2**   | `2. Mark WIP`                         | **STOP**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Log and continue.                        |
| `3. Implement`    | **Step 3.5** | `3.5. Verify Signals (Mid-Execution)` | **STEER**: Consolidate feedback, optionally restart implementation step before verification.         |

## 3. Ralph-v2-Planner

| Mode             | Step       | Code Block                   | Behavior                                                                     |
| ---------------- | ---------- | ---------------------------- | ---------------------------------------------------------------------------- |
| `TASK_BREAKDOWN` | **Step 0** | `Step 0: Check Live Signals` | **STEER**: Adjust plan context and constraints before generating task files. |

## 4. Ralph-v2-Questioner

| Mode                | Loop            | Code Block                                  | Behavior                                                                                 |
| ------------------- | --------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `brainstorm`        | Pre-Generation  | `Step 1.5: Check Live Signals`              | **STEER**: Update analysis context.<br>**PAUSE**: Wait.<br>**STOP**: Return early.       |
| `research`          | Question Loop   | `Step 2: Research each unanswered question` | **Act on**: STEER/PAUSE/STOP inside loop.                                                |
| `feedback-analysis` | Issue Loop      | `Process: 2. For each critical issue`       | **Act on**: STEER/PAUSE/STOP inside loop.                                                |

## 5. Ralph-v2-Reviewer

| Workflow Section | Step          | Code Block                 | Behavior                                                                             |
| ---------------- | ------------- | -------------------------- | ------------------------------------------------------------------------------------ |
| `TASK_REVIEW`    | **Step 1.5**  | `1.5. Check Live Signals`  | **STEER**: Adjust validation context.<br>**PAUSE**: Wait.<br>**STOP**: Return early. |

## 6. Gap Analysis (Missing Checkpoints)

| Agent | Potential Location | Reason to Add |
| ----- | ------------------ | ------------- |
| (None) | | All identified gaps implemented. |

## Common Polling Routine

All checkpoints follow this logic pattern (Mailbox Pattern):

```markdown
Poll signals/inputs/
  - List files (sort timestamp asc)
  - Atomic Move -> signals/processed/
  - Read Content
  - Act (STEER/PAUSE/STOP)
```
