---
category: reference
source_session: 260302-001737
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-7 report (publish-agents.ps1 Platform parameter)"
extracted_at: "2026-03-02T15:06:27+07:00"
promoted: true
promoted_at: "2026-03-02T15:17:25+07:00"
---

# Platform-Aware publish-agents.ps1 Design Reference

## Overview

The `publish-agents.ps1` script supports platform-aware agent publishing via a `-Platform` parameter, routing VS Code and CLI agents to their correct destinations.

## Parameter

```powershell
-Platform [ValidateSet("vscode", "cli")]
```

- `-Platform vscode`: Publishes only VS Code agents.
- `-Platform cli`: Publishes only CLI agents.
- **Default (omitted)**: Publishes both platforms.

## Source Discovery

The `Get-AgentFiles` function discovers agents using these patterns:

| Platform | Glob Patterns | What It Finds |
|----------|--------------|---------------|
| VS Code | `agents/*/vscode/*.agent.md` + `agents/*.agent.md` | Variant agents in vscode/ subdirs + root-level non-variant agents |
| CLI | `agents/*/cli/*.agent.md` | CLI variant agents only |

- `agents/archived/` is naturally excluded (no `vscode/` or `cli/` subdirectories, and root-level discovery uses `-File` without `-Recurse`).
- Each discovered file gets a structured object with `FullName`, `DestinationName`, and `Platform` properties.

## Destination Routing

| Platform | Windows Destination | WSL Destination |
|----------|-------------------|-----------------|
| VS Code | `%APPDATA%\Code\User\prompts\` + Insiders | `.config/Code/User/prompts` + Insiders |
| CLI | `%USERPROFILE%\.copilot\agents\` | `.copilot/agents` |

## Destination Flattening

All agents are flattened to their base filename at the destination:

```
agents/ralph-v2/vscode/ralph-v2.agent.md  →  <dest>/ralph-v2.agent.md
agents/ralph-v2/cli/ralph-v2.agent.md     →  <dest>/ralph-v2.agent.md
```

The `DestinationName` property uses `$_.Name` (filename only), stripping all directory path components.

## Validation Script

`validate-agent-variants.ps1` provides advisory deny-list validation with four checks:

1. **VS Code deny-list for CLI variants**: 17 VS Code-only tool patterns that must not appear in CLI agent frontmatter.
2. **CLI deny-list for VS Code variants**: 9 CLI-only tool patterns that must not appear in VS Code agent frontmatter.
3. **Body content scan**: Regex checks for cross-platform tool references in body text (warnings only).
4. **Shared instruction reference parity**: Verifies that VS Code and CLI variants for the same agent group reference the same shared instruction files.
