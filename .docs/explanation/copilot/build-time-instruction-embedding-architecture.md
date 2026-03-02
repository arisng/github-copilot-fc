---
category: explanation
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/plan.md
  - iterations/7/review.md
  - iterations/7/reports/task-7-report.md
  - iterations/7/questions/feedback-driven.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
---

# Build-Time Instruction Embedding Architecture

## The Problem: Runtime Instruction Reading Fails

Copilot CLI custom agents reference instruction files via `> **Shared instructions**: Read [file](path)` blockquotes. At runtime, the CLI agent is expected to read the referenced `.instructions.md` file to obtain its workflow, rules, signal protocol, and contract.

This approach failed in practice:
- **Instruction files are large** — ranging from 12KB (346 lines) to 46KB (1,094 lines).
- **CLI agents truncate or skip reading** large files, silently losing critical workflow steps.
- **Signal protocol is lost** — the inter-agent communication protocol lives inside instruction files. When files aren't fully read, agents can't participate in the signal mailbox pattern.
- **No plugin.json instruction path** — the `plugin.json` schema supports `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers` but NOT `instructions`. There is no plugin-native way to deliver instruction files.

## The Solution: Embed at Build Time

Instead of relying on runtime file reading, instruction content is inlined directly into agent files during the plugin bundle build step. The result is a self-contained agent file where the full instruction content is part of the agent's prompt body.

### Pipeline Overview

```
Source Agent File     Instructions Dir        Bundle Output
  (EMBED marker)   +  (*.instructions.md)  →  (merged agent)
       │                     │                      │
       ▼                     ▼                      ▼
  YAML frontmatter     Read + strip            YAML frontmatter
  # Title              frontmatter/H1          # Title
  <!-- EMBED: f.md --> ─────────────────────→   [full instruction
                                                 content inlined]
```

### Key Design Decisions

1. **Template markers, not concatenation** — Source agent files contain `<!-- EMBED: filename -->` markers. This is explicit, grep-able, and makes the embedding intent visible in version control.

2. **Replace-in-place in .build/** — The merge operates on copies in the `.build/` directory, never modifying source files. Source agent files remain minimal (frontmatter + title + marker).

3. **Instruction frontmatter stripped** — `applyTo`, `description`, and other instruction metadata are meaningless in the embedded context. Only the instruction body content is inlined.

4. **Agent frontmatter preserved verbatim** — The agent's YAML frontmatter (including `mcp-servers:`, `tools:`, `metadata:`) is never modified. The split/reassemble approach ensures frontmatter integrity.

5. **Body-only 30K limit** — Only Markdown content below YAML frontmatter counts against the 30,000-character limit. This provides ~200–500 chars of extra headroom versus a full-file measurement.

6. **Trimmed variants for over-budget agents** — Agents exceeding 30K combined chars use `.cli-embed.instructions.md` trimmed variants that remove templates, checklists, and verbose examples while preserving persona, rules, workflow, signals, and contract.

7. **Orchestrator excluded** — At 46.4K combined chars, the Orchestrator exceeds the 30K limit by 16K+ and cannot be trimmed to fit without losing core functionality. It retains the runtime instruction reference as a follow-up item.

### Integration Point

`Merge-AgentInstructions` is called by `Build-PluginBundle` in `publish-plugins.ps1`:
- **After**: Agent files are copied to `.build/agents/`.
- **Before**: Post-bundle validation (schema, section markers, char counts).

This ordering ensures the merge has access to copied files and validation catches any merge issues.

### Protected Sections

These sections are NEVER trimmed from instruction variants, as they are essential for agent operation:

| Section | Purpose | Typical Size |
|---------|---------|-------------|
| `<persona>` | Agent identity, mode definitions, hard rules | 400–1,800 chars |
| `<rules>` | Operational constraints | 500–900 chars |
| Core workflow | The actual process steps for each mode | Variable |
| `<signals>` / Signal Protocol | Inter-agent mailbox communication | 1,000–4,000 chars |
| `<contract>` | Input/Output schemas | 1,000–1,800 chars |
