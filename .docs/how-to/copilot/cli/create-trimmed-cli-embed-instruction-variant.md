---
category: how-to
source_session: 260302-001737
source_iteration: 7
source_artifacts:
  - iterations/7/plan.md
  - iterations/7/tasks/task-2.md
  - iterations/7/tasks/task-3.md
  - iterations/7/reports/task-2-report.md
  - iterations/7/reports/task-3-report.md
extracted_at: "2026-03-02T23:42:49+07:00"
staged_at: "2026-03-02T23:47:15+07:00"
promoted: true
promoted_at: "2026-03-02T23:50:57+07:00"
deprecated: true
deprecated_reason: "CLI-embed variants were eliminated. Full instruction files are now compressed to fit within 30K. See agents/ralph-v2/README.md."
---

> **DEPRECATED** — This how-to is no longer applicable. The `.cli-embed.instructions.md` trimmed-variant pattern was eliminated. Full instruction files (reviewer: 26K, librarian: 27K) are now compressed to fit within the 30K CLI body limit. Embed markers in CLI agent files point directly to the full instruction files. See [agents/ralph-v2/README.md](../../../../../agents/ralph-v2/README.md) for current state.

# How to Create a Trimmed CLI-Embed Instruction Variant

## Goal

Create a reduced-size variant of an instruction file that fits within the 30K body-char limit when embedded into a CLI agent file at bundle time.

## Naming Convention

Trimmed variants use the `.cli-embed.` infix:

```
instructions/ralph-v2-<role>.cli-embed.instructions.md
```

Examples:
- `ralph-v2-reviewer.cli-embed.instructions.md` (trimmed from `ralph-v2-reviewer.instructions.md`)
- `ralph-v2-librarian.cli-embed.instructions.md` (trimmed from `ralph-v2-librarian.instructions.md`)

The EMBED marker in the agent source file references the trimmed variant:

```html
<!-- EMBED: ralph-v2-reviewer.cli-embed.instructions.md -->
```

## Prerequisites

1. Know the agent body char count (the non-frontmatter content of the `.agent.md` file).
2. Calculate the maximum instruction body size: `30,000 − agent_body_chars = max_instruction_chars`.
3. Identify which sections to trim based on the budget gap.

## Steps

### 1. Calculate the Budget Gap

```
gap = (instruction_chars + agent_body_chars) − 30,000
```

Add a safety margin of ~500–1,000 chars to account for line-ending differences.

### 2. Identify Trimming Targets (Safe to Remove)

| Category | Examples | Typical Savings |
|----------|----------|-----------------|
| Execution checklists | Step-by-step verification checklists | 3,000–5,000 chars |
| Verbose templates | Full markdown code block templates with placeholders | 1,000–3,000 chars |
| Quick reference sections | Diátaxis Quick Reference, tool catalogs | 1,000–2,000 chars |
| Condensable examples | Detailed walkthrough examples | 500–2,000 chars |
| Redundant documentation | Sections duplicated in other knowledge sources | Variable |

### 3. Identify Protected Sections (NEVER Trim)

| Section | Reason |
|---------|--------|
| `<persona>` | Agent identity and hard rules |
| `<rules>` | Operational constraints |
| Core workflow steps | Mode logic (the actual process the agent follows) |
| Signal protocol (`<signals>`) | Inter-agent communication — 2–4K chars, critical |
| `<contract>` | Input/Output schemas |

### 4. Create the Trimmed File

1. Copy the full instruction file to the new `.cli-embed.` path.
2. Replace the YAML frontmatter with minimal `description`-only frontmatter (no `applyTo` — meaningless in embedded context).
3. Remove identified trimming targets.
4. Condense verbose sections to compact equivalents (tables instead of code blocks, headings-only instead of full templates).
5. Verify all protected sections remain verbatim.

### 5. Verify

```powershell
# Count body chars (after YAML frontmatter)
$content = Get-Content $file -Raw
$bodyStart = $content.IndexOf("`n---`n", $content.IndexOf("---") + 3) + 5
$body = $content.Substring($bodyStart)
Write-Host "Body chars: $($body.Length)"

# Verify protected sections
@('<persona>', '<rules>', '<contract>', '<signals>', 'Live Signals Protocol') | ForEach-Object {
    $found = Select-String -Path $file -Pattern $_ -SimpleMatch
    Write-Host "$_`: $(if ($found) { 'PRESENT' } else { 'MISSING' })"
}
```

## Real-World Examples

### Reviewer (needed ≥5,315 chars trimmed → achieved 6,500)

| Target | Action | Savings |
|--------|--------|---------|
| Cross-Agent Normalization Checklist | Fully removed | ~3,400 chars |
| playwright-cli reference section | Fully removed | ~1,000 chars |
| Session Review template | Condensed to headings-only list | ~2,000 chars |

Result: 26,211 body chars (margin: 2,224)

### Librarian (needed ≥13,465 chars trimmed → achieved 14,111)

| Target | Action | Savings |
|--------|--------|---------|
| Execution Checklists (4 modes) | Fully removed | ~5,000 chars |
| COMMIT workflow | Condensed to prose bullets | ~3,400 chars |
| Preflight Gates (3 gates) | Condensed to table | ~2,700 chars |
| Knowledge Progress template | Condensed to status table | ~2,400 chars |
| Diátaxis Quick Reference | Fully removed | ~1,425 chars |
| Frontmatter Template | Condensed to key fields | ~1,100 chars |

Result: 27,619 body chars (margin: 858)
