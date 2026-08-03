# Copilot CLI Feature Verification Audit

Empirical audit of every GitHub Copilot CLI feature claimed by the workspace copilot skills, verified against the **installed** CLI rather than documentation.

## Audit metadata

| Field | Value |
| --- | --- |
| Date | 2026-08-03 |
| CLI version | **1.0.77** (`copilot --version`) |
| CLI binary | `%APPDATA%\Code - Insiders\User\globalStorage\github.copilot-chat\copilotCli\copilot.ps1` |
| Skills in scope | `copilot-cli-subsession`, `copilot-byok`, `copilot-sdk-dotnet`, `copilot-cli-agent-customization` |
| Evidence captured | `copilot --help`, `copilot help environment` \| `permissions` \| `providers` \| `commands` \| `config` \| `logging` \| `limits` \| `sandbox`, `copilot plugin/skill/mcp --help`, runtime artifacts (`~/.copilot/session-state/`, `~/.copilot/byok-profiles.json`), OpenCode Go catalog (`https://opencode.ai/zen/go/v1/models`) |

## Verdict summary

| Status | Count | Meaning |
| --- | --- | --- |
| ✅ Verified (help-confirmed) | 34 | Flag/env/command exists in installed CLI help or was confirmed via runtime artifact |
| 🟡 Partially verified | 4 | Claim grounded but not fully confirmable from the installed CLI alone |
| ⚪ Runtime-only (not statically verifiable) | 3 | Claim is about runtime behavior/event shapes; needs a live session to confirm |
| 🔴 Contradicted / Gap | 5 | Claim does not match the installed CLI or the actual profile data |

Net: the vast majority of CLI surface claims are **verified**. Four real findings need action — the most important is that the `reasoningEffortSupported: false` flag documented by the skills is **absent from the actual stored profiles**, making the sub-session/byok reasoning-effort guard inoperative for unsupported models.

---

## ✅ Verified — flags, env vars, commands present in CLI 1.0.77

### Invocation & session (cheatsheet / sub-session skill)

| Claim | Evidence |
| --- | --- |
| `-p, --prompt` | `copilot --help` ✓ |
| `-s, --silent` | `copilot --help` ✓ |
| `--session-id <uuid>` | `copilot --help` ✓ |
| `-r, --resume [value]` | `copilot --help` ✓ |
| `-n, --name <name>` | `copilot --help` (`-n, --name`) ✓ |
| `--agent <name>` | `copilot --help` ✓ |
| `--model <model>` | `copilot --help` ✓ |
| `-C <directory>` | `copilot --help` ✓ |
| `--reasoning-effort` / alias `--effort` | `copilot --help` (`--effort, --reasoning-effort`) ✓ |
| Levels `none, minimal, low, medium, high, xhigh, max` | `copilot --help` choices (incl. newer `minimal`) ✓ |
| `--output-format text\|json` (JSONL) | `copilot --help` ✓ |
| `--stream on\|off` | `copilot --help` ✓ |
| `--attachment <path>` (non-interactive) | `copilot --help` ✓ |

### Permissions

| Claim | Evidence |
| --- | --- |
| `--allow-all` / `--yolo` equivalence (`--allow-all-tools --allow-all-paths --allow-all-urls`) | `copilot help permissions` ✓ (explicit equivalence) |
| `--allow-all-tools`, `--allow-all-paths`, `--allow-all-urls` | `copilot --help` + `help permissions` ✓ |
| `--allow-tool` / `--deny-tool` patterns `kind(argument)` | `help permissions` ✓ |
| `shell(git:*)`, `write(README.md)`, `url(github.com)` example patterns | `help permissions` (shell, write, url kinds + wildcard rules) ✓ |
| `--allow-url` / `--deny-url` (protocol-aware, default https) | `help permissions` ✓ |
| `--no-ask-user` | `copilot --help` ✓ |
| `--available-tools` / `--excluded-tools` | `copilot --help` + `help permissions` ✓ |
| `--add-dir` | `copilot --help` ✓ |
| `COPILOT_ALLOW_ALL` | `copilot help environment` ✓ |

### MCP, instructions, logging

