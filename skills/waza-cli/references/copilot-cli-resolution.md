# Copilot CLI Resolution (COPILOT_CLI_PATH)

How `scripts/Resolve-CopilotCliPath.ps1` decides which Copilot CLI binary waza runs, which install channels are real, and how to isolate `COPILOT_HOME` for eval runs.

## Default: waza's bundled CLI (recommended)

With `COPILOT_CLI_PATH` unset, waza spawns its **bundled CLI** — v1.0.85 for waza 0.38.7. This version is pinned at waza build time via `COPILOT_CLI_VERSION` (see `internal/embedded/generate/generate.go` in the waza repo). It is the exact CLI waza was built and tested against, giving reproducible results across machines and CI runs.

**Do not set `COPILOT_CLI_PATH` by default.** The resolver is an opt-in override for when you need a specific machine CLI.

### Why machine-default is risky

| Risk | Detail |
|---|---|
| Version variance | Machine CLI varies by box: 1.0.92 (WinGet MSIX), 1.0.80 (npm), etc. |
| No version check | waza does `os.Stat` only — no protocol version validation before spawning |
| Protocol incompatibility | The SDK negotiates a protocol version at connection time; an incompatible CLI fails mid-eval |
| Silent misbehavior | A compatible-but-different CLI may produce subtly different eval results with no error |

The bundled CLI is the only version **known** to work with waza 0.38.7.

## Source-verified waza contract

From `microsoft/waza` `internal/execution/sdkclient.go`:

| `COPILOT_CLI_PATH` state | waza behavior |
|---|---|
| Set to an existing non-directory file | `os.Stat` passes → that exact binary is spawned (`source=COPILOT_CLI_PATH`) |
| Set but missing/directory | Hard error: `COPILOT_CLI_PATH %q is not usable` |
| Unset | waza extracts and uses its **bundled** CLI (`source=embedded`) and **refuses to fall back to PATH** |

Consequence: waza never discovers your installed CLI on its own. To override, the variable must be exported before `waza run` / `waza quality`.

## Resolution priority (opt-in override)

Use `scripts/Resolve-CopilotCliPath.ps1` only when you need to force a specific machine CLI:

1. **Existing `$env:COPILOT_CLI_PATH`** — honored when usable; a stale value triggers a warning and re-detection instead of waza's hard error.
2. **`copilot` on PATH** — first candidate that passes validation. On Windows only `.exe` hits are considered; `.ps1` and extensionless shims are not executable images for waza's Go `os/exec` (batch `.cmd` launchers are likewise not directly executable there), so a native image is required.
3. **Known locations** — npm global platform binary (`<npm root -g>/@github/copilot/node_modules/@github/copilot-*/copilot[.exe]`).
4. **Install fallback** (`-InstallFallback`, Windows) — only when steps 1–3 found nothing:
   1. `winget install -e --id GitHub.Copilot.CLI` — the requested MSIX package
   2. `winget install -e --id GitHub.Copilot` — official portable package, then re-detect

Validation of every candidate mirrors waza: exists, is not a directory, and (unless `-SkipProbe`) runs `--version` successfully with a **10-second timeout** — a hanging binary counts as a failed candidate and resolution moves on.

## Usage (opt-in override)

```powershell
# Detect and export for the current session, installing only if no CLI exists
$env:COPILOT_CLI_PATH = & skills/waza-cli/scripts/Resolve-CopilotCliPath.ps1 -InstallFallback

# Also persist at user scope for future sessions
& skills/waza-cli/scripts/Resolve-CopilotCliPath.ps1 -InstallFallback -Persist | Out-Null

waza run skills/<name>/eval.yaml
```

The script prints only the resolved path on stdout; diagnostics go to the verbose stream and **warnings are re-emitted on stderr** at the process boundary, so both the in-session pattern above and cross-process capture (`path=$(pwsh -File …)`) receive exactly one line. Exit 1 when nothing was found.

Caveat for `-Persist`: a user-level environment-variable write affects **new sessions only** — the current session must still use the capture-then-assign line above, or waza in this session will keep running its bundled CLI.

## COPILOT_HOME isolation

waza does **not** modify `COPILOT_HOME`. The `commandmock.RuntimeEnvironment()` function copies `os.Environ()` wholesale and only touches `PATH` + `WAZA_COMMAND_MOCK_*`. If `COPILOT_HOME` is already set (e.g., `~/.copilot`), every eval run writes sessions and extracts the embedded CLI there.

**Isolate for eval runs:**

```powershell
$env:COPILOT_HOME = "$env:USERPROFILE\.copilot-waza"
waza run skills/<name>/eval.yaml
```

This redirects both eval session data and the embedded CLI extraction to the isolated dir. Your main `.copilot` stays clean.

**Critical ordering:** BYOK profiles are stored in `$COPILOT_HOME/byok-profiles.json`. Select the profile **before** switching `COPILOT_HOME` to the isolated dir — otherwise the wizard/list will find zero profiles.

Note: the isolated `COPILOT_HOME` won't have your existing CLI auth. With BYOK this is fine — auth flows through `COPILOT_PROVIDER_*` vars, not CLI login.

