---
category: explanation
source_session: 260302-142754
source_iteration: 1
source_artifacts:
  - "Iteration 1 task-14 report (validation run)"
  - "Iteration 1 plan"
  - "Iteration 1 task-13 report (validation script creation)"
extracted_at: 2026-03-02T20:11:56+07:00
promoted: true
promoted_at: 2026-03-02T20:22:26+07:00
---

# Runtime-Agnostic Spec Abstraction

When reverse-engineering a working multi-agent system into behavioral specifications, runtime-specific terminology inevitably leaks in. Achieving true runtime agnosticism requires a deliberate two-pass validation approach, not just careful writing.

## The Problem

Agent systems are built against specific runtimes — VS Code tool namespaces, PowerShell scripts, file-system paths. When distilling behavioral contracts from these implementations, authors unconsciously carry runtime-specific language into the spec. A spec that says "writes to the session directory" implicitly assumes a file-system storage model, which prevents the spec from being implemented against a database or API backend.

## Two-Pass Approach

### Pass 1: Lexical Blocklist Scan

A data-driven scan matches spec content against a 5-category blocklist:

| Category | Examples Blocked |
|----------|-----------------|
| Editor/Runtime | VS Code, Code, Copilot, IDE, editor, terminal |
| OS/Shell | PowerShell, pwsh, bash, cmd, Windows, Linux, WSL |
| Tool Names | grep, search, git mv, npm, semantic_search |
| File Formats | .yaml, .md, .json, .ps1, frontmatter |
| Path/Filesystem | directory, folder, file path, workspace root |

This pass catches obvious leaks quickly. It uses case-sensitive regex with word boundaries so "terminal" (the OS concept) is caught while "determination" is not.

**Key rule**: Skip YAML frontmatter between `---` markers. The abstraction boundary applies to behavioral content only — frontmatter is operational metadata.

### Pass 2: Semantic Review

Lexical scanning cannot catch language that is structurally correct but semantically implies a specific runtime. Patterns to look for:

| Pattern | Why It Leaks | Replacement |
|---------|-------------|-------------|
| "writes to" / "write to" | Implies file I/O | "updates" / "persists to" / "modifies" |
| "write authority" | Implies file permissions | "mutation authority" |
| "directory structure" | Implies file system | "organizational structure" |
| "reads the file" | Implies file I/O | "retrieves the artifact" |
| "directory-based mailbox" | Implies folder as protocol | "polling-based mailbox" |

The semantic pass is inherently manual — no regex can reliably distinguish "terminal state" (abstract concept) from "terminal" (OS concept). The blocklist catches the latter; semantic review catches the former when "terminal" appears as a standalone adjective for state descriptions.

## The Abstract Vocabulary Table

A powerful technique for enforcing runtime agnosticism is to define an explicit vocabulary table that maps implementation-layer terms to abstract equivalents. This table is placed in the foundational spec (the one that defines shared concepts) and all other specs reference only the abstract terms.

Example entries:

| Implementation Term | Abstract Equivalent |
|--------------------|--------------------|
| metadata.yaml | session record |
| progress.md | progress tracker |
| plan.md | iteration plan |
| .ralph-sessions/ | session store |
| tasks/ directory | task collection |
| signals/inputs/ | signal inbox |

With this table in the foundational spec, reviewers can mechanically verify that no implementation term appears in any spec's behavioral content.

## Pitfall: PowerShell `$Matches` Clobbering

During validation tooling development, a subtle bug demonstrated why validation scripts must be carefully engineered. PowerShell's automatic `$Matches` variable is globally scoped — when a validation script performs multiple regex operations in a loop, a successful match overwrites `$Matches` and a subsequent non-matching regex does **not** clear the previous value. This caused a validator to report 513 false-positive gaps because `$Matches` from an earlier iteration's regex was carried into the next check.

**Fix**: Use explicit local capture variables (`$m = [regex]::Match(...)`) instead of relying on the automatic `$Matches` variable in validation loops. Alternatively, use negative lookbehind assertions (`(?<!-)`) to prevent partial ID matches (e.g., `DISC-001` matching inside `SC-DISC-001`).

## When to Apply This Approach

This two-pass validation is most valuable when:
- Distilling behavioral specs from an existing codebase with established conventions
- Multiple contributors author specs (blocklist enforces shared vocabulary)
- The specs might be implemented on different platforms in the future
