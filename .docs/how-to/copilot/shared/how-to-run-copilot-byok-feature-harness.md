---
category: how-to
domain: copilot
---

# How to Run the copilot-byok Feature Harness

## Goal

Empirically verify the `copilot-byok` skill (`skills/copilot-byok/scripts/byok-profile.ps1`) behaviors — staging redirection, profile management, provider env emission, reasoning-effort stripping, and subsession seeding — against a hermetic fixture, so skill edits get a tight, deterministic feedback loop without touching production keys or `~/.copilot`.

## Prerequisites

- Windows with `pwsh` 7+ (never `powershell` 5.1).
- The workspace repo cloned; the harness resolves scripts by workspace-relative path.
- No secrets needed: the harness injects sentinel API keys per child and never inherits real `OPENCODE_API_KEY_*` / `OPENAI_API_KEY`.
- Optional: production `~/.copilot/byok-profiles.json` present (case `t1-5` auto-skips otherwise; cases `t6-1`/`t6-2` seed from it).

## The four-step feedback loop

### Step 1 — Edit the skill

Change `skills/copilot-byok/scripts/byok-profile.ps1` (or the fixture `scripts/test/fixtures/byok-profiles.fixture.json`).

### Step 2 — Know the staging model (dojo vs harness-owned)

The harness **never touches the shared dojo `~/.copilot-staging` by default**. Its default `-StagingHome` is a harness-owned directory under `scripts/test/.artifacts/copilot-byok-feature-test/staging`, which it creates, injects the fixture into, and cleans up after the run.

If you *do* want to test against the dojo and leave it in a maintained seeded state, pass `-StagingHome` explicitly **with** `-KeepFixture` (without it, the injected `byok-profiles.json` is removed after the run, leaving the dojo bare):

```powershell
pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1 -StagingHome "$env:USERPROFILE\.copilot-staging" -KeepFixture
```

To seed the dojo with production BYOK config (safe — production `apiKey` values are `${ENV}` placeholders, no secrets; this is the same copy `Invoke-CopilotCliSubSession.ps1` performs when `byok-profiles.json` is missing):

```powershell
Copy-Item "$env:USERPROFILE\.copilot\byok-profiles.json" "$env:USERPROFILE\.copilot-staging\byok-profiles.json"
```

Or run the workspace publish staging flow for agents/skills/hooks:

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 -Command agents:publish -CopilotHome "$env:USERPROFILE\.copilot-staging"
```

### Step 3 — Run the harness

```powershell
# From the repo root
pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1

# Or through the workspace dispatcher
pwsh -NoProfile -File scripts/workspace/run-command.ps1 -Command tests:byok-features

# Safe CI-style run with a throwaway staging home
pwsh -NoProfile -File scripts/test/copilot-byok-feature-test.ps1 -StagingHome "$env:TEMP\byok-staging-<unique>"
```

Exit codes: `0` all pass (known-gap rows count as pass), `1` one or more failures, `2` harness error.

### Step 4 — Read the report and iterate

The latest report is under `scripts/test/.artifacts/copilot-byok-feature-test/run-<timestamp>-<pid>/`:

1. `report.md` — `Run overview` (exit code + `Total / Passed / Failed / Skipped / Known-gap`), then `Execution checklist`; start at the first failed row.
2. For a failure, open `evidence/<id>.out.txt` (child stdout) and `<id>.err.txt` (child stderr); for `run` cases also `evidence/<id>.shim.log` (the intercepted `copilot` args + emitted provider env).
3. Fix the skill (or, if the change is intended, update the fixture or the case expectation), re-run, and re-read.

## What the harness covers

| Bucket | Cases | What it proves |
| --- | --- | --- |
| redirection | t1-1, t1-3, t1-4, t1-5 | `list`/`use`/`remove` hit `COPILOT_HOME` only; production file hash byte-identical; without `COPILOT_HOME` production is read-only |
| profile-manager | t2-1 … t2-9 | list format + `[accountGroup: ...]`, `show` JSON + `Reasoning Effort Supported`, `accounts` + `[active]`, `use` persistence, wizard preset 6 via piped stdin, missing-profile/account error exits, empty states |
| env-emission | t3-1 … t3-7 | dot-sourced `set-env` emits `COPILOT_PROVIDER_*`/`COPILOT_MODEL`/`COPILOT_OFFLINE`, `--account` override, `${ENV}` expansion, rich→minimal stale cleanup |
| reasoning-strip | t4-1 … t4-8 | `run` strips `--reasoning-effort`/`--effort=` for unsupported models, forwards for supported, consumes `--account`, preserves other args (via a fake `copilot` shim) |
| negatives | t5-1, t5-2, t5-3 | malformed JSON exits 1 cleanly; empty JSON → `No profiles found`; `kimi-k3` reasoning drift locked |
| subsession | t6-1, t6-2, t6-4 | `Invoke-CopilotCliSubSession.ps1` seeds missing `byok-profiles.json`, is idempotent when present, returns `CopilotHome`/`ExitCode` |

## Known gaps (PASS with gap label)

Current behavior locked as baseline — fix these in the skill, not the harness:

- **t2-6** — wizard preset 6 (OpenCode Go) never prompts for `wireApi`.
- **t4-7** — `byok run <profile> -p "<prompt>"` breaks: PowerShell param prefix matching binds `-p` to the script's `-Profile`; use `--prompt`.
- **t4-8** — `Remove-AccountArg` regex `^--account=(.+)$` does not consume an empty `--account=`, which leaks to `copilot`.
- **t5-3** — `kimi-k3` is absent from `Get-NoReasoningEffortModels`; `Test-ReasoningEffortSupported` returns `True` while `reasoning-effort-lookup.md` says assume no support until probed.

## Notes and gotchas

- The harness spawns child `pwsh -NoProfile -Command` processes with redirected stdout/stderr; `*>&1` merges the info stream (Write-Host) into stdout, but terminating errors land on stderr — error-path cases assert on exit codes, not captured error text.
- A `copilot.ps1` shim is prepended to the child `PATH` (real copilot dir scrubbed) so `run` cases can assert exactly what the byok script hands to `copilot`.
- The fixture is re-injected before every config case; the staging file is restored or removed after the run unless `-KeepFixture`.
- **The shared dojo `~/.copilot-staging` is never used by default** — the harness owns `scripts/test/.artifacts/copilot-byok-feature-test/staging`. If you explicitly point `-StagingHome` at the dojo without `-KeepFixture`, the injected `byok-profiles.json` is removed afterwards, leaving the dojo without a BYOK seed; either use `-KeepFixture` or re-seed from production (see Step 2).
- `t6-*` cases use throwaway directories and never touch `~/.copilot-staging`.
- To mutate-test the harness: drop `maxPromptTokens` from a fixture profile and confirm the corresponding env case fails, then restore.
