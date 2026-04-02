---
name: kimi-fleet-mini
description: Multi-iteration parallel subagent orchestrator for Kimi Code CLI
type: flow
metadata: 
  author: arisng
  version: 0.2.0
---

# Fleet Flow Skill

Dispatch subagents in parallel waves to complete complex work.

## Agent Flow

```mermaid
flowchart TD
    BEGIN([BEGIN]) --> INIT[Initialize Session]
    INIT --> PLAN[Create Master Plan]
    PLAN --> WAVE{Execute Wave}
    WAVE -->|Tasks ready| DISPATCH[Dispatch Subagents]
    WAVE -->|All done| REVIEW[Review Results]
    DISPATCH --> COLLECT[Collect Results]
    COLLECT --> WAVE
    REVIEW --> VALIDATE{Validation Pass?}
    VALIDATE -->|Issues found| FIX[Create Fix Tasks]
    FIX --> WAVE
    VALIDATE -->|Clean| COMMIT[Atomic Commits]
    COMMIT --> DOCUMENT[Document Insights into Wiki]
    DOCUMENT --> END([END])
```

## Core Principles

- Dispatch independent tasks simultaneously using `Agent` tool with `run_in_background=true`
- Use `coder`, `explore`, or `plan` subagent types appropriately

## Step: COMMIT — Atomic Commits

**Trigger:** After `VALIDATE` passes with no remaining issues.

Apply the `git-atomic-commit` skill (with `git-commit-scope-constitution` as its companion):

1. **Ensure constitution exists** — check for `.github/git-scope-constitution.md`.
   - If absent, run `git-commit-scope-constitution` to generate it from the repository structure and git history before proceeding.
2. **Analyze all changes** — run `git status --short` and diff each changed file.
3. **Assign type + scope per file** — use the Tier 1/2/3 hierarchy from `git-atomic-commit`. Every file gets a `type(scope)` label before any grouping begins.
4. **Run the pre-commit verification checklist** (type mapping, scope selection, no generic types, atomic grouping, dependency order).
5. **Group into atomic commits** — files sharing the same type and related scope form one commit. Different types → separate commits.
6. **Generate conventional commit messages** — `type(scope): subject` + optional body.
7. **Execute commits in dependency order** — stage files for each commit and commit sequentially.
8. **Report** — list all commits created with their messages.

**Autonomous mode:** Execute all commits automatically without user prompts; surface a summary when done.

## Step: DOCUMENT — Document Insights into Wiki

**Trigger:** After `COMMIT` completes successfully.

Apply the `diataxis` + `diataxis-categorizer` skills to capture what was learned:

### What to document

Capture content that would benefit future iterations or agents:

| Source | Target Diátaxis category | Examples |
|--------|--------------------------|---------|
| Reusable procedures discovered during the task | **How-to guide** | "How to configure X", "How to run Y pipeline" |
| Technical facts, APIs, config options | **Reference** | Data model schemas, CLI flag lists |
| Conceptual understanding gained | **Explanation** | Why the architecture is structured this way |
| Step-by-step learning journeys | **Tutorial** | First-time setup walkthrough |

Lessons learned and gotchas **always** go into an **Explanation** page (or appended to an existing one).

### Where to write

Use the `.docs/` structure:

```
.docs/
├── tutorials/          # Learning-oriented lessons
├── how-to/             # Task-oriented guides
├── reference/          # Technical descriptions
└── explanation/        # Conceptual discussions + lessons learned
```

Apply the `diataxis-categorizer` three-rule heuristic to determine the correct sub-folder:
1. **Keyword extraction** — identify the primary domain from filename → frontmatter → H1 → body scan.
2. **Reuse check** — if a matching `<category>/<domain>/` folder exists, place the file there.
3. **Create check** — if ≥3 peers share the domain and no sub-folder exists, create it and move peers.
4. **Fallback** — store at the category root if no domain dominates.

### Process

1. Collect key insights from REVIEW and COMMIT outputs (what worked, what failed, surprises, reusable patterns).
2. For each insight, determine its Diátaxis category (How-to / Reference / Explanation / Tutorial).
3. Apply `diataxis-categorizer` to find or create the correct sub-folder path.
4. Write or append to the target `.md` file using the appropriate template from the `diataxis` skill.
5. Run `python skills/diataxis/scripts/generate_index.py` (if available) to refresh `.docs/index.md`.
6. Stage and commit documentation changes as a separate `docs(...)` commit (do **not** mix with code commits from the COMMIT step).
