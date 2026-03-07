---
category: reference
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/reports/task-1-report.md
  - iterations/7/reports/task-4-report.md
  - iterations/7/reports/task-critique-1-1-report.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
---

# EMBED Marker Specification

## Syntax

```html
<!-- EMBED: <instruction-filename> -->
```

- The marker is an HTML comment containing the keyword `EMBED:` followed by the instruction filename.
- The filename is relative to the `instructions/` directory (e.g., `ralph-v2-executor.instructions.md`).
- Each agent source file should contain **exactly one** EMBED marker as its sole body content after the `# Title` heading.

## Examples

```markdown
# Ralph-v2 Executor (CLI)

<!-- EMBED: ralph-v2-executor.instructions.md -->
```

For agents with large instruction files that point directly to the compressed full-file:

```markdown
# Ralph-v2 Reviewer (CLI)

<!-- EMBED: ralph-v2-reviewer.instructions.md -->
```

## Processing Pipeline

`Merge-AgentInstructions` resolves markers at bundle build time:

1. **Scan** — `Get-ChildItem -Filter '*.agent.md' -Recurse` in `.build/agents/`.
2. **Split** — Separate agent YAML frontmatter from body using `(?s)^(---\r?\n.*?\r?\n---)` regex (non-greedy, preserves multiline `mcp-servers:` blocks).
3. **Match** — Find `<!-- EMBED:\s*(.+?)\s*-->` in body. If no match → skip (agent has no embedding).
4. **Read** — Load the referenced instruction file from `instructions/` directory.
5. **Strip** — Remove instruction file's YAML frontmatter (`(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$`) and first H1 header (`([regex]).Replace(content, '^# .+\r?\n', '', 1)`).
6. **Replace** — Replace the EMBED marker line with stripped instruction content using `[Regex]::Replace()` with a script block evaluator (avoids backreference interpretation).
7. **Validate** — Check body char count ≤ 30,000 and verify required section markers (`<persona>`, `<rules>`, signal protocol, `<contract>`, workflow).
8. **Write** — Reassemble frontmatter + merged body and write back in-place.

## Regex Patterns Used

| Purpose | Pattern | Notes |
|---------|---------|-------|
| Agent frontmatter split | `(?s)^(---\r?\n.*?\r?\n---)` | Non-greedy; captures multiline YAML |
| EMBED marker match | `<!-- EMBED:\s*(.+?)\s*-->` | Capture group 1 = filename |
| Instruction frontmatter strip | `(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$` | Capture group 1 = content after frontmatter |
| First H1 strip | `^# .+\r?\n` | Only first occurrence removed |
| Marker replacement | `(?m)^.*<!-- EMBED:\s*.+?\s*-->.*$` | Full-line match, multiline mode |

## Validation Markers

After merging, the function checks for these required section markers (warning on absence):

1. `<persona>` — Agent identity and hard rules
2. `<rules>` — Operational constraints
3. Signal Protocol — `Live Signals Protocol` or `Poll-Signals`
4. `<contract>` — Input/Output schemas
5. Workflow — `Workflow` or `Modes of Operation`
