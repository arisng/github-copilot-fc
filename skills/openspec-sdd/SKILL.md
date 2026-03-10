---
name: openspec-sdd
description: >-
  Spec-driven development (SDD) using OpenSpec with GitHub Copilot. Use when initializing
  OpenSpec in a project, writing specifications (requirements + scenarios), proposing changes
  with delta specs, designing and breaking down tasks, implementing from tasks.md, verifying
  against specs, syncing/archiving completed changes, managing the openspec/ directory,
  or adopting specs in existing brownfield codebases.
  Triggers: "openspec", "spec-driven", "SDD", "write specs", "propose a change",
  "delta spec", "archive change", "opsx", "/opsx:", "GIVEN/WHEN/THEN scenarios",
  "requirements specification", "change proposal", "brownfield specs", "verify implementation".
---

# OpenSpec Spec-Driven Development

Spec-driven development (SDD) with OpenSpec: specify what to build before writing code, track changes as structured proposals, keep specs as living documentation.

**Principle**: Fluid, iterative, brownfield-first. Artifacts are enablers, not gates.

**Source**: <https://github.com/Fission-AI/OpenSpec>

## Prerequisites

- Node.js >= 20.19.0
- `npm install -g @fission-ai/openspec@latest`
- Verify installation: `openspec --version` (if not found → `npm install -g @fission-ai/openspec@latest`)
- Initialize: `openspec init --tools github-copilot` (creates `.github/skills/` and `.github/prompts/`)

## Directory Structure

```
project-root/
├── .github/
│   ├── skills/openspec-*/SKILL.md   # Copilot skill files (auto-generated)
│   └── prompts/opsx-*.prompt.md     # Copilot slash commands (auto-generated)
└── openspec/
    ├── config.yaml                  # Project context, schema, artifact rules
    ├── specs/<workflow>/<domain>/spec.md  # Preferred for shared workspaces with multiple systems
    │                                      # specs/<domain>/spec.md is acceptable only for one top-level system
    ├── changes/<change-name>/       # Active change proposals
    │   ├── .openspec.yaml           # Metadata (schema, created date)
    │   ├── proposal.md              # Why, what changes, capabilities, impact
    │   ├── specs/<workflow>/<domain>/spec.md  # Delta specs (ADDED/MODIFIED/REMOVED/RENAMED)
    │   ├── design.md                # Technical approach, architecture decisions
    │   └── tasks.md                 # Implementation checklist
    └── changes/archive/             # Completed changes (YYYY-MM-DD-<name>/)
```

For a single-system repository, `openspec/specs/<domain>/spec.md` is fine. For a repository that hosts multiple workflows or products, group domains under a stable namespace such as `openspec/specs/<workflow>/<domain>/spec.md` to avoid collisions and make cross-workflow ownership explicit.

## Core Workflow

Default `core` profile — 4 commands for end-to-end flow:

```
/opsx:explore  →  Think, investigate, clarify (no artifacts, no code)
/opsx:propose  →  Create change + all planning artifacts in one step
/opsx:apply    →  Implement tasks from tasks.md checklist
/opsx:archive  →  Validate, merge delta specs, move to archive
```

**Typical flow**: `propose` → `apply` → `archive`.
Use `explore` before `propose` when the problem is unclear.

## AI Coding Agent Adaptation

The `/opsx:*` names are workflow aliases, not a required user interface. If the environment cannot invoke slash prompts directly, execute the equivalent OpenSpec workflow through skills or CLI steps instead of stopping at "run `/opsx:*`".

| Alias | AI-agent equivalent |
|---|---|
| `/opsx:explore` | Use `.github/skills/openspec-explore/SKILL.md` behavior or follow the explore rules directly |
| `/opsx:propose` | Use `.github/skills/openspec-propose/SKILL.md` or run `openspec new change`, `openspec status`, and `openspec instructions` to create artifacts |
| `/opsx:apply` | Use `.github/skills/openspec-apply-change/SKILL.md` or run `openspec instructions apply --change <name> --json` and implement tasks |
| `/opsx:archive` | Use `.github/skills/openspec-archive-change/SKILL.md` or run the archive workflow with validation and sync checks |

When operating as an AI coding agent, read [references/ai-coding-agent-workflow.md](references/ai-coding-agent-workflow.md) before changing anything under `openspec/`.

### Custom Profile Commands

Enable: `openspec config profile` → select custom → `openspec update`.

| Command | Purpose |
|---|---|
| `/opsx:new` | Scaffold change directory only (no artifacts) |
| `/opsx:continue` | Create next artifact based on dependency graph |
| `/opsx:ff` | Fast-forward: generate all planning artifacts at once |
| `/opsx:verify` | Validate implementation against specs (3 dimensions) |
| `/opsx:sync` | Merge delta specs into main specs without archiving |
| `/opsx:bulk-archive` | Archive multiple completed changes with conflict detection |
| `/opsx:onboard` | Guided walkthrough for new users |

