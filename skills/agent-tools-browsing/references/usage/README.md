# Usage scenarios catalog

The **allowlist** axis of this skill answers *which tool names are valid*.
This catalog answers the other half: *given a goal, which tools do I call and
in what order*.

| Axis | Question | Where it lives |
|---|---|---|
| Allowlist | Which names may go in an agent's `tools:` frontmatter? | [../runtime-vocabularies.yaml](../runtime-vocabularies.yaml), [../naming-rules.md](../naming-rules.md), [../allowlist-profiles.md](../allowlist-profiles.md) |
| Usage | How do I call runtime tools to accomplish a task? | this directory |

## Why a catalog and not one big page

Each scenario is a self-contained procedure with its own gates, its own
failure modes, and its own verification. Bundling them into one page makes
every reader pay for every scenario. A catalog keeps each procedure loadable
on its own and lets the set grow without one file becoming unmaintainable.

## The scenarios

| Scenario | Runtime | Status |
|---|---|---|
| [Create a nested session in the Agent Host](agent-host-nested-session.md) | `agent-host` | verified |

## Shared references

Some material is not about one scenario but about one runtime's tool surface.
That belongs in a shared file, listed under `shared:` in the catalog, so
several scenarios of the same runtime link one page instead of repeating it.

| Shared file | Runtime | Covers |
|---|---|---|
| [Agent Host session-management tools](agent-host-session-tools.md) | `agent-host` | The session tool group, the create-versus-move distinction, the `move_session` gates, and the peer-chat nesting model |

## How to add a scenario

1. Pick the runtime. The scenario applies to exactly one — the same names mean
   different things in each, and a procedure that spans runtimes is two
   procedures.
2. Write the reference file in this directory. Name it `<id>.md`.
3. Add the entry to [catalog.yaml](catalog.yaml).
4. If the scenario is a *host-provided* tool rather than a frontmatter
   nameable one, say so in the reference file. Those tools are enabled by the
   host, not by an agent author, so an agent cannot grant them to itself.
5. Set `status` honestly. See below.

### The reference file shape

Every scenario file follows the same skeleton, so a reader who knows one
scenario knows them all:

```markdown
# <title>

**Runtime:** `<runtime>`  **Tools:** `<tool>`, `<tool>`

## When to use this
## Before you start   (the gates — settings, capabilities, preconditions)
## Steps
## Verify
## Pitfalls
```

Keep it under the workspace reference limit (`.waza.yaml` sets
`references/**/*.md` to 1000 tokens). Move anything that is not about this
scenario into a shared file rather than growing the page — that is exactly
what [agent-host-session-tools.md](agent-host-session-tools.md) is for.

### Status values

| Status | Means |
|---|---|
| `verified` | Every step was executed against a live runtime and the result observed. |
| `reported` | Grounded in the runtime's published schema or source, but not executed end to end. The file must say which parts are unverified. |
| `draft` | The procedure is not settled. Not ready to follow. |

Do not mark a scenario `verified` because the tool exists. Verify it by
running it.

## Related

- [../naming-rules.md](../naming-rules.md) — which names are valid where.
- [agent-host-session-tools.md](agent-host-session-tools.md) — the Agent Host session tool surface, shared by the agent-host scenarios.

This skill travels with its own directory, so it must not depend on files
outside it. The workspace reference for the full Agent Host tool surface
lives at `.docs/reference/copilot/vscode/copilot-vscode-agent-host-tools.md`.
