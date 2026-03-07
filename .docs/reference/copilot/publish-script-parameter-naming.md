---
category: reference
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-3 task definition"
  - "Iteration 9 task-3 report"
  - "Iteration 9 feedback-driven questions Q-FDB-005 Q-FDB-006 Q-FDB-007"
  - "Iteration 9 plan FDB-018"
  - "Iteration 9 session review SC-1"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# Publish Script Parameter Naming Convention

## Distinction: `-Platform` vs `-Environment`

Two publish scripts in the workspace use different parameters that address **different semantic dimensions**. These must NOT be treated as interchangeable or renamed to match each other:

| Script | Parameter | Values | Meaning |
|--------|-----------|--------|---------|
| `publish-agents.ps1` | `-Platform` | `vscode`, `cli`, `all` | **Copilot runtime target** — which product receives the agent |
| `publish-plugins.ps1` | `-Environment` | `windows`, `wsl`, `all` | **Host OS environment** — which operating system runs the install |

## Rationale

The two dimensions are orthogonal:
- `-Platform` answers: "Which Copilot product are we publishing TO?" (VS Code vs CLI)
- `-Environment` answers: "Which OS is running the publish PROCESS?" (Windows vs WSL)

Using the same parameter name for both would create a semantic collision that misleads authors about what they are controlling.

## Deprecation Handler Pattern

`publish-plugins.ps1` includes a `-SkipWSL` backward-compatibility handler. When the parameter name changes, the deprecation message MUST reference the new parameter name:

```powershell
# Correct pattern — message references the new -Environment param
if ($SkipWSL) {
    Write-Warning "-SkipWSL is deprecated; use -Environment windows instead"
    $Environment = 'windows'
}
```

## Validation

```powershell
# publish-agents.ps1 still uses -Platform (runtime)
Select-String "\$Platform" scripts/publish/publish-agents.ps1   # should match

# publish-plugins.ps1 uses -Environment (host OS)
Select-String "\$Platform" scripts/publish/publish-plugins.ps1  # should return 0
Select-String "\$Environment" scripts/publish/publish-plugins.ps1  # should match
```