> **Skill generation**: When the custom profile is enabled, `openspec update` generates a dedicated skill file (`.github/skills/openspec-<command>/SKILL.md`) and prompt file (`.github/prompts/opsx-<command>.prompt.md`) for each custom command, enabling the same skill-first routing pattern used by core commands.

## Spec Format

Specs in `openspec/specs/<workflow>/<domain>/spec.md` or, for single-system repositories, `openspec/specs/<domain>/spec.md`:

```markdown
# <Domain> Specification

## Purpose
High-level description of this capability.

## Requirements

### Requirement: <Name>
The system SHALL/MUST/SHOULD/MAY <behavior statement>.

#### Scenario: <Scenario Name>
- **GIVEN** <precondition>
- **WHEN** <action>
- **THEN** <expected outcome>
- **AND** <additional outcome>
```

**Rules**: RFC 2119 keywords for obligation. GIVEN/WHEN/THEN for scenarios. Externally observable behavior only — implementation details go in `design.md`.

## Change Artifacts

For detailed templates of each artifact, see [references/artifact-templates.md](references/artifact-templates.md).

**Summary of artifacts in each change folder:**

| Artifact | Purpose | Key content |
|---|---|---|
| `proposal.md` | Why + what | Why, what changes, capabilities (new + modified), impact |
| `specs/<workflow>/<domain>/spec.md` | Delta specs | ADDED/MODIFIED/REMOVED/RENAMED requirements |
| `design.md` | How | Technical approach, architecture decisions, file changes |
| `tasks.md` | Checklist | Phased tasks with `- [ ]` / `- [x]` checkboxes |

**Delta merge order during archive**: RENAMED → REMOVED → MODIFIED → ADDED.

## Config

`openspec/config.yaml`:

```yaml
schema: spec-driven

context: |
  Tech stack: TypeScript, React, Node.js
  Testing: Vitest for unit tests

rules:
  proposal:
    - Include rollback plan for risky changes
  specs:
    - Use GIVEN/WHEN/THEN for all scenarios
  tasks:
    - Each task must be independently verifiable
```

- `schema`: Default workflow schema
- `context`: Project background injected into all artifacts (max 50KB, keep concise)
- `rules`: Per-artifact generation constraints

## Agent Decision Guide

### Situation → Action

