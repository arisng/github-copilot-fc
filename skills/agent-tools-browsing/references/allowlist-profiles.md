# Allowlist profiles

A profile is a starting point for the `tools:` list, not the answer. Adjust it to the agent's actual job, then validate with `browse_tools.py check`.

Emit any profile as a ready-to-paste block:

```bash
python3 scripts/browse_tools.py profile --runtime cli --profile implementer --format yaml
```

## read-only

Inspect code and answer questions. No writes, no shell. Safe to expose to untrusted input.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search]` |
| `agent-host` | `[view, search]` |
| `vscode` | `[read, search]` |
| `github-copilot` | `[read, search]` |

Drop `search` for a narrow reader that only needs specific files. Add `grep`/`glob` in the CLI and Agent Host when the agent needs literal pattern matching rather than the conceptual search alias.

## read-only-with-shell

Inspect code and run commands, for example to run the test suite. The shell is the escape hatch: it can write, so this profile is not a containment boundary.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search, bash]` |
| `agent-host` | `[view, search, bash]` |
| `vscode` | `[read, search, execute]` |
| `github-copilot` | `[read, search, execute]` |

On Windows, `powershell` is the native shell spelling in the CLI and Agent Host. Use `read_bash` or `read_powershell` when the agent must read a long-running command's output instead of blocking on it.

## implementer

Change files and verify the result.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search, edit, bash]` |
| `agent-host` | `[view, search, edit, bash]` |
| `vscode` | `[read, search, edit, execute]` |
| `github-copilot` | `[read, search, edit, execute]` |

`edit` covers file creation as well as modification. Do not add `create` or `apply_patch` on top of it — no shipped agent uses them, and `create` was reported as silently ignored in the CLI's agent frontmatter.

## reviewer

Review a diff without changing anything.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search, bash]` |
| `agent-host` | `[view, search, bash]` |
| `vscode` | `[read, search]` |
| `github-copilot` | `[read, search]` |

The CLI and Agent Host need the shell to run the project's test or lint command as part of the review. VS Code has `execute/testFailure` and `execute/createAndRunTask` when a review must run tasks.

## orchestrator

Plan and delegate to subagents.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search, edit, bash, task]` |
| `agent-host` | `[view, search, edit, bash, task]` |
| `vscode` | `[read, search, edit, execute, agent]` |
| `github-copilot` | `[read, search, edit, execute, agent]` |

`task` is the CLI and Agent Host delegation tool. `agent` is the VS Code and cloud-agent equivalent. Add `read_agent` and `list_agents` only when the orchestrator must inspect a running subagent, and `write_agent` only when it must steer one.

## research

Investigate the web and external repositories.

| Runtime | `tools:` |
|---|---|
| `cli` | `[view, search, web_fetch]` |
| `agent-host` | `[view, search, web_fetch]` |
| `vscode` | `[read, search, web]` |
| `github-copilot` | `[read, search, web]` |

`web_fetch` is a documented CLI built-in that no shipped agent uses, so treat it as advisory. For GitHub repository research, add the MCP server rather than a web tool:

```yaml
tools:
  - view
  - search
  - web_fetch
  - github-mcp-server/*
```

A whole-server entry keeps the list short while giving the agent the full server. Narrow it to individual tools when the agent should not have write access.

## Tightening an existing list

Work from the intent backwards rather than deleting names one at a time.

1. Write the intent in one sentence: "the agent may do exactly X and nothing else".
2. Map each clause of the intent to the capability that provides it.
3. Emit that minimal set, then add back only the names the agent provably needs.
4. Validate the result and read every advisory and rejection it returns.
5. Confirm the list contains no `*` and no name that was silently ignored.

Removing a name is a restriction only if that capability is not reachable another way. In the CLI, `edit` and `bash` can both write, so a read-only agent must exclude both.