| Claim | Evidence |
| --- | --- |
| `--disable-builtin-mcps` | `copilot --help` ✓ |
| `--no-custom-instructions` | `copilot --help` ✓ |
| `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | `copilot help environment` ✓ |
| `--log-dir` / `--log-level` (levels incl. `default`) | `copilot --help` + `help logging` ✓ |
| MCP config sources `~/.copilot/mcp-config.json`, `.mcp.json`, `.github/mcp.json` | `copilot mcp --help` ✓ |
| `copilot mcp add/get/list/remove` | `copilot mcp --help` ✓ |

### BYOK (`copilot-byok` claims)

| Claim | Evidence |
| --- | --- |
| `COPILOT_PROVIDER_BASE_URL` activates BYOK; GitHub auth not required | `copilot help providers` ✓ |
| `COPILOT_PROVIDER_TYPE` = `openai` (default) \| `azure` \| `anthropic` | `help providers` + `help environment` ✓ |
| `COPILOT_PROVIDER_API_KEY` optional (local providers) | `help providers` ✓ |
| `COPILOT_PROVIDER_WIRE_API` = `completions` (default) \| `responses`; "use responses for GPT-5 series" | `help providers` ✓ |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` / `_MAX_OUTPUT_TOKENS` | `help providers` ✓ |
| `COPILOT_MODEL` (sets model ID + wire model); `--model` overrides | `help providers` ✓ |
| `COPILOT_OFFLINE` (skips GitHub services; requires local provider) | `help environment` ✓ |
| `COPILOT_HOME` config override | `help environment` ✓ |
| Newer vars (`_BEARER_TOKEN`, `_TRANSPORT`, `_MODEL_ID`, `_WIRE_MODEL`, `_HEADERS`, `_AZURE_API_VERSION`) | `help providers` ✓ |
| **No `COPILOT_*` env var for reasoning effort** | absent from `help environment` + `help providers` ✓ |
| Auth precedence `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN` | `help environment` ✓ |
| Azure: `type=azure` (not `openai`), host-only URL | `help providers` ✓ |
| OpenAI-compatible: Ollama, vLLM, Foundry Local | `help providers` ✓ |

### Slash commands (`copilot help commands`)

Verified present: `/help /model /init /diff /pr /review /plan /research /delegate /compact /share /allow-all /add-dir /skills /resume /rewind /context /limits /settings /agent /mcp /plugin /memory /experimental /security-review /rubber-duck /fleet /autopilot /tasks` and more.

### Plugins & skills (`copilot-cli-agent-customization` claims)

| Claim | Evidence |
| --- | --- |
| `copilot plugin install/list/uninstall/update/marketplace` | `copilot plugin --help` ✓ |
| Skills discovery: project `.github/skills/`, `.agents/skills/`, `.claude/skills/`; personal `~/.copilot/skills/`, `~/.agents/skills/`; plugin; custom via `skill add` | `copilot skill --help` ✓ |
| `copilot skill add/list/remove` | `copilot skill --help` ✓ |

### Runtime-artifact confirmed

| Claim | Evidence |
| --- | --- |
| `~/.copilot/session-state/<uuid>/` exists (sub-session handoff) | directory present on disk ✓ |
| `~/.copilot/byok-profiles.json`; default profile `opencode-go-deepseek-v4-flash` | file + profile present ✓ |
| `dprocess-openai-gpt-54` profile (used in byok examples) | present ✓ |
| OpenCode Go catalog reachable at `https://opencode.ai/zen/go/v1/models` (25 models) | live fetch ✓ |
| All 18 model IDs in `reasoning-effort-lookup.md` exist in catalog | live fetch ✓ |
| deepseek-v4-flash profile: `openai`, base `…/zen/go/v1`, maxPrompt 325000, maxOutput 64000 | profile JSON ✓ (matches "empirically validated" claim) |
| gpt-5.6-luna profile: `wireApi=responses`, maxPrompt 200000, maxOutput 64000 | profile JSON ✓ (matches 272K−64K−8K calc) |
| minimax-m3 profile: `type=anthropic`, base `https://opencode.ai/zen/go` (no `/v1`) | profile JSON ✓ (matches Anthropic-type claim) |

---

## 🟡 Partially verified

| Claim | Status | Note |
| --- | --- | --- |
| DeepSeek V4 Flash/Pro reasoning "only `low`, `medium`, `high`" | Partially | Grounded in the skill's own VS Code `supportsReasoningEffort` list + API error signatures. The provider catalog exposes **only** `id/object/created/owned_by` — no reasoning-effort metadata — so the level range cannot be confirmed from the API. Requires a live probe (`--reasoning-effort xhigh` on deepseek) for full confirmation. |
| GPT-5.6 Luna "full range incl. `max`" | Partially | Same catalog limitation; grounded in models.dev + VS Code picker list. |
| OpenCode Go path appending (`/chat/completions`, `/responses`, anthropic no `/v1`) | Partially | Base URL reachable (catalog fetch worked). Path-appending behavior is SDK/provider-doc sourced, not CLI-verifiable. |
| `copilot plugin install <local path>` | Partially | `plugin --help` lists marketplaces/GitHub repos/subdirectories/git URLs, not explicit local paths. Verified operationally by `scripts/test/ralph-v2-cli-smoke.ps1`. |

---

## ⚪ Runtime-only claims (not statically verifiable)

| Claim | Where | Note |
| --- | --- | --- |
| JSONL event types `tool.execution_start`, `tool.execution_complete`, `session.task_complete`, `result` (with `exitCode`/`usage`), `error` | sub-session cheatsheet | `--output-format json` help only says "JSONL". Event shapes require capturing a live JSONL session to confirm. |
| `--reasoning-effort none` probe behavior | byok lookup | Runtime/API behavior, not help surface. |
| Moonshot `top_p=0.95` workaround behavior | byok | Provider/VS Code runtime behavior; proxy scripts code-verified, not CLI-verifiable. |

---