| Situation | Action |
|---|---|
| Problem is unclear or complex | `/opsx:explore` — think, investigate, clarify. Never write code. |
| Ready to plan + implement a feature | `/opsx:propose` → `/opsx:apply` → `/opsx:archive` |
| Need granular artifact control | `/opsx:new` → `/opsx:continue` (repeat) → `/opsx:apply` |
| Multiple small changes to batch | `/opsx:propose` each → `/opsx:bulk-archive` |
| Implementation done, need validation | `/opsx:verify` |
| Specs changed mid-implementation | `/opsx:sync` then continue `/opsx:apply` |
| New contributor needs orientation | `/opsx:onboard` |
| Existing codebase, no specs yet | See [Brownfield Adoption](#brownfield-adoption) |
| Change should be abandoned | Delete the change folder from `openspec/changes/` |
| Tasks need revision mid-implementation | Edit `tasks.md` directly, then continue `/opsx:apply` |
| Multiple changes touch same spec domain | `/opsx:bulk-archive` handles conflict detection automatically |

### /opsx:explore — Rules

- Act as thinking partner: ask questions, challenge assumptions, compare options
- Investigate codebase: read files, search code, map architecture
- Check existing state: `openspec list --json`, read existing artifacts
- Visualize with ASCII diagrams when helpful
- Surface risks and unknowns
- Offer to capture insights into artifacts — but never auto-capture
- **Never write code or implement features during explore**
- When insights crystallize → suggest `/opsx:propose`

### /opsx:apply — Implementation Workflow

1. Run `openspec status --change "<name>" --json` to check artifact state
2. Read `tasks.md` — identify incomplete tasks (`- [ ]`)
3. For each task:
   - Reference delta specs for behavioral requirements (primary: what to implement)
   - Consult `design.md` for technical guidance (secondary: how to implement)
   - Implement the code change
   - Mark task `- [x]` in `tasks.md`
4. After all tasks complete → `/opsx:verify` (if available) → `/opsx:archive`
5. If interrupted, `/opsx:apply` resumes from where it left off

### /opsx:verify — Three Dimensions

| Dimension | Checks |
|---|---|
| **Completeness** | All tasks in tasks.md done? All requirements implemented? All scenarios covered? |
| **Correctness** | Implementation matches spec intent? Edge cases handled? Error states align? |
| **Coherence** | Design decisions reflected in code structure? Naming consistent with design.md? |

Issues reported as CRITICAL (blocks archive), WARNING (highlight), or SUGGESTION.

### /opsx:archive — Step by Step

1. Validates task completion in `tasks.md` (incomplete tasks prompt confirmation)
2. Validates delta spec structure (invalid markers block archive)
3. Merges delta specs: RENAMED → REMOVED → MODIFIED → ADDED
4. Moves change folder to `openspec/changes/archive/YYYY-MM-DD-<name>/`

Use `--no-validate` to skip validation. Use `-y` to skip confirmation prompts.

## Brownfield Adoption

Introduce OpenSpec to an existing codebase with no specs:

### Step 1: Initialize

```bash
openspec init --tools github-copilot
```

Creates `openspec/` structure + Copilot integration files in `.github/`.
If `openspec/` already exists, enters extend mode (adds tools without recreating).

### Step 2: Configure project context

Edit `openspec/config.yaml` with tech stack, conventions, constraints:

```yaml
schema: spec-driven
context: |
  Existing Express.js API with PostgreSQL.
  Authentication via JWT tokens.
  All endpoints under /api/v2/.
```

### Step 3: Explore and document existing behavior

```
/opsx:explore
```

Investigate the existing codebase. Map current architecture, identify domains, surface undocumented behaviors. Use this to understand what specs are needed.

### Step 4: Write initial specs incrementally

For each domain identified during exploration, create specs describing **current** behavior:

```bash
# Create spec file manually
# Single-system repo:    mkdir -p openspec/specs/auth
# Multi-workflow repo:   mkdir -p openspec/specs/<workflow>/auth
# Then write the spec capturing existing behavior
```

Write specs for what the system **does today**, not what it should do. Use `/opsx:propose` for any **new** changes on top.

This manual creation step is the main exception to the "change specs through change proposals" rule. It is for first-time baseline capture of current behavior, not routine edits to established specs.

### Step 5: Evolve with changes

From this point, all new features and modifications follow the standard workflow:
`/opsx:propose` → `/opsx:apply` → `/opsx:archive`

Each archived change automatically merges delta specs into the main specs, keeping documentation evergreen.

## Current-Spec Mutation Rule

After a domain has been established, treat `openspec/specs/**` as protocol-governed current-state artifacts.

- Do not directly edit `openspec/specs/**` for new behavior, changed behavior, renamed requirements, or removed requirements.
- Stage those changes in `openspec/changes/<change-name>/specs/**` first.
- Update main specs only through the sync or archive step.
- Treat `openspec/config.yaml` as protocol-governed too; change it deliberately when project-wide rules or context change.
- Use direct edits to current specs only for explicit brownfield baseline capture or a user-approved repair of previously corrupted synced content.

For the full mutation policy and enforcement details, see [references/ai-coding-agent-workflow.md](references/ai-coding-agent-workflow.md).

## CLI Quick Reference

For full CLI details and flags, see [references/cli-reference.md](references/cli-reference.md).

| Command | Purpose |
|---|---|
| `openspec init [--tools github-copilot]` | Initialize project + Copilot integration |
| `openspec update [--force]` | Regenerate Copilot skill/prompt files |
| `openspec list [--specs\|--changes] [--json]` | List specs or active changes |
| `openspec show <item> [--json]` | Display specific change or spec |
| `openspec status --change "<name>" [--json]` | Artifact completion status for a change |
| `openspec instructions <artifact> [--json]` | Get enriched instructions for next artifact |
| `openspec validate [<id>] [--all]` | Validate changes/specs structure |
| `openspec archive [change-name] [-y]` | Archive completed change |
| `openspec config list` | Show current configuration |
| `openspec config profile [preset]` | Set workflow profile (core/custom) |

## Spec Quality Checklist

Before finalizing any spec artifact:

- [ ] Every requirement uses RFC 2119 keywords (SHALL/MUST/SHOULD/MAY)
- [ ] Every requirement has at least one scenario
- [ ] Scenarios use GIVEN/WHEN/THEN format with bold keywords
- [ ] No implementation details in specs (those go in design.md)
- [ ] Delta specs use correct markers (ADDED/MODIFIED/REMOVED/RENAMED)
- [ ] REMOVED requirements include deprecation reason
- [ ] RENAMED requirements include FROM:/TO: mapping

## Error Handling

| Failure | Action |
|---|---|
| `openspec` not found | Install: `npm install -g @fission-ai/openspec@latest` |
| `validate` fails | Read `--json` output → fix CRITICAL issues first, then WARNINGs → re-validate |
| `archive` fails | Check: (a) incomplete tasks in `tasks.md`, (b) invalid delta spec markers, (c) use `--skip-specs` for non-spec changes |
| `validate --strict` fails on warnings | Resolve all WARNINGs or downgrade to non-strict if acceptable |
