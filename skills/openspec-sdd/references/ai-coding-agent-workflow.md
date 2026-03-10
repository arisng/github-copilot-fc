# AI Coding Agent Workflow

Read this reference when an AI coding agent needs to work on anything under `openspec/` and cannot invoke `/opsx:*` slash commands directly.

## Core Rule

Treat `openspec/` as a protocol-governed area.

- `openspec/specs/**` contains protocol-governed current-state artifacts.
- `openspec/changes/**` is the editable proposal surface. The `archive/` subdirectory holds completed changes and should be treated as read-only.
- `openspec/config.yaml` is workspace-wide policy and context, so change it deliberately.

The agent should not make ad hoc edits to main specs when the requested work is really a change proposal, implementation cycle, or archive step.

## Intent Routing

| User intent                                                  | Agent action                                                                                                              |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Understand a problem, compare options, inspect current specs | Follow the `explore` workflow. Read existing specs and active changes, but do not implement or mutate code.               |
| Add or change spec behavior                                  | Create or continue an OpenSpec change under `openspec/changes/<change-name>/`.                                            |
| Implement approved work                                      | Use the `apply` workflow against the active change and update `tasks.md` as work completes.                               |
| Merge approved deltas into current specs                     | Use the `archive` workflow, including validation and delta merge checks.                                                  |
| Capture existing undocumented behavior for the first time    | Use brownfield baseline capture. This is the narrow exception where direct creation under `openspec/specs/**` is allowed. |
| Abandon a change that is no longer needed                    | Delete the change folder from `openspec/changes/`.                                                                        |

> **Custom profile commands** add intents not covered by this table (e.g., verify implementation, sync without archiving, onboard a new user). When the custom profile is enabled, consult the generated skill files for these commands (see note below the Slash Command Translation table).

## Slash Command Translation

If the environment cannot invoke `/opsx:*` directly, treat those names as aliases for the following actions:

| Alias           | Skill-first route                                 | CLI fallback                                                                 |
| --------------- | ------------------------------------------------- | ---------------------------------------------------------------------------- |
| `/opsx:explore` | `.github/skills/openspec-explore/SKILL.md`        | `openspec list --json` plus read-only investigation                          |
| `/opsx:propose` | `.github/skills/openspec-propose/SKILL.md`        | `openspec new change`, `openspec status`, `openspec instructions <artifact>` |
| `/opsx:apply`   | `.github/skills/openspec-apply-change/SKILL.md`   | `openspec status`, `openspec instructions apply --change <name> --json`      |
| `/opsx:archive` | `.github/skills/openspec-archive-change/SKILL.md` | `openspec validate`, sync assessment, `openspec archive <name>`              |

The agent should execute the matching workflow directly. Do not stop at a recommendation like "run `/opsx:propose`" when the agent can perform the equivalent workflow itself.

> **Custom profile commands** (`/opsx:new`, `/opsx:continue`, `/opsx:ff`, `/opsx:verify`, `/opsx:sync`, `/opsx:bulk-archive`, `/opsx:onboard`) are not in this table. When the custom profile is enabled via `openspec config profile` → `openspec update`, each command generates its own `.github/skills/openspec-<command>/SKILL.md` and `.github/prompts/opsx-<command>.prompt.md`. Route through those generated skill files using the same skill-first pattern. This workspace currently uses the core profile (4 commands above).

## Allowed Edit Surface

| Path                          | Default policy                                            | Notes                                                                       |
| ----------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- |
| `openspec/changes/**`         | Editable                                                  | Normal place for proposal, delta specs, design, and tasks.                  |
| `openspec/specs/**`           | Read-only during active change work                       | Update through sync or archive, not by ad hoc edits.                        |
| `openspec/config.yaml`        | Restricted                                                | Edit only when schema, project context, or generation rules need to change. |
| `.github/skills/openspec-*`   | Editable                                                  | Use when adapting OpenSpec workflow entry points for AI agents.             |
| `.github/prompts/opsx-*`      | Reference only unless intentionally maintaining prompt UX | These are useful for human UX but are not the primary AI-agent entry point. |
| `openspec/changes/archive/**` | Read-only                                                 | Completed changes; do not edit archived content.                            |
| `skills/openspec-sdd/**`      | Editable                                                  | The SDD skill package itself, including this reference document.            |
| `scripts/openspec/**`         | Editable                                                  | OpenSpec validation and utility scripts.                                    |

## Namespace Guidance

Use `openspec/specs/<workflow>/<domain>/spec.md` when the repository may host more than one top-level workflow or system. This keeps domain names reusable without collisions.

Example:

```text
openspec/
  specs/
    ralph-v2-orchestration/
      session/spec.md
      planning/spec.md
      review/spec.md
```

Use `openspec/specs/<domain>/spec.md` only when the repository clearly has one top-level spec family.

> **Note:** Workspace-level instructions (e.g., `openspec-protocol.instructions.md`) may impose stricter scoping rules than the generic guidance above. Always check for workspace-specific directory conventions before choosing a namespace layout.

## Recommended Agent Sequence

1. Run `openspec list --json` to understand current changes and spec inventory.
2. Decide whether the task is `explore`, `propose`, `apply`, `archive`, or brownfield capture.
3. If the task changes established behavior, create or continue `openspec/changes/<change-name>/` before editing any spec content.
4. Use `openspec status --change <name> --json` and `openspec instructions ... --json` to drive artifact creation or implementation.
5. Validate before archive or sync.
6. Only after the protocol steps are satisfied should current specs be updated.

## Enforcement Strategy

Instruction-level enforcement is the baseline: the agent is told to load `openspec-sdd` and route through the OpenSpec workflow.

For stronger enforcement, consider adding a `preToolUse` hook that blocks direct edits to `openspec/specs/**` unless an explicit protocol override or approved sync/archive context is present. No such hook exists yet in this workspace — this is a forward-looking recommendation.

When implemented, the usual pattern is to combine the hook with a short-lived approval marker created by an approved OpenSpec workflow command. Because hooks are deterministic and chat context is not, this provides reliable enforcement beyond instruction-level rules.