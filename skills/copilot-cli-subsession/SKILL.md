---
name: copilot-cli-subsession
description: >-
  Spawn a new isolated Copilot CLI sub-session from a main Copilot CLI or VS Code session.
  Use when you need to programmatically create, resume, or chain Copilot CLI sessions with
  explicit control over session ID, custom agent, model, BYOK provider profile, permissions,
  and working directory. Triggers: "invoke copilot", "spawn copilot", "copilot sub-session",
  "programmatic copilot cli", "copilot cli session id", "resume copilot session", "chain copilot sessions",
  "copilot byok profile script", "subagent copilot cli", "task copilot cli".
argument-hint: "What is the sub-session prompt?"
metadata:
  author: arisng
  version: 0.3.0
---

# Invoke Copilot CLI Sub-Session

Use this skill when a main session (in Copilot CLI or VS Code) needs to spawn a **fresh, isolated Copilot CLI sub-session** with full control over its identity and runtime.

## When to use

- Run a long or risky sub-workflow in a separate process that does not pollute the main session context.
- Pin a specific **custom agent** to the sub-session.
- Pin a specific **BYOK provider / model** for the sub-session (default: `opencode-go-deepseek-v4-flash`, reasoning-effort `high`; the default model requires `-ReasoningEffort none`).
- Self-generate a **session name** (`--name`) and **session UUID** (`--session-id`) so the main session can send follow-up prompts to the same sub-session.
- Capture structured output (text or JSONL) for programmatic parsing.

## What it produces

- A PowerShell script: `scripts/Invoke-CopilotCliSubSession.ps1`.
- This skill guides the agent to call that script with the correct parameters. The agent should proactively assign a descriptive `-Name` in kebab-case.
- By default the sub-session **inherits** the main session's MCP servers and custom instructions (same working directory, same `~/.copilot/`).

## Quick start

```powershell
# Minimal invocation — uses default BYOK profile (requires reasoning-effort none)
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "analyze-async" `
    -ReasoningEffort "none" `
    -Prompt "Analyze the project structure and list all async methods."

# Specific agent, model override, named session, multi-line prompt
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "security-audit" `
    -Agent "security-auditor" `
    -Model "claude-opus-4.5" `
    -SessionId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -Prompt @"
Review the codebase for security vulnerabilities:
1. Check for SQL injection in data access layer
2. Audit authentication middleware
3. Verify CSRF protection is active
4. Report findings with severity levels
"@

# Invoke a built-in command or skill via slash command
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -SlashCommand "handoff" `
    -Prompt "Describe the current session state" `
    -Name "session-handoff" `
    -ReasoningEffort "none"

# Invoke a skill without extra prompt
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -SlashCommand "git-atomic-commit" `
    -Name "auto-commit" `
    -ReasoningEffort "none"

# Invoke with a custom agent
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Agent "dotnet-diag:optimizing-dotnet-performance" `
    -Name "perf-analysis" `
    -Prompt "Scan for async anti-patterns"

# Context handoff: list relevant file paths; sub-session reads them itself
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "exec-plan" `
    -ReasoningEffort "none" `
    -Prompt @"
Execute the implementation plan at:
  c:/Workplace/my-repo/openspec/changes/auth-impl/plan.md
  c:/Workplace/my-repo/openspec/changes/auth-impl/tasks.md

Reference specs:
  c:/Workplace/my-repo/openspec/specs/auth/spec.md

Working directory: c:/Workplace/my-repo
Read each file before executing. Report progress after each step.
"@

# Chain two prompts on the same sub-session by reusing SessionId
$uuid = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
$r1 = .\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "research-auth" `
    -SessionId $uuid `
    -ReasoningEffort "none" `
    -Prompt "Research this repo's authentication approach." `
    -JsonOutput

$r2 = .\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "research-auth" `
    -SessionId $uuid `
    -ReasoningEffort "none" `
    -Prompt "Based on the research, propose three security improvements." `
    -JsonOutput
```

## Required vs optional parameters

