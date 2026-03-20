---
category: explanation
---

# Portable Skill vs Workspace-Specific Enforcement Layering

## The Problem

When a skill (e.g., `openspec-sdd`) travels across repositories, its guidance must work in diverse environments — single-system repos, multi-workflow monorepos, greenfield and brownfield codebases. But a specific workspace may need stricter rules than the skill's generic defaults.

## The Solution: Intentional Asymmetry

The three-layer architecture deliberately allows **asymmetric strictness**:

- **Portable layer** (SKILL.md + reference docs): Generic, permissive defaults. Example: "For a single-system repository, `openspec/specs/<domain>/spec.md` is fine."
- **Workspace layer** (instruction file): Stricter, workspace-specific enforcement. Example: "Never place domain specs directly under `openspec/specs/`. All domains must nest under a workflow-scoped subdirectory."

This is not a contradiction — it is intentional layering. The portable skill offers the broadest correct guidance; the workspace instruction narrows it for the current environment.

## When to Apply

Use this pattern when:
- A skill's rules depend on repository structure (single vs multi-system, naming conventions)
- The workspace has conventions that go beyond the portable skill's defaults
- The instruction file's `applyTo` scope activates only in the relevant workspace context

## Design Principles

1. **Portable artifacts never reference workspace-specific paths** — they use generic placeholders (`<workflow>`, `<domain>`)
2. **Workspace artifacts reference the portable skill** — the instruction can point to the skill for comprehensive guidance while adding enforcement
3. **The instruction file is the authority for "what must happen here"** while the skill is the authority for "what is correct in general"
4. **Terminology alignment flows from workspace authority** — when multiple artifacts describe the same concept, align the portable artifact's phrasing to match the workspace instruction's canonical terms (e.g., `<workflow>` rather than `<scope>`)

## Validation Checklist

When auditing this layering:
- Confirm portable artifacts don't accidentally adopt workspace-specific rules (over-tightening)
- Confirm workspace instructions don't contradict portable rules (only narrow them)
- Confirm both layers use consistent terminology for shared concepts
- Document the intentional asymmetry so future reviewers don't "fix" it into uniformity
