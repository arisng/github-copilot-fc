---
date: 2026-03-15
type: Design Doc  
id: design-ralph-e2e-scenario
status: completed
---

# Design: Ralph CLI E2E Scenario for Smoke Harness

## Executive Summary

The Ralph CLI smoke harness currently **skips agent invocation** via -SkipAgentInvocation, only validating plugin build/install mechanics. To exercise a meaningful multi-agent workflow without bloating test duration, this design specifies:

1. **Minimal realistic prompt** that invokes all core roles (Planner, Executor, Reviewer, Librarian)
2. **State-machine checkpoints & evidence collection** per role to validate orchestration
3. **Checkpoint additions to smoke report** mapping roles/transitions to concrete artifacts
4. **Constraints & optimization strategies** to keep runtime under ~5 min per run

---

## 1. Shortest Realistic Orchestrator Prompt

### Prompt Design Principles
- **Scope**: Single self-contained task that does NOT require interactive human feedback
- **Determinism**: Avoid LLM-generated open-ended output; use scripted, verifiable steps
- **Role Coverage**: Must trigger Planner → Executor → Reviewer → Librarian → Orchestrator loop
- **Duration**: Target completion in 2–4 min per agent invocation (total session ~5–10 min)

### Recommended Prompt
\\\
SESSION_PATH: .ralph-sessions/<SESSION_ID>/

USER_REQUEST: |
  Create a simple documentation file named .docs/test-prompt-response.md 
  with the header "# Test Output" and one paragraph describing what tasks 
  were completed in this session. Do not make any functional code changes. 
  Do not modify existing .docs files. This is a smoke test only.
\\\

### Why This Works
- **Planner**: Parses request → creates 1 trivial task (write file) → no brainstorm/research cycle needed
- **Executor**: Implements file creation → simple, fast, verifiable
- **Reviewer**: Validates file exists & has correct content → quick pass/fail
- **Librarian**: Extracts new \.md\ file → stages to \knowledge/\ → promotes to \.docs/\
- **Orchestrator**: Routes through INITIALIZE → PLANNING → EXECUTING_BATCH → REVIEWING_BATCH → KNOWLEDGE_EXTRACTION → ITERATION_REVIEW → COMPLETE

---

## 2. Subagents, Roles, & Concrete Evidence

### State Machine Path

**INITIALIZING** → **PLANNING** → **BATCHING** → **EXECUTING_BATCH** → **REVIEWING_BATCH** → **KNOWLEDGE_EXTRACTION** → **ITERATION_REVIEW** → **COMPLETE**

### Evidence Checklist by Role

#### Orchestrator Evidence
- \metadata.yaml\ state transitions: INITIALIZING → PLANNING → BATCHING → REVIEWING_BATCH → KNOWLEDGE_EXTRACTION → ITERATION_REVIEW → COMPLETE
- Subagent delegations visible in logs: \	ask("Ralph-v2-Planner-CLI", ...)\, \	ask("Ralph-v2-Executor-CLI", ...)\, etc.

#### Planner Evidence (INITIALIZE → TASK_BREAKDOWN → TASK_CREATE)
- \iterations/1/plan.md\ created with Goal, Success Criteria, Task List
- \iterations/1/progress.md\ created with status markers ([ ], [/], [x], [P], [F], [C])
- \iterations/1/metadata.yaml\ with \started_at\ timestamp
- \iterations/1/tasks/task-1.md\ created with task-id, objective, success criteria
- Progress shows \[x] plan-init\, \[x] plan-breakdown\, \[/] task-1\ after creation

#### Executor Evidence (task implementation)
- \.docs/smoke-test-output.md\ created with header "# Test Output" and body text
- \iterations/1/reports/task-1-report.md\ created with PART 1 (objective, success criteria status, summary)
- Progress shows \[P] task-1\ after execution (pending review)

#### Reviewer Evidence (TASK_REVIEW → COMMIT → ITERATION_REVIEW)
- PART 2 appended to \	ask-1-report.md\ with criterion verdicts (✅ or ❌) and evidence
- Progress shows \[x] task-1\ after review passes
- \iterations/1/review.md\ created by ITERATION_REVIEW mode
- No active issues remaining (clean closure)

#### Librarian Evidence (EXTRACT → STAGE → PROMOTE → COMMIT)
- \iterations/1/progress.md\ Knowledge Progress: \[x] plan-knowledge-extraction\, \[x] plan-knowledge-staging\, \[x] plan-knowledge-promotion\
- \iterations/1/knowledge/\ contains extracted .md files OR section shows [C] (nothing to extract)
- \knowledge/\ contains staged knowledge files with promotion frontmatter
- \.docs/\ contains promoted .md file (e.g., \.docs/test-prompt-response.md\)
- Git log shows new commit from Librarian COMMIT step