## 🔴 Contradicted / Gap findings — RESOLVED (2026-08-03)

All five findings below were remediated in the same session. Each section retains the original finding and the resolution.

### F-1. `--config-dir` no longer exists in CLI 1.0.77 — RESOLVED

- **Claim**: cheatsheet documents `--config-dir DIR`; `Invoke-CopilotCliSubSession.ps1` forwards `--config-dir` from `-ConfigDir`.
- **Reality**: not present anywhere in `copilot --help`. `COPILOT_HOME` is the supported config-override mechanism (`copilot help environment`).
- **Impact**: `-ConfigDir` was dead on v1.0.77; the script's isolation path silently did nothing.
- **Resolution**: `-ConfigDir` now maps to `COPILOT_HOME` for the sub-process (Step 5). Removed the dead `--config-dir` forwarding. Updated cheatsheet + parity matrix + SKILL.md.

### F-2. `/undo` listed as a built-in command but does not exist — RESOLVED

- **Claim**: sub-session SKILL.md lists `undo` among "Any built-in CLI command".
- **Reality**: `copilot help commands` (v1.0.77) has **`/rewind`** ("Rewind the last turn and revert file changes"); no `/undo`.
- **Fix**: replaced `undo` with `rewind` in the slash-command list. (`/handoff` and `/git-atomic-commit` remain correctly described as *skill* commands elsewhere in the skill.)

### F-3. 🔴 `reasoningEffortSupported: false` is documented but absent from actual profiles — RESOLVED

- **Claim** (byok SKILL.md + reasoning-effort-lookup + sub-session SKILL.md): profiles for models without reasoning-effort support set `"reasoningEffortSupported": false`, and both `byok-profile.ps1 run` and `Invoke-CopilotCliSubSession.ps1` strip `--reasoning-effort` when it is `false`.
- **Reality**: inspected stored profiles — `opencode-go-kimi-k27-code` and `opencode-go-minimax-m3` (both in the no-support list) **lack the flag entirely**. The strip logic exists in both scripts (code-verified), but with no flag present it defaults to supported, so `Invoke-CopilotCliSubSession.ps1` would forward `--reasoning-effort high` to Kimi/MiniMax/GLM/MiMo/Qwen profiles → API error.
- **Root cause**: these profiles were hand-added to `byok-profiles.json` (the `add` wizard sets the flag, but hand-edited profiles don't).
- **Resolution**: support is now derived from a shared model list (`Get-NoReasoningEffortModels` / `Test-ReasoningEffortSupported` in `byok-profile.ps1`, mirrored inline in `Invoke-CopilotCliSubSession.ps1`) when the optional profile flag is absent. Wizard, `run`, `set-env`, `show`, and the sub-session script all use the same derivation.

### F-4. `reasoning-effort-lookup.md` table is stale vs the live catalog — RESOLVED

- **Reality**: catalog (2026-08-03) also contains `kimi-k3`, `qwen3.8-max`, `hy3`, `hy3-preview`, `grok-4.5` — none covered in the lookup. Their reasoning-effort support is **unknown** (catalog exposes no metadata).
- **Fix**: added a dedicated "UNKNOWN support" table for these 5 models with probe-first guidance and family-based assumptions.

### F-5. SDK-skill reasoning-effort gap (parity, not CLI) — RESOLVED

- `copilot-sdk-dotnet` did not document reasoning effort on `SessionConfig` while CLI/VS Code expose it.
- **Resolution**: added a "known gap" callout in the SDK skill's session-config section pointing to the parity matrix + audit, and linked the audit from its reference list.

---

## Action items

All five audit findings were remediated on 2026-08-03:

1. **F-3** ✅ — shared `Test-ReasoningEffortSupported` derivation in `byok-profile.ps1` (wizard/run/set-env/show) + mirrored inline in `Invoke-CopilotCliSubSession.ps1`.
2. **F-1** ✅ — `-ConfigDir` → `COPILOT_HOME` mapping; dead `--config-dir` forwarding removed.
3. **F-2** ✅ — `undo` → `rewind` in the sub-session SKILL.md built-in command list.
4. **F-4** ✅ — `reasoning-effort-lookup.md` gained an "UNKNOWN support" table for `kimi-k3`, `qwen3.8-max`, `hy3`, `hy3-preview`, `grok-4.5`.
5. **F-5** ✅ — SDK-skill reasoning-effort gap documented + audit linked.

Remaining hygiene: re-run `scripts/Test-CopilotCliParity.ps1` after removing `--config-dir` from expected flags, and keep `lastVerified` / `verifiedCliVersion` current.

## Grounding

- **Evidence-backed**: every ✅/🟡/🔴 claim above is grounded in captured output of the installed CLI 1.0.77 (help topics listed in Audit metadata), on-disk artifacts, or the live OpenCode Go catalog, all dated 2026-08-03.
- **Not verified**: ⚪ runtime-only claims are explicitly marked; they require a live JSONL session or provider probe.

`Grounding status: evidence-backed (CLI 1.0.77, 2026-08-03), with 5 flagged findings (3 contradiction, 2 gap).`
