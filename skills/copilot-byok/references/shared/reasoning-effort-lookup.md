# Reasoning Effort — Per-Model Lookup (shared)

Grounded lookup for **which `--reasoning-effort` level to use for a specific model**. This is the authoritative source that the `copilot-cli-subsession` skill defers to; other skills should reference this file instead of re-documenting per-model support.

The method applies to any BYOK model. The detailed per-model rows for OpenCode Go live in [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md) (Available Models table) so this shared file stays provider-agnostic — only cross-provider facts and the verification workflow remain here.

## How to use

1. Find the model in the provider's Available Models table (for OpenCode Go, [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md) — or run `curl https://opencode.ai/zen/go/v1/models` for the current catalog).
2. **Supported** → pass `--reasoning-effort <level>`. Recommended default: `high` unless the workload needs less (cost / latency) or more (only where the model's range includes it).
3. **Not supported** → omit `--reasoning-effort` entirely. The model uses its built-in default reasoning behavior; passing the flag triggers the API error `Model "<id>" does not support reasoning effort configuration (requested: "<level>")`.

## Supported levels

`none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` — per-model subset varies. Example (OpenCode Go): DeepSeek V4 models only support `low`, `medium`, `high` (`minimal` is newer, verified in CLI 1.0.77); GPT-5.x-class models support the full range including `max`.

## Wire placement (probed 2026-08-05)

On the `responses` wire, effort must be **nested** as `reasoning.effort` — a top-level `reasoning_effort` field returns 400. Copilot CLI/VS Code already send the nested form, so `wireApi: responses` works end-to-end. On `completions`, use top-level `reasoning_effort` (all levels incl. `max` verified). Per-provider detail: [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md).

## Known families WITHOUT reasoning-effort support (OpenCode Go)

For these, never pass `--reasoning-effort`; thinking is implicit or always-on. Full table with model IDs: [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md).

- **Kimi K2.x** (Moonshot AI) — thinking always-on / implicit
- **GLM** (Zhipu AI) — no controllable levels
- **MiMo** (Xiaomi) — no controllable levels
- **Qwen3.x** (Alibaba) — implicit thinking (`anthropic` type, `messages` wire per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints))
- **MiniMax** (MiniMax) — implicit thinking (`anthropic` type, `messages` wire)

## OpenCode Go models with UNKNOWN reasoning-effort support

These appear in the live catalog (`https://opencode.ai/zen/go/v1/models`, 2026-08-03) but are not yet classified: `kimi-k3`, `qwen3.8-max`, `hy3`, `hy3-preview`, `grok-4.5`. The catalog exposes no reasoning-effort metadata, so probe before use (start with `--reasoning-effort none`) and record the result in [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md).

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