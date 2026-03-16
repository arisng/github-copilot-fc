---
category: how-to
---

# How to Run the Ralph CLI Smoke Harness

This guide shows how to run the `scripts/test/ralph-v2-cli-smoke.ps1` harness as a publish gate for the Ralph-v2 Copilot CLI plugin.

## When to Use This Guide

Use this when you need to:

- validate a freshly built Ralph CLI plugin bundle
- check bundle discovery and installation before publishing
- exercise the orchestrator with a minimal end-to-end smoke scenario
- collect a reviewable report with evidence files

## Prerequisites

- PowerShell 7+ available as `pwsh`
- GitHub Copilot CLI installed and authenticated
- the workspace cloned locally
- any required model credentials already configured for `copilot`

## Steps

### 1. Run the default smoke harness

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1
```

This default path builds the beta bundle, installs it through `copilot plugin install`, and runs the configured smoke scenario.

### 2. Run a stable-channel validation

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -Channel stable
```

Use this when you want to verify the stable build path instead of the default beta path.

### 3. Validate build and discovery without invoking agents

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -SkipAgentInvocation
```

Use this mode when you only want to validate bundling, installation, and discovery mechanics.

### 4. Pin the model explicitly

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -Model gpt-5.2
```

Pinning the model makes comparisons easier when you are investigating regressions or preparing repeatable validation.

### 5. Save a human-readable report to a known path

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -ReportPath .\ralph-cli-smoke-latest\report.md
```

The harness also writes sibling JSON artifacts and evidence files next to the report output.

## What to Review

After the run, inspect:

- `report.md` for the high-level narrative
- `summary.json` for machine-readable pass/fail state
- `inputs.json` and `test-cases.json` for harness configuration
- `evidence/` for captured proof of bundle identity, discovery, and session artifacts

## Common Variations

Keep temporary working directories for debugging:

```powershell
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -KeepConfigDir -KeepLogDir -KeepWorkingDirectory
```

Run the harness from the workspace command router:

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 tests:ralph-cli-smoke
```

## Troubleshooting

**Problem: plugin builds but is not discoverable**

Run with `-SkipAgentInvocation` first to isolate installation and discovery from model execution.

**Problem: beta vs stable naming looks wrong**

Verify the active channel and then review the bundle identity rules in [Ralph Beta Agent Frontmatter Name Contract](../../reference/ralph/ralph-beta-agent-frontmatter-name-contract.md).

**Problem: report artifacts are cluttering the working tree**

The workspace ignores `scripts/test/.artifacts/`, but custom report paths outside that directory will still appear in git status unless you clean them up manually.

## See Also

- [Ralph-v2 CLI Plugin Test Plan](../../../.issues/260315_ralph-v2-cli-test-plan.md)
- [scripts/test/README.md](../../../scripts/test/README.md)
- [Ralph-v2 agent frontmatter version contract](../../reference/ralph/ralph-agent-frontmatter-version-contract.md)

