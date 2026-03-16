---
date: 2026-03-14
type: Task
severity: High
status: Proposed
---

# Task: Define stable subagent alias table for Ralph-v2 orchestrator

## Objective
Ensure the Ralph-v2 orchestrator and its related instructions consistently reference subagents via a stable alias layer rather than hard-coded agent names. This prevents workflow breakage when beta channel bundles append `-beta` to agent names and avoids mismatches between orchestrator routing and bundled agent identities.

## Tasks
- [ ] Add a dedicated "Subagent alias table" section to `agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md` that lists the canonical alias and corresponding stable + beta agent names.
- [ ] Refactor orchestrator instructions to use alias identifiers when describing/routing to Planner, Questioner, Executor, Reviewer, Librarian, and any other subagent.
- [ ] Audit Ralph-v2 subagent instruction docs (e.g., planner, executor, reviewer, questioner, librarian) for hard-coded agent invocation references and update them to reference the alias contract or explain alias usage.
- [ ] Add/update a validation step (documentation or automated check) to ensure beta bundle agent name suffixing does not break the orchestrator workflow (e.g., by verifying alias mappings cover all bundled agents).

## Acceptance Criteria
- [ ] `ralph-v2-orchestrator.instructions.md` contains a clear alias mapping table and uses aliases consistently in routing descriptions.
- [ ] No workflow or instructions refer directly to raw agent names that differ between stable and beta bundles (e.g., `Ralph-v2-Planner-VSCode` vs `Ralph-v2-Planner-VSCode-beta`) in a way that would cause incorrect agent invocation.
- [ ] Beta bundle validation (existing or new) succeeds when the alias mapping is in place and no direct name references remain.
- [ ] Related Ralph-v2 subagent instruction files reference the alias contract, reducing future drift when channel naming changes.

## References
- `agents/ralph-v2/instructions/ralph-v2-orchestrator.instructions.md`
- `.docs/reference/ralph/ralph-beta-agent-frontmatter-name-contract.md`
- `openspec/specs/ralph-v2-orchestration/session/spec.md`
- `scripts/publish/build-plugins.ps1` (beta bundle rewrite logic)