## Update check

waza performs a **background version check** after every command and prints an update notice if available. The check runs in a goroutine but `Result()` blocks up to **100ms** synchronously, and the GitHub API call is cached for **24h**. This is low-overhead but not zero — no additional LLM tokens, but a small network call and sync wait on each invocation. Do not add a separate update-check mechanism; rely on the built-in notice.

For skill updates: re-run `scripts/publish/publish-skills.ps1` from the workspace source. No runtime check needed.

## BYOK mode (no Copilot subscription)

This workspace uses **BYOK** (Bring Your Own Key) by default. waza's copilot-sdk executor passes the parent environment to the CLI child process, so BYOK provider vars set before `waza run` are inherited automatically. See the [copilot-byok](../../copilot-byok/SKILL.md) skill for profile management.

**Mandatory profile gate:** Before running `waza run` or `waza quality`, you **must** stop and ask which BYOK profile to use — unless the user's prompt explicitly specifies a profile name. This is a hard requirement: never auto-select or assume a default profile.

**Two selection paths:**

1. **Interactive wizard** (recommended for terminal use) — dot-source with `-i` to launch the account-first picker:
   ```powershell
   . skills/copilot-byok/scripts/byok-profile.ps1 set-env -i
   # → pick account (or skip) → pick profile → env vars applied to current shell
   ```
   The wizard handles account scoping, disabled profile filtering, and `--account` auto-addition for grouped profiles. **Note:** The wizard uses `Read-Host` and requires a real terminal — it will **not** work from the powershell tool. Use the `ask_user` path when running from a Copilot session.

2. **Copilot `ask_user`** (for automated selection):
   ```powershell
   $profiles = & skills/copilot-byok/scripts/byok-profile.ps1 list
   # → ask_user with the profile list as enum options
   . skills/copilot-byok/scripts/byok-profile.ps1 set-env <selected-profile>
   ```

**If no profiles exist:** Ask the user to either create a profile (`byok-profile.ps1 add`) or specify provider details inline.

**Wizard cancellation:** Press `q` at any menu to cancel cleanly. If cancelled, fall back to `ask_user` or ask the user directly.

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

Key BYOK env vars (see [copilot-byok environment-variables](../../copilot-byok/references/shared/environment-variables.md) for full reference):
- `COPILOT_PROVIDER_BASE_URL` — provider endpoint
- `COPILOT_MODEL` — model identifier
- `COPILOT_PROVIDER_TYPE` — `openai` (default), `azure`, or `anthropic`
- `COPILOT_PROVIDER_API_KEY` — API key (omit for unauthenticated providers)
- `COPILOT_PROVIDER_WIRE_API` — `completions` (default) or `responses`
- `COPILOT_OFFLINE` — set `true` to prevent GitHub server contact

## Verified install channels (2026-09-22)

| Channel | Command / ID | Artifact | Status |
|---|---|---|---|
| winget MSIX (requested fallback) | `GitHub.Copilot.CLI` | MSIX | **Not published** — `winget show` returns "No package found" (winget + msstore sources). The script still tries it first so it takes over automatically if/when GitHub publishes it. |
| winget official | `winget install GitHub.Copilot` | zip → portable exe | Available (v1.0.87). Documented in `github/copilot-cli` README and `install.sh`. Declares a package dependency on PowerShell ≥ 7.0. |
| Microsoft Store | `XPDC8MMRVCF73P` ("GitHub Copilot CLI") | **MSI**, not MSIX | Available (v1.0.87). Install via `winget install XPDC8MMRVCF73P --source msstore`. |
| npm | `npm install -g @github/copilot` | node + platform package | Available; documented in README and GitHub Docs. |
| GitHub releases | `github/copilot-cli` release assets | zip / msi / tar.gz / tgz | Available; **no `.msix` asset exists** in v1.0.83 or v1.0.87. |

Note on a machine-local MSIX: an installed package named `GitHub.Copilot.CLI` (SignatureKind=Developer) is a **sideloaded** package — no public install channel for that package identity was found in winget, winget-pkgs, GitHub releases, GitHub Docs, or the copilot-cli repo. It is not produced by any of the channels above.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| waza: `COPILOT_CLI_PATH %q is not usable` | Stale variable (deleted/moved binary, or a directory) | Re-run `Resolve-CopilotCliPath.ps1` without `-SkipProbe` and re-export |
| waza: `embedded Copilot CLI is unavailable and COPILOT_CLI_PATH is not set; refusing to fall back to PATH` | Variable unset and bundled extraction failed | Set `COPILOT_CLI_PATH` via the script |
| waza log shows `source=embedded` though a CLI is installed | Variable was never exported to the waza process | Export before invoking waza (capture-then-assign pattern above) |
| Detected path ends in `.cmd`/`.ps1` (Windows) | Shim leaked through an explicit override | Point at the native exe; the script skips shims automatically during detection |
| waza: embedded CLI extraction fails | Cache dir permissions or disk space | Set `COPILOT_CLI_INSTALL_VERBOSE=1` for diagnostics, or set `COPILOT_CLI_PATH` to a known-good CLI |