---

## 3. Checkpoint Design for Smoke Report

### New Checkpoints to Add

| Checkpoint ID | Bucket | What to Check | Evidence | Pass Condition |
|---|---|---|---|---|
| **orchestrator-state-transitions** | orchestration | State progression in metadata.yaml | metadata.yaml file | State chain: INITIALIZING → ... → COMPLETE |
| **planner-task-creation** | planner | Task file exists with valid structure | iterations/1/tasks/task-1.md | YAML frontmatter valid, sections present |
| **executor-artifact-creation** | executor | Target .docs file created | .docs/smoke-test-output.md | File exists with "# Test Output" header |
| **executor-report-generation** | executor | Report PART 1 written | iterations/1/reports/task-1-report.md | Contains Objective, Success Criteria Status, Summary |
| **reviewer-task-verdict** | reviewer | PART 2 appended with verdict | Report PART 2 section | All criteria marked ✅; task shows [x] in progress.md |
| **librarian-knowledge-extraction** | librarian | Knowledge extraction complete | iterations/1/progress.md | Knowledge Progress shows [x] extraction or [C] (nothing to extract) |
| **librarian-knowledge-staging-promotion** | librarian | Knowledge staged and promoted | knowledge/ and .docs/ | New files visible in both directories |
| **reviewer-iteration-closure** | reviewer | Iteration review created | iterations/1/review.md | File exists; no active issues remain |
| **orchestrator-final-state** | orchestration | Session complete and marked | metadata.yaml + .active-session | state == "COMPLETE" + session ID marker present |

---

## 4. Minimal Prompt & Role Coverage

### Recommended CLI Invocation

\\\powershell
\ = Get-Date -Format 'yyMMdd-HHmmss'
\ = "SESSION_PATH: .ralph-sessions/\/ USER_REQUEST: Create a documentation file at .docs/smoke-test-output.md with header '# Smoke Test Output' and a one-paragraph summary of work completed. Do not modify existing files or make functional code changes. This is a smoke test only."

copilot --config-dir \ \
  --log-dir \ \
  --model gpt-5.2 \
  --agent "Ralph-v2-Orchestrator-CLI" \
  --allow-all \
  --no-ask-user \
  --no-auto-update \
  --stream off \
  --silent \
  --prompt \
\\\

### Role Coverage Path

1. **Planner (INITIALIZE)**: Creates session scaffold, one trivial task
2. **Executor**: Creates .docs file (one task, no complex logic)
3. **Reviewer (TASK_REVIEW)**: Validates file + criteria, approves
4. **Librarian (EXTRACT → STAGE → PROMOTE)**: Stages new .md file, promotes to .docs/
5. **Orchestrator**: Routes all transitions, closes session at COMPLETE

---

## 5. Constraints & Optimization

### Timing Budget
| Step | Target | Strategy |
|------|--------|----------|
| Planner (INITIALIZE + TASK_BREAKDOWN + TASK_CREATE) | ~60–90 sec | Skip Questioner; simple request, no research cycles |
| Executor (file creation) | ~30–60 sec | Trivial implementation |
| Reviewer (TASK_REVIEW + COMMIT) | ~30–45 sec | Simple validation |
| Librarian (EXTRACT → STAGE → PROMOTE → COMMIT) | ~45–60 sec | Minimal new docs, fast merge |
| **Total Session** | **~4–5 min** | Includes LLM token overhead |

### Determinism & Nondeterminism Handling

**Validated (deterministic)**:
- File paths (task files, reports, progress.md, metadata.yaml)
- YAML frontmatter structure
- Status markers ([x], [P], [F], [C])
- State transitions in metadata.yaml

**Tolerated (non-deterministic)**:
- LLM-generated text content (smoke test validates file existence + header, not full body)
- Exact token counts
- Exact timing (use timeout, not strict time assertions)
- Task ID values (always task-1 for smoke)

**Guardrails**:
- Prompt explicitly restricts scope: "Do not make functional code changes"
- Validation checks SIDE EFFECTS (artifacts exist), not LLM text output
- \--reasoning-effort low\ reduces token usage and variance
- \--stream off\ ensures complete output before assertion

### Optional MCPs & Feature Flags
- **mcp_docker/sequentialthinking**: Optional; disable with \--disable-builtin-mcps\ for determinism
- **Questioner MCPs (remote docs/wiki)**: Not exercised in smoke (Questioner skipped by prompt)
- **git/bash**: Required; test fails if unavailable
- **Librarian availability**: Check \AVAILABLE(librarian)\ in orchestrator; skip KNOWLEDGE_EXTRACTION if absent

---

