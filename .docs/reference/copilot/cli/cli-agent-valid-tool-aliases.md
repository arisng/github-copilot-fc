---
category: reference
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-2 task definition"
  - "Iteration 9 task-2 report"
  - "Iteration 9 feedback-driven questions Q-FDB-004"
  - "Iteration 9 session review SC-5"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# Copilot CLI Agent: Valid Tool Aliases

## Canonical Tool List

The official Copilot CLI tool aliases are:

| Alias | Description |
|-------|-------------|
| `bash` | Shell command execution |
| `view` | Read/inspect files |
| `edit` | Write/modify files |
| `search` | File system and codebase search |
| `mcp_SERVERNAME_TOOLNAME` | MCP server tools (dynamic, per agent config) |

## Invalid Aliases

| Alias | Status | Notes |
|-------|--------|-------|
| `create` | **NOT valid** | Silently ignored by the CLI; has no effect on agent capabilities |

## Recommended Baseline Tools Block

For a standard subagent (no MCP):
```yaml
tools:
  - bash
  - view
  - edit
  - search
```

For the orchestrator (with task management):
```yaml
tools:
  - bash
  - view
  - edit
  - search
  - task
```

## Migration Note

When auditing existing CLI agent files:
```powershell
# Check create is absent
Select-String "^\s+- create\s*$" agents/**/*.agent.md  # should return 0

# Check search is present
Select-String "^\s+- search\s*$" agents/**/*.agent.md  # should return match per file
```

## Source Reference

Confirmed via the GitHub Copilot CLI features comparison documentation and direct testing in March 2026. The `search` alias was missing from early Ralph-v2 CLI agent files and was added during CLI hardening. The `create` alias was incorrectly included and has been removed.
