# How to Configure Auto-Approve Commands in Codex

This guide shows you how to configure Codex (OpenAI's AI coding assistant) to auto-approve commands, allowing it to execute actions without prompting for user approval when running in Windows Subsystem for Linux (WSL).

## When to use this guide

Use this guide if you need to automate Codex's execution of reads, edits, and commands within a workspace without manual approvals, while maintaining sandbox security. This is ideal for trusted development environments where you want to reduce friction in workflows.

## Before you start

- Codex installed and set up in WSL.
- VS Code configured with `"chatgpt.runCodexInWindowsSubsystemForLinux": true`.
- Basic familiarity with TOML configuration files and command-line editing.

## Context

Codex uses sandbox modes to limit technical actions (e.g., file writes, network access) and approval policies to control when it seeks user confirmation. Setting the approval policy to `"never"` enables auto-approval for actions within the sandbox, streamlining automation while preserving security boundaries.

Valid values for `approval_policy`:
- `"never"`: No prompts (full auto-approve).
- `"on-request"`: Prompts for risky actions.
- `"untrusted"`: Prompts for untrusted commands.
- `"on-failure"`: Prompts only on failures.

## Steps

### 1. Locate the configuration file

Access your WSL environment and navigate to the Codex config directory.

```
cd ~
```

The file is at `~/.codex/config.toml`. Create it if it doesn't exist.

### 2. Edit the configuration file

Open the file with a text editor.

```
nano ~/.codex/config.toml
```

Add or modify the settings for auto-approval.

### 3. Set basic auto-approve options

For auto-approval of workspace actions (reads, edits, commands):

```toml
approval_policy = "never"
sandbox_mode = "workspace-write"
```

### 4. Optionally enable network access

If you need network operations auto-approved:

```toml
[sandbox_workspace_write]
network_access = true
```

### 5. Save and apply changes

Save the file and exit the editor.

Restart Codex or run `codex config show --effective` to verify.

### 6. Test the configuration

Run a test command to confirm auto-approval works.

```
codex --ask-for-approval never --sandbox workspace-write [your-command]
```

## Troubleshooting

**Problem: Configuration not applied**
Solution: Ensure you're editing the file in WSL (not Windows). Run `codex config show --effective` to check for overrides.

**Problem: Sandbox restrictions still prompt**
Solution: Verify `sandbox_mode` is set to `"workspace-write"`. For full bypass, use `"danger-full-access"` cautiously.

**Problem: Network access denied**
Solution: Set `network_access = true` in the `[sandbox_workspace_write]` section.

## Variations

If you want selective approvals (e.g., prompt for network but not edits):
- Set `approval_policy = "on-request"` and `network_access = false`.

For read-only auto-approval:
- Set `sandbox_mode = "read-only"` and `approval_policy = "never"`.

## Related guides

- [Codex Security Guide](https://developers.openai.com/codex/security/) for understanding sandbox and approval policies.

## See also

- [Codex Configuration Reference](https://github.com/openai/codex/blob/main/docs/config.md) for complete config options.