## 6. Implementation Steps

### Step 1: Update smoke-harness prompt default
Change \-PromptText\ parameter default from "Smoke test only. Reply in one short sentence..." to the e2e workflow prompt (see section 4).

### Step 2: Add checkpoint validation functions
Add PowerShell functions to \alph-v2-cli-smoke.ps1\:
- \Get-OrchestratorState\ → Parse metadata.yaml, return state string
- \Get-PlannerArtifacts\ → List task files, validate frontmatter
- \Get-ExecutorArtifacts\ → Check .docs file + report PART 1
- \Get-ReviewerArtifacts\ → Extract verdict from report PART 2 + progress.md
- \Get-LibrarianArtifacts\ → Check knowledge progress + promoted files

### Step 3: Extend test case definitions
Update \New-SmokeTestCases\ to include 9 new checkpoint IDs from section 3.

### Step 4: Integrate into invocation flow
After agent invocation completes:
1. Run 9 new checkpoint validators
2. Set checkpoint status (pass/fail/skip)
3. Collect evidence file paths
4. Update report

### Step 5: Update report template
Extend markdown report to show orchestrator/planner/executor/reviewer/librarian evidence tables separately.

---

## 7. Example Report Output

\\\markdown
# Ralph CLI Smoke Harness Report — 2026-03-15 16:45:00 UTC+7

**Model**: gpt-5.2 | **Channel**: stable | **Overall**: ✅ PASSED

## Orchestration

| Checkpoint | Status | Evidence |
|---|---|---|
| State Transitions | ✅ | INITIALIZING → PLANNING → BATCHING → REVIEWING_BATCH → KNOWLEDGE_EXTRACTION → ITERATION_REVIEW → COMPLETE |
| Final State | ✅ | metadata.yaml: state=COMPLETE |
| Session Marker | ✅ | .active-session contains session ID |

## Planner

| Checkpoint | Status | Evidence |
|---|---|---|
| Task Creation | ✅ | iterations/1/tasks/task-1.md (YAML frontmatter valid) |
| Progress Init | ✅ | iterations/1/progress.md: [x] plan-init, [x] plan-breakdown, [/] task-1 |

## Executor

| Checkpoint | Status | Evidence |
|---|---|---|
| Artifact Creation | ✅ | .docs/smoke-test-output.md (220 bytes, header present) |
| Report PART 1 | ✅ | iterations/1/reports/task-1-report.md: Objective, Criteria, Summary |

## Reviewer

| Checkpoint | Status | Evidence |
|---|---|---|
| Task Verdict | ✅ | Report PART 2: All criteria ✅; progress.md: [x] task-1 |
| Iteration Closure | ✅ | iterations/1/review.md: Iteration closed, no active issues |

## Librarian

| Checkpoint | Status | Evidence |
|---|---|---|
| Knowledge Extraction | ✅ | progress.md: [x] plan-knowledge-extraction |
| Knowledge Staging | ✅ | knowledge/ contains staged files |
| Knowledge Promotion | ✅ | .docs/ contains promoted file + git commit exists |

## Summary
- Total Checkpoints: 13
- Passed: 13
- Skipped: 0
- Failed: 0
- Duration: 4m 32s

---
\\\

---

## 8. Known Risks & Mitigation

| Risk | Mitigation |
|---|---|
| LLM Hallucination (e.g., modifies existing .docs files) | Prompt constraint: "Do not modify existing .docs files." Executor role enforces scope. Test validates new file only. |
| Questioner Infinite Loop | Skip Questioner cycles in prompt (no brainstorm/research needed for trivial task). Planner routes directly to TASK_BREAKDOWN. |
| Librarian Skip Signal | Treat \INFO + target: Librarian + SKIP_PROMOTION\ as valid pass (not failure). Smoke test marks as "skipped" not "failed." |
| Git Unavailable | Test requires \ash\ tool for Librarian git-atomic-commit. Use \--allow-all\ in CLI flags. |
| Timing Variance | Set \PromptTimeoutSeconds\ to 300 (5 min) with 20% slack. Timeout = fail gracefully, not hang. |
| Model Nondeterminism | Validate SIDE EFFECTS (artifacts, state markers), not LLM text. Two runs may produce different text but same file structure. |

---

## Conclusion

This design enables Ralph CLI smoke harness to exercise **all 5 core agents** in a **~5 min deterministic workflow**, validating:
✅ Orchestrator state-machine  
✅ Planner task scaffolding  
✅ Executor artifact creation  
✅ Reviewer verdict & commit  
✅ Librarian knowledge pipeline  

By replacing -SkipAgentInvocation with a **minimal realistic prompt**, we gain meaningful orchestration coverage while maintaining fast, deterministic CI validation.
