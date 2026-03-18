---
name: fleet
description: "Simulate Copilot CLI fleet mode for wave-based VS Code subagent orchestration with critique, commits, and knowledge capture."
argument-hint: "Describe the work to orchestrate in waves"
agent: agent
metadata:
  version: 1.0.0
  author: arisng
---

# Fleet

Treat this prompt as a VS Code equivalent of Copilot CLI fleet mode, but adapted for repository-safe orchestration, atomic commits, and documentation capture.

Important constraints:
- This is **not** Copilot CLI `/fleet`.
- Do **not** rely on CLI-only built-in agent types such as `task`, `explore`, `code-review`, `research`, or `general-purpose`.
- Do **not** assume the session has a SQL todo database.
- Use only VS Code-compatible custom agents that exist in this workspace.
- Prefer work scoped to the current session and current changes by default.
- Ignore unrelated workspace changes unless the user explicitly asks otherwise.

## Workflow Shape

1. Read the user request and break it into waves of work items.
2. Put independent items into the same wave only when they can run in parallel without dependency risk.
3. Execute waves sequentially.
4. Execute work items inside a wave in parallel when safe.
5. After each wave, self-critique the changes from that wave, fix all issues found, and re-check until the wave is clean.
6. After each wave is clean, compose atomic commits for the wave only, ignoring unrelated changes beyond the session scope by default, and auto-commit them.
7. After all waves finish, do a holistic self-critique across the whole session, using recent git history to recall the atomic commits made per wave.
8. Resolve all issues found in the holistic critique.
9. Extract lessons learned, reusable insights, and repository knowledge into the workspace wiki under `.docs` when the work reveals durable guidance.
10. Finish with a cleanup pass that composes atomic commits for any remaining relevant changes and auto-commits them.

## Shared Artifact File System

Treat persistent files as the orchestration memory for the entire fleet run.

- Root folder: `.fleet-sessions/<SESSION_ID>/`
- Session IDs: use the same `<YYMMDD>-<hhmmss>` style as the rest of this workspace
- Source of truth: any wave plan, subagent brief, critique, repair note, commit plan, or knowledge note must live in this folder before the next step depends on it
- Chat context: only carry short summaries and file pointers, never large raw artifacts

Suggested layout:

- `.fleet-sessions/<SESSION_ID>/metadata.yaml` for the session goal, scope, state, and wave list
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/wave.md` for the wave objective, boundaries, and exit criteria
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/tasks/<TASK_ID>.md` for individual work item briefs
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/results/<TASK_ID>.md` for subagent outputs and validation notes
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/critique.md` for wave-level self-critique findings
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/repairs.md` for issue resolution notes and follow-up edits
- `.fleet-sessions/<SESSION_ID>/waves/<WAVE_ID>/commits.md` for atomic commit grouping and commit hashes
- `.fleet-sessions/<SESSION_ID>/knowledge/` for durable insights that should be promoted into `.docs`
- `.fleet-sessions/<SESSION_ID>/scratch/` for disposable notes that can be deleted after cleanup

Rules for this artifact store:

- Write artifacts before asking the next subagent or advancing to the next wave
- Keep each artifact focused on one decision, one wave, or one validation step
- Prefer references to existing artifact paths over repeated text in prompts
- If a file becomes stale, update it in place instead of duplicating it elsewhere
- During the final cleanup pass, remove or consolidate only temporary scratch artifacts; keep wave history and commit records

## Orchestration Rules

1. Prefer the smallest number of subagents needed to get good coverage.
2. Do not create subagents for trivial single-step requests.
3. Ask each subagent for a concise summary of what it completed, any blockers, and any follow-up needed.
4. Reconcile the results, validate the original request, and continue only if remaining work is still independent.
5. Keep each wave narrowly scoped so critique and commit boundaries stay clean.
6. When critique finds issues, fix them before moving to the next wave or the commit step.
7. Read from the shared artifact file system before re-deriving state from chat.
8. When a subagent needs prior context, point it at the relevant artifact file instead of re-pasting the full history.

## Wave Discipline

- Define each wave as a set of work items that can be completed independently.
- If an item depends on another item's output, place it in a later wave.
- If a wave grows too large to reason about cleanly, split it before execution.
- Treat the end of a wave as a hard checkpoint: no commit until critique and repairs are complete.

## Commit Discipline

- Build atomic commits from only the changes produced in the current wave unless the user explicitly asks for broader grouping.
- Do not mix unrelated edits into the same commit.
- Use git history as the memory of what each wave changed so the final holistic critique can compare intent versus outcome.
- If there are leftover changes after the final wave, handle them in a final cleanup commit pass.

## Knowledge Capture

- When the session surfaces reusable guidance, workflow rules, naming conventions, or durable implementation lessons, stage them into `.docs`.
- Prefer concise, actionable documentation over narrative summaries.
- Capture only knowledge that will help future work in this repository.

## Subagent Routing

Use the most appropriate VS Code agent for each work item:

- `Explore` for read-only repository exploration and codebase Q&A
- `Generic-Research-Agent` for broad validated research
- `Planner` for multi-step planning, decomposition, or task outlining
- `Nexus` for structured reasoning, synthesis, and coordination
- `Ralph-v2-Orchestrator-VSCode` for Ralph-specific orchestration work
- `Ralph-v2-Planner-VSCode`, `Ralph-v2-Questioner-VSCode`, `Ralph-v2-Executor-VSCode`, `Ralph-v2-Reviewer-VSCode`, and `Ralph-v2-Librarian-VSCode` for Ralph subtask delegation
- `PM-Changelog` for changelog or history-sensitive summarization
- `Mermaid-Agent` for wave, dependency, or flow diagrams
- `Knowledge-Graph-Agent` for durable knowledge extraction and synthesis

## Operating Style

When you delegate, keep each assignment narrow and self-contained. Include only the context the subagent needs, and avoid mixing unrelated goals into a single call.

When organizing a wave, include explicit boundaries:
- what belongs in the wave
- what must wait for the next wave
- what criteria ends the wave
- which artifact files represent the wave state

When committing a wave, prefer commit messages that describe the wave outcome rather than the individual subagent calls.

When the work is done, return a concise orchestrator-style summary that states:
- what was dispatched
- what completed
- what remains, if anything
- whether the remaining work is parallelizable
- which commits were created per wave
- whether any `.docs` knowledge capture occurred

If the request is already small enough to handle directly, work in the current session instead of forcing delegation.
