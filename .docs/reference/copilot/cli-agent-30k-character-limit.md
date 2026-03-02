---
category: reference
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/plan.md
  - iterations/7/questions/feedback-driven.md
  - iterations/7/reports/task-7-report.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
---

# Copilot CLI Agent 30K Character Limit

## Scope

The character limit that applies to custom agent prompt bodies in GitHub Copilot CLI.

## Key Facts

- **Limit**: 30,000 characters maximum for agent prompt bodies.
- **What counts**: Only the Markdown content **below** the YAML frontmatter counts against the limit. The official docs state: *"Define the agent's behavior, expertise, and instructions in the Markdown content below the YAML frontmatter. The prompt can be a maximum of 30,000 characters."*
- **What does NOT count**: YAML frontmatter (including `name:`, `description:`, `tools:`, `mcp-servers:`, `metadata:`, etc.) is excluded from the character count.
- **Practical impact**: For agents near the limit, the ~200–500 chars of frontmatter provide additional headroom beyond a naive full-file measurement.

## Budget Analysis (Ralph-v2 CLI Agents, Iteration 7)

| Agent | Instruction Chars | Agent Body Chars | Combined | vs 30K | Strategy |
|-------|-------------------|------------------|----------|--------|----------|
| Executor | 11,813 | 1,851 | 13,664 | −16,336 | Full embed |
| Questioner | 16,129 | 1,780 | 17,909 | −12,091 | Full embed |
| Planner | 27,733 | 1,505 | 29,238 | −762 | Full embed (tight) |
| Reviewer | 33,750 | 1,565 | 35,315 | +5,315 | Trimmed embed |
| Librarian | 41,942 | 1,523 | 43,465 | +13,465 | Trimmed embed |
| Orchestrator | 44,320 | 2,072 | 46,392 | +16,392 | Excluded |

## Measurement Method

Body char count is measured by:
1. Reading the agent file content as a string.
2. Finding the second `---` delimiter (end of YAML frontmatter).
3. Counting `.Length` of all content after that delimiter.

## Source

- Official docs: https://docs.github.com/en/copilot/reference/custom-agents-configuration
- Verified in iteration 7 via Q-FDB-004 research and task-7 end-to-end validation.