| Parameter | Required | Default | Purpose |
|-----------|----------|---------|---------|
| `-SlashCommand` | No | — | Built-in command or skill name to invoke (e.g., `handoff`, `git-atomic-commit`, `plan`, `review`). Script prepends `/`. When given with `-Prompt`, the prompt becomes the command argument. **At least one of `-SlashCommand` or `-Prompt` is required.** |
| `-Prompt` | No* | — | The task prompt, or argument to `-SlashCommand` when both are given. Supports multi-line (here-strings, `` `n ``, literal newlines). \*Required when `-SlashCommand` is not provided. |
| `-Name` | No | — | Human-readable session name (`--name`). Use kebab-case slugs (e.g. `"analyze-async"`). The agent should proactively generate one. |
| `-SessionId` | No | auto-generated UUID | Custom UUID for `--session-id`. Must be valid UUID format. When omitted, a UUID is auto-generated. Reuse the same value across calls to chain messages on the same session. |
| `-Agent` | No | — | Custom agent name. Qualify plugin agents as `plugin:agent-name` (colon, e.g. `dotnet-diag:optimizing-dotnet-performance`). Repo agents use bare name. |
| `-Model` | No | — | Model override. Takes precedence over the BYOK profile's model. |
| `-ByokProfile` | No | `opencode-go-deepseek-v4-flash` | BYOK profile name from `~/.copilot/byok-profiles.json`. |
| `-ReasoningEffort` | No | `high` | `none`, `low`, `medium`, `high`, `xhigh`, `max`. **Important**: the default BYOK model (`opencode-go-deepseek-v4-flash`) does NOT support reasoning effort — always pass `-ReasoningEffort none` when using the default profile. |
| `-WorkingDir` | No | current location | Working directory for the sub-process. |
| `-JsonOutput` | Switch | off | Emit JSONL instead of plain text. |
| `-NoAllowAll` | Switch | off | Opt out of `--allow-all --no-ask-user`. By default the sub-session runs with full permissions. |
| `-DisableBuiltInMcps` | Switch | off | Isolate from main session's MCP servers. |
| `-NoCustomInstructions` | Switch | off | Skip project custom instructions. |
| `-TimeoutSeconds` | No | `600` | Kill the sub-process after N seconds. |
| `-Passthrough` | No | — | Extra arguments forwarded to `copilot`. |

## Session naming (`-Name`)

The agent should always assign a meaningful `-Name` in **kebab-case** that describes the sub-session's purpose:

- `"research-csrf-patterns"` — a research task
- `"implement-oauth-middleware"` — an implementation task
- `"review-pr-142"` — a review task

This name appears in `copilot --resume` listings and session logs. It is distinct from `-SessionId` (the UUID used for programmatic chaining). Pass both: `-Name` for human readability, `-SessionId` for script-level chaining.

## Choosing a session ID

- **Auto-generated**: when `-SessionId` is omitted, a valid UUID is auto-generated using `New-Guid`. Every call gets a fresh session unless you reuse the same UUID.
- **Explicit UUID**: pass a valid UUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). Invalid UUIDs trigger a warning and are replaced with an auto-generated one.
- **Follow-up to the same sub-session**: reuse the exact same `-SessionId` value; the prior session state is reloaded via `--session-id`.
- **Valid UUIDs only**: `--session-id` requires standard format (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).

## Multi-line prompts

`-Prompt` accepts multi-line strings natively. Use PowerShell here-strings for multi-paragraph task descriptions:

```powershell
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "code-review" `
    -Prompt @"
Review the following PR checklist:
1. Verify all edge cases are covered
2. Check for proper error handling
3. Ensure tests pass with >80% coverage
4. Validate API contract changes
Report findings in a markdown table.
"@
```

Inline newlines via `` `n `` also work: `-Prompt "Line 1`nLine 2`nLine 3"`.

## Slash command invocation (`-SlashCommand`)

`-SlashCommand` wraps Copilot CLI's interactive slash commands for non-interactive use. Pass just the command name (no leading `/`) — the script prepends `/` automatically.

**Supported commands**: Any built-in CLI command (`help`, `model`, `init`, `diff`, `pr`, `review`, `plan`, `research`, `delegate`, `undo`, `compact`, `share`, `allow-all`, `add-dir`, `skills`) and any installed skill (`git-atomic-commit`, `handoff`, `mermaid-creator`, etc.).

```powershell
# Slash command only
.\scripts\Invoke-CopilotCliSubSession.ps1 -SlashCommand "plan" -Name "planning-pass"

# Slash command with arguments (Prompt becomes the argument)
.\scripts\Invoke-CopilotCliSubSession.ps1 -SlashCommand "handoff" -Prompt "Describe session results" -Name "handoff-pass"

# Equivalent freeform prompt (also valid)
.\scripts\Invoke-CopilotCliSubSession.ps1 -Prompt "/handoff Describe session results" -Name "handoff-pass"
```

**Multi-step orchestration pattern**:

```powershell
# Plan → Execute → Review with slash commands
.\scripts\Invoke-CopilotCliSubSession.ps1 -SlashCommand "plan" -Prompt "Implement user auth" -Name "plan-auth" -SessionId $uuid -ReasoningEffort "none"
.\scripts\Invoke-CopilotCliSubSession.ps1 -Prompt "Execute the plan above" -Name "exec-auth" -SessionId $uuid -ReasoningEffort "none"
.\scripts\Invoke-CopilotCliSubSession.ps1 -SlashCommand "review" -Name "review-auth" -SessionId $uuid -ReasoningEffort "none"
```
## Custom agent invocation (`-Agent`)

Pin a specific agent to the sub-session. Plugin agents use **colon**: `plugin:agent-name`. Repo agents use bare name.

```powershell
# Plugin agent
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Agent "dotnet-diag:optimizing-dotnet-performance" `
    -Prompt "Analyze this project's performance" `
    -Name "perf-analysis"

# Repo agent (discovered from .github/agents/)
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Agent "my-custom-agent" `
    -Prompt "Execute the workflow" `
    -Name "custom-workflow"
```

Agent discovery paths (in precedence order):
1. `~/.copilot/agents/` (user-level)
2. `.github/agents/` (repo-level)
3. `plugin:agent-name` (qualified, from installed plugins)

The agent is invoked via the Copilot CLI `--agent` flag and inherits the sub-session's model, BYOK config, and all other parameters.

## Context handoff convention

When delegating to a sub-session, **always prioritize listing the full absolute paths of relevant files** in `-Prompt`. The sub-session can read those files itself using its own tools (`cat`, `grep`, `read`). Only embed content inline when the context is short and simple enough to fit in a single message.

### Why

- The sub-session starts with a blank context — it does not know what files the main session worked with, what decisions were made, or what artifacts exist.
- MCP and custom instructions inheritance provides *environment* (tools, config), not *session memory*.
- Listing file paths is cheaper, avoids duplication, and lets the sub-session choose what to read in depth.

### Do this

```powershell
# PREFERRED — list full paths; sub-session reads files itself
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "exec" `
    -Prompt @"
Execute the implementation plan at:
  c:/Workplace/my-repo/openspec/changes/auth-impl/plan.md
  c:/Workplace/my-repo/openspec/changes/auth-impl/tasks.md

Reference specs:
  c:/Workplace/my-repo/openspec/specs/auth/spec.md

Start from working directory: c:/Workplace/my-repo
After each step, report progress.
"@

# EXCEPTION — directly embed only when context is short and simple
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "quick-fix" `
    -Prompt "Fix the typo in src/utils/helpers.ts line 42: change 'teh' to 'the'."
```

### Practical workflow

1. Identify the relevant files from the main session (plan, research, spec, ADR, design doc, task list).
2. List their **full absolute paths** in the `-Prompt` argument, grouped by role.
3. Include the **working directory** and the **final instruction** — what the sub-session should produce.
4. Only embed content inline (via here-string) when the context is trivially short (a few lines).
5. Use the returned `SessionId` to chain follow-up messages if the task requires multiple turns.

### What to reference

| Context type | Files to reference by path |
|--------------|----------------------------|
| Implementation plan | `openspec/changes/*/plan.md`, `openspec/changes/*/tasks.md` |
| Research findings | `openspec/research/*.md`, `docs/design-docs/*.md` |
| Specifications | `openspec/specs/**/spec.md`, `requirements/*.md` |
| Active task checklist | Current todo list, task breakdown |
| Configuration / conventions | `.github/git-scope-constitution.md`, relevant `*.agent.md` |
| **Copilot CLI session state** | `~/.copilot/session-state/<session-uuid>/` (see below) |

### Copilot CLI session-state handoff

When the main session is itself a **Copilot CLI session**, its session state is persisted under `~/.copilot/session-state/<session-uuid>/`. These files capture what the main session already worked on — plans, research, file changes, and checkpoints. Forward them to the sub-session so it does not start from scratch.

| File / Dir | Description |
|------------|-------------|
| `plan.md` | The implementation plan generated by `/plan`. The sub-session should read this to understand what to build and in what order. |
| `research/` | Output from `/research`. Contains search results, analyzed code snippets, and external references the main session already gathered. |
| `files/` | File snapshots or diffs touched during the session. Lets the sub-session see what was changed without re-reading the whole repo. |
| `checkpoints/` | Session checkpoints. Useful for resuming work from a specific point if the sub-session needs to continue where the main session left off. |

**How to discover the session UUID:**

```powershell
# List all session IDs
Get-ChildItem "$HOME\.copilot\session-state" -Directory | Select-Object Name

# Or get the latest session
Get-ChildItem "$HOME\.copilot\session-state" -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty Name
```

**How to reference in `-Prompt`:**

```powershell
# PREFERRED — pass knowledge from previous session
.\scripts\Invoke-CopilotCliSubSession.ps1 `
    -Name "continue-from-session" `
    -Prompt @"
Continue the work from the previous Copilot CLI session.

Session state is at:
  ~/.copilot/session-state/a1b2c3d4-e5f6-7890-abcd-ef1234567890/

Review these files before executing:
  ~/.copilot/session-state/a1b2c3d4-e5f6-7890-abcd-ef1234567890/plan.md
  ~/.copilot/session-state/a1b2c3d4-e5f6-7890-abcd-ef1234567890/research/
  ~/.copilot/session-state/a1b2c3d4-e5f6-7890-abcd-ef1234567890/files/

Working directory: c:/Workplace/my-repo
Continue from where the plan left off.
"@
```

**Note**: The session-state directory is tied to the **main** session's UUID. The sub-session gets its own separate session-state (under its own `--session-id`). Forwarding the main session's state paths is what bridges the gap.

### Path formatting

- Use **absolute paths** (`c:/Workplace/my-repo/...`) so the sub-session can read them regardless of its working directory.
- If the sub-session's `-WorkingDir` matches the repo root, relative paths rooted there also work.
- Group paths by purpose with a short header line before each group.

## MCP and custom instructions inheritance

By default the sub-session **inherits** the main session's MCP servers and custom instructions because:

- It runs in the same working directory (project-level `.mcp.json`, `.github/mcp.json`, `copilot-instructions.md` are picked up).
- It uses the same `~/.copilot/` directory (user-level `mcp-config.json`, agents, skills).

To isolate the sub-session, pass `-DisableBuiltInMcps` and/or `-NoCustomInstructions`. To fully isolate, set `-ConfigDir` (or `$env:COPILOT_HOME`) to a separate config tree.

## BYOK profile handling

The script looks up the profile in `~/.copilot/byok-profiles.json` (or `$env:COPILOT_HOME/byok-profiles.json`). The **default profile** is `opencode-go-deepseek-v4-flash`.

It maps profile fields to environment variables:

```text
COPILOT_PROVIDER_BASE_URL
COPILOT_PROVIDER_TYPE
COPILOT_MODEL
COPILOT_PROVIDER_API_KEY
COPILOT_PROVIDER_WIRE_API
COPILOT_PROVIDER_MAX_PROMPT_TOKENS
COPILOT_PROVIDER_MAX_OUTPUT_TOKENS
COPILOT_OFFLINE
```

If the profile contains `proxyPort`, the script routes the request through the local Moonshot proxy (`https://moonshot.local/v1`) used by `copilot-byok`.

A `-Model` parameter, when provided, takes precedence over the profile's model.

## Output

By default the script returns a plain-text block. With `-JsonOutput` it returns JSONL; the final `result` line contains `exitCode` and `usage`.

The script prints a structured result object (metadata only — StdOut is written to the console directly):

```powershell
[PSCustomObject]@{
    ExitCode      = $proc.ExitCode
    SlashCommand  = $SlashCommand
    Name          = $Name
    SessionId     = $SessionId
    Agent         = $Agent
    Model         = $env:COPILOT_MODEL
    ByokProfile   = $ByokProfile
}
```

## Safety rules

- Always assign a descriptive `-Name` in kebab-case.
- `-NoAllowAll` lets you opt out of the default `--allow-all --no-ask-user` for read-only or untrusted contexts.
- The sub-session inherits MCP and custom instructions by default; use `-DisableBuiltInMcps` or `-NoCustomInstructions` only when isolation is intended.
- The sub-process inherits the main session's environment except where the script overrides it.

## References

- [Programmatic Copilot CLI cheatsheet](./references/copilot-cli-programmatic-cheatsheet.md)
- [BYOK configuration](../copilot-byok/SKILL.md)
