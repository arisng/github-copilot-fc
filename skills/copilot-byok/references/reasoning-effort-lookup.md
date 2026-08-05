# Reasoning Effort — Per-Model Lookup

Grounded lookup for **which `--reasoning-effort` level to use for a specific model**, focused on OpenCode Go models. This is the authoritative source that the `copilot-cli-subsession` skill defers to; other skills should reference this file instead of re-documenting per-model support.

## How to use

1. Find the model in the tables below (or run `curl https://opencode.ai/zen/go/v1/models` for the current catalog).
2. **Supported** → pass `--reasoning-effort <level>`. Recommended default: `high` unless the workload needs less (cost / latency) or more (only where the model's range includes it).
3. **Not supported** → omit `--reasoning-effort` entirely. The model uses its built-in default reasoning behavior; passing the flag triggers the API error `Model "<id>" does not support reasoning effort configuration (requested: "<level>")`.

## OpenCode Go models that support reasoning effort

| Model | Bare model ID (`COPILOT_MODEL`) | Provider type | Wire format | Supported levels | Recommended default |
| --- | --- | --- | --- | --- | --- |
| GPT-5.6 Luna | `gpt-5.6-luna` | `openai` | `completions` or `responses` | Full range: `none` … `max` | `high` |
| DeepSeek V4 Flash | `deepseek-v4-flash` | `openai` | `completions` | `low`, `medium`, `high` (no `xhigh` / `max`) | `high` |
| DeepSeek V4 Pro | `deepseek-v4-pro` | `openai` | `completions` | `low`, `medium`, `high` (no `xhigh` / `max`) | `high` |

> **Wire placement (2026-08-05)**: on the `responses` wire, GPT-5.6 Luna requires the effort **nested** as `reasoning.effort` — a top-level `reasoning_effort` field returns 400. Copilot CLI/VS Code already send the nested form, so `wireApi: responses` works end-to-end. On `completions`, use top-level `reasoning_effort` (all levels incl. `max` verified).

## OpenCode Go models WITHOUT reasoning-effort support

For these, never pass `--reasoning-effort`; thinking is implicit or always-on.

| Family | Model IDs (`COPILOT_MODEL`) | Provider type | Notes |
| --- | --- | --- | --- |
| Kimi K2.x (Moonshot AI) | `kimi-k2.7-code`, `kimi-k2.6`, `kimi-k2.5` | `openai` | K2.7 thinking always-on; K2.6/K2.5 implicit |
| GLM (Zhipu AI) | `glm-5.2`, `glm-5.1`, `glm-5` | `openai` | No controllable levels |
| MiMo (Xiaomi) | `mimo-v2.5`, `mimo-v2.5-pro`, `mimo-v2-pro`, `mimo-v2-omni` | `openai` | No controllable levels |
| Qwen3.x (Alibaba) | `qwen3.7-plus`, `qwen3.7-max`, `qwen3.6-plus`, `qwen3.5-plus` | `anthropic` (`messages` per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints)) | Implicit thinking |
| MiniMax | `minimax-m3`, `minimax-m2.7`, `minimax-m2.5` | `anthropic` (`messages` per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints)) | Implicit thinking |

## OpenCode Go models with UNKNOWN reasoning-effort support

These models appear in the live catalog (`https://opencode.ai/zen/go/v1/models`, 2026-08-03) but are not yet classified. The catalog exposes no reasoning-effort metadata, so probe before use (`copilot --reasoning-effort none`, then escalate) and record the result here.

| Model ID | Notes |
| --- | --- |
| `kimi-k3` | Newest Kimi; assume implicit thinking until probed (K2.x family has no support) |
| `qwen3.8-max` | Newer Qwen; assume no support until probed (Qwen3.x family has no support) |
| `hy3` | Unknown family |
| `hy3-preview` | Preview variant of `hy3` |
| `grok-4.5` | xAI; unknown support |

## Verify for any model (not just OpenCode Go)

1. **Check the stored profile** — `.\scripts\byok-profile.ps1 show <profile>` prints `Reasoning Effort Supported`. Profiles for models without support carry `"reasoningEffortSupported": false`, set automatically by the `add` wizard and maintained in `~/.copilot/byok-profiles.json`.
2. **Probe the API** — start with the least demanding level:
   `copilot --reasoning-effort none`
   - Error `Model "<id>" does not support reasoning effort configuration` → the model has no controllable levels; omit the flag.
   - Success → escalate (`low` → `medium` → `high` → …) until the model rejects a level or you reach what you need.
3. **Copilot CLI only** — there is no `COPILOT_*` environment variable for reasoning effort unless `copilot help environment` in the installed CLI version lists one.

## Tooling that enforces this lookup

- `byok-profile.ps1 run` strips incompatible `--reasoning-effort` / `--effort` arguments (flag + value) when the profile has `reasoningEffortSupported: false`, warns, then forwards the rest.
- `Invoke-CopilotCliSubSession.ps1` (copilot-cli-subsession) does the same: it forwards `--reasoning-effort` only when the resolved profile supports it, and warns otherwise.

## Grounding

- **Evidence-backed**: GPT-5.6 Luna full range incl. `max` (models.dev capabilities; OpenCode Go docs; VS Code `supportsReasoningEffort: ["low","medium","high","max"]`); DeepSeek V4 Flash/Pro limited to `low|medium|high` (VS Code `supportsReasoningEffort` lists; API error signature for out-of-range levels); Kimi / GLM / MiMo / Qwen / MiniMax lack of support (API error signature `does not support reasoning effort configuration`; `$noReasoningEffortModels` in `byok-profile.ps1`).
- **Inferred (operational)**: the `high` recommended default — a tuning choice, not an API constraint. It matches the `byok-profile.ps1` and `Invoke-CopilotCliSubSession.ps1` defaults and the documented GPT-5.6 Luna example (`copilot --reasoning-effort high`).

`Grounding status: mixed (evidence + inference)` — per-model support facts are evidence-backed; the `high` default is inferred operational guidance.
