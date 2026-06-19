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
  version: 0.1.0
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
| `-Prompt` | **Yes** | — | The task prompt. Supports multi-line (here-strings, `` `n ``, literal newlines). |
| `-Name` | No | — | Human-readable session name (`--name`). Use kebab-case slugs (e.g. `"analyze-async"`). The agent should proactively generate one. |
| `-SessionId` | No | — | Custom UUID for `--session-id`. Reuse the same value across calls to chain messages on the same session. |
| `-Agent` | No | — | Custom agent name. Qualify plugin agents as `plugin-name/agent-name`. |
| `-Model` | No | — | Model override. Takes precedence over the BYOK profile's model. |
| `-ByokProfile` | No | `opencode-go-deepseek-v4-flash` | BYOK profile name from `~/.copilot/byok-profiles.json`. |
| `-ReasoningEffort` | No | `high` | `none`, `low`, `medium`, `high`, `xhigh`, `max`. **Important**: the default BYOK model (`opencode-go-deepseek-v4-flash`) does NOT support reasoning effort — always pass `-ReasoningEffort none` when using the default profile. |
| `-WorkingDir` | No | current location | Working directory for the sub-process. |
| `-JsonOutput` | Switch | off | Emit JSONL instead of plain text. |
| `-AllowAll` | Switch | off | Add `--allow-all --no-ask-user`. |
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

- **One-shot sub-session**: omit `-SessionId` or generate a fresh UUID (`$(New-Guid)`).
- **Follow-up to the same sub-session**: reuse the exact same `-SessionId` value; the prior session state is reloaded.
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

The script prints a structured result object:

```powershell
[PSCustomObject]@{
    ExitCode      = $proc.ExitCode
    StdOut        = $stdout
    StdErr        = $stderr
    Name          = $Name
    SessionId     = $SessionId
    Agent         = $Agent
    Model         = $env:COPILOT_MODEL
    ByokProfile   = $ByokProfile
}
```

## Safety rules

- Always assign a descriptive `-Name` in kebab-case.
- Prefer `-AllowAll` only for trusted, isolated sub-workflows.
- The sub-session inherits MCP and custom instructions by default; use `-DisableBuiltInMcps` or `-NoCustomInstructions` only when isolation is intended.
- The sub-process inherits the main session's environment except where the script overrides it.

## References

- [Programmatic Copilot CLI cheatsheet](./references/copilot-cli-programmatic-cheatsheet.md)
- [BYOK configuration](../copilot-byok/SKILL.md)
