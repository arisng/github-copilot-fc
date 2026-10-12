---
name: waza-cli
description: Drive the waza CLI (microsoft/waza) to evaluate agent skills with real LLM execution, model comparison, and CI regression gating. Use when checking a skill for submission readiness, running behavioral eval suites with LLM graders, comparing models A/B, gating skill regressions in CI, or measuring skill quality with an LLM judge. Do not use for fast static structure audits with zero LLM cost (use skill-eval).
metadata:
  version: 0.1.0
---

# Waza CLI Evaluation

Run [waza](https://github.com/microsoft/waza) commands against a skill dir. Install: `go install github.com/microsoft/waza@latest`.

USE FOR: check my skill, run my evals, compare models, gate CI regressions, score skill quality. DO NOT USE FOR: first-draft authoring (use skill-creator); offline static audits (use skill-eval).

## Choose the command

| Goal | Command |
|------|---------|
| Readiness, compliance, token budget | `waza check <skill-dir>` |
| LLM-judge quality (5 dimensions) | `waza quality <skill-dir>` |
| Behavioral eval, real execution | `waza run <eval.yaml>` |
| Model A/B comparison | `waza run --baseline` |
| CI regression gate | `waza gate` |
| Determinism check | `waza snapshot` + `waza replay` |

## Runtime environment (CLI, COPILOT_HOME, BYOK)

### Default: waza's bundled Copilot CLI

With `COPILOT_CLI_PATH` unset, waza spawns its **bundled CLI** (v1.0.85 for waza 0.38.7 — pinned at build time, see [copilot-cli-resolution.md](references/copilot-cli-resolution.md)). This is the recommended default for eval: it is the exact CLI version waza was built and tested against, giving reproducible results across machines and CI runs.

**Do not set `COPILOT_CLI_PATH` by default.** The resolver script is an **opt-in override** for when you need a specific machine CLI (e.g., testing a feature only in a newer release). Machine-default is risky: it varies by box (1.0.92 on WinGet, 1.0.80 on npm-first) and may be newer than waza tested, with no version-compatibility check.

### Isolate COPILOT_HOME

waza does **not** modify `COPILOT_HOME` — it passes through to the CLI child process. If `COPILOT_HOME` is already set (e.g., `~/.copilot`), every eval run writes sessions and extracts the embedded CLI there. Set an isolated dir for eval:

```powershell
$env:COPILOT_HOME = "$env:USERPROFILE\.copilot-waza"  # or a temp dir
```

This redirects both eval session data and the embedded CLI extraction. Your main `.copilot` stays clean. See [copilot-cli-resolution.md](references/copilot-cli-resolution.md) for details.

**Important ordering:** BYOK profiles are stored in `$COPILOT_HOME/byok-profiles.json`. Select the profile **before** switching `COPILOT_HOME` to the isolated dir — otherwise the wizard/list will find zero profiles.

### Update check

waza performs a **background version check** after every command and prints an update notice if a new version is available (e.g., "A newer version of waza is available: v0.38.7 → v0.38.10"). The check runs in a goroutine but `Result()` blocks up to **100ms** synchronously, and the GitHub API call is cached for **24h**. This is low-overhead but not zero — no additional LLM tokens, but a small network call and sync wait on each invocation. **Do not add a separate update-check mechanism** to the skill; rely on the built-in notice.

For skill updates: this workspace publishes skills via `scripts/publish/publish-skills.ps1`. The update path is to re-run the publish script from the workspace source. No runtime check is needed.

### BYOK mode (no Copilot subscription)

This workspace uses **BYOK** (Bring Your Own Key) by default — no Copilot subscription. waza's copilot-sdk executor passes the parent environment to the CLI child process, so BYOK provider vars set before `waza run` are inherited automatically. See the [copilot-byok](../copilot-byok/SKILL.md) skill for profile management and the full env-var reference.

**Mandatory profile gate:** Before running `waza run` or `waza quality`, you **must** stop and ask which BYOK profile to use — unless the user's prompt explicitly specifies a profile name (e.g., "use ollama profile", "run with opencode-go"). This is a hard requirement: never auto-select or assume a default profile.

**Two selection paths:**

1. **Interactive wizard** (recommended for terminal use) — dot-source with `-i` to launch the account-first picker. The wizard handles account scoping, disabled profiles, and `--account` auto-addition. Env vars are set in the current shell:
   ```powershell
   . skills/copilot-byok/scripts/byok-profile.ps1 set-env -i
   # → pick account (or skip) → pick profile → env vars applied to current shell
   ```
   **Note:** The wizard uses `Read-Host` for input and requires a real terminal. It will **not** work from the powershell tool (which doesn't support interactive input). Use the `ask_user` path below when running from a Copilot session.

2. **Copilot `ask_user`** (for automated selection) — list profiles, present them via `ask_user`, then apply:
   ```powershell
   $profiles = & skills/copilot-byok/scripts/byok-profile.ps1 list
   # → ask_user with the profile list as enum options
   . skills/copilot-byok/scripts/byok-profile.ps1 set-env <selected-profile>
   ```

**If no profiles exist:** The agent should ask the user to either create a profile (`byok-profile.ps1 add`) or specify provider details inline (base URL, model, API key).

**Wizard cancellation:** Press `q` at any menu to cancel cleanly. If the wizard is cancelled, fall back to `ask_user` or ask the user directly.

**Critical ordering:** Select the profile **before** switching `COPILOT_HOME` to the isolated dir. BYOK profiles are stored in `$COPILOT_HOME/byok-profiles.json` — if `COPILOT_HOME` is already set to the isolated dir, the wizard/list will find zero profiles.

Both paths converge on:
```powershell
# 1. Apply profile (COPILOT_HOME still points to main .copilot)
. skills/copilot-byok/scripts/byok-profile.ps1 set-env <profile>

# 2. Switch to isolated home for eval
$env:COPILOT_HOME = "$env:USERPROFILE\.copilot-waza"

# 3. Run waza
waza run skills/<name>/eval.yaml
```

Key BYOK env vars (see [copilot-byok environment-variables](../copilot-byok/references/shared/environment-variables.md) for full reference):
- `COPILOT_PROVIDER_BASE_URL` — provider endpoint
- `COPILOT_MODEL` — model identifier
- `COPILOT_PROVIDER_TYPE` — `openai` (default), `azure`, or `anthropic`
- `COPILOT_PROVIDER_API_KEY` — API key (omit for unauthenticated providers)
- `COPILOT_PROVIDER_WIRE_API` — `completions` (default) or `responses`
- `COPILOT_OFFLINE` — set `true` to prevent GitHub server contact

Note: the isolated `COPILOT_HOME` won't have your existing CLI auth. With BYOK this is fine — auth flows through `COPILOT_PROVIDER_*` vars, not CLI login.

## Quick recipes

```bash
waza check skills/<name>           # offline, no LLM cost
waza tokens suggest skills/<name>

waza run skills/<name>/eval.yaml   # needs BYOK provider vars + isolated COPILOT_HOME (see above)
waza run --baseline skills/<name>/eval.yaml

waza gate --baseline baseline.json --current results.json
```

If `waza check` flags the 500-token budget on a large skill, set `tokens.limits.defaults` (a glob → limit map) in `.waza.yaml` — see [eval format reference](references/waza-eval-format.md#token-budget-override).

## Decision rule

Run `skill-eval` first for zero-cost structural checks. Escalate to `waza` for real model execution, model comparison, or CI regression gating. Complementary, not replacements.

Read references when needed:
- [Eval format and graders](references/waza-eval-format.md) — authoring eval.yaml, task YAML, trigger tests
- [Full command surface](references/waza-commands.md) — flags/subcommands not covered above
- [CI integration](references/waza-ci.md) — wiring `waza gate`/`waza run` into GitHub Actions
- [Copilot CLI resolution](references/copilot-cli-resolution.md) — COPILOT_CLI_PATH override, COPILOT_HOME isolation, BYOK mode
