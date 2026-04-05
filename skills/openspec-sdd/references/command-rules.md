# Per-Command Behavioral Rules

Detailed rules for each core OpenSpec command. Referenced from SKILL.md when implementing a specific phase.

## Contents

- [/opsx:explore — Rules](#opsx-explore--rules)
- [/opsx:apply — Implementation Workflow](#opsx-apply--implementation-workflow)
- [/opsx:verify — Three Dimensions](#opsx-verify--three-dimensions)
- [/opsx:archive — Step by Step](#opsx-archive--step-by-step)
- [Custom Profile Commands](#custom-profile-commands)

---

## /opsx:explore — Rules

- Act as thinking partner: ask questions, challenge assumptions, compare options
- Investigate codebase: read files, search code, map architecture
- Check existing state: `openspec list --json`, read existing artifacts
- Visualize with ASCII diagrams when helpful
- Surface risks, unknowns, and hidden design gaps
- Offer to capture insights into artifacts — but never auto-capture
- **Never write code or implement features during explore**
- When insights crystallize → suggest `/opsx:propose`

**When to use explore**: When the problem statement is ambiguous, multiple designs are valid, or implementation gaps could surface mid-flight. Skipping explore on complex tasks leads to hidden assumptions baked into artifacts.

---

## /opsx:apply — Implementation Workflow

1. Run `openspec status --change "<name>" --json` to check artifact state
2. Read `tasks.md` — identify incomplete tasks (`- [ ]`)
3. For each task:
   - Reference **delta specs** for behavioral requirements (primary: *what* to implement)
   - Consult **`design.md`** for technical guidance (secondary: *how* to implement)
   - Implement the code change
   - Mark task `- [x]` in `tasks.md` immediately after completing it
4. After all tasks complete → `/opsx:verify` → `/opsx:archive`
5. If interrupted, `/opsx:apply` resumes from the first incomplete task

**Mid-flight spec gaps**: If implementation reveals behavior not covered by the delta spec, update the delta spec *before* implementing the code. See the mid-flight adjustment in [e2e-simulation.md](e2e-simulation.md) for an annotated example.

---

## /opsx:verify — Three Dimensions

Run after all tasks in `tasks.md` are complete, before archiving.

| Dimension | Checks |
|---|---|
| **Completeness** | All tasks done? All requirements implemented? All scenarios covered by tests? |
| **Correctness** | Implementation matches spec intent? Edge cases handled? Error states align with scenarios? |
| **Coherence** | Design decisions reflected in code structure? Naming consistent with `design.md`? |

Issues are classified as:
- **CRITICAL** — blocks archive, must be resolved
- **WARNING** — highlighted, should be addressed
- **SUGGESTION** — informational

**Manual verify checklist** (when `/opsx:verify` is unavailable):
- [ ] `openspec validate --change <name> --all` reports no CRITICALs
- [ ] All `tasks.md` checkboxes are `- [x]`
- [ ] Tests exist for every GIVEN/WHEN/THEN scenario in the delta spec
- [ ] No undocumented behavior was added during implementation

---

## /opsx:archive — Step by Step

1. Validates task completion in `tasks.md` (incomplete tasks prompt confirmation)
2. Validates delta spec structure (invalid markers block archive)
3. Merges delta specs in order: **RENAMED → REMOVED → MODIFIED → ADDED**
4. Moves change folder to `openspec/changes/archive/YYYY-MM-DD-<name>/`

**Flags:**
- `--no-validate` — skip validation (use when validation has already been confirmed)
- `-y` — skip confirmation prompts
- `--skip-specs` — archive without merging specs (for changes that have no spec impact)

**After archive**: The `Current-Spec Mutation Rule` is in effect for all domains touched. Any future change to that domain must go through a new delta proposal.

---

## Custom Profile Commands

Enable: `openspec config profile` → select custom → `openspec update`.

On enable, `openspec update` generates a dedicated skill file (`.github/skills/openspec-<command>/SKILL.md`) and prompt file (`.github/prompts/opsx-<command>.prompt.md`) for each custom command.

| Command | Purpose |
|---|---|
| `/opsx:new` | Scaffold change directory only (no artifacts) |
| `/opsx:continue` | Create next artifact based on dependency graph |
| `/opsx:ff` | Fast-forward: generate all planning artifacts at once |
| `/opsx:verify` | Validate implementation against specs (3 dimensions) |
| `/opsx:sync` | Merge delta specs into main specs without archiving |
| `/opsx:bulk-archive` | Archive multiple completed changes with conflict detection |
| `/opsx:onboard` | Guided walkthrough for new contributors |
