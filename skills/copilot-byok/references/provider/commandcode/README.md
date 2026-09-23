# Command Code — Provider Overview (shared)

This index links the two harness-specific files for the **Command Code** provider. Read only the file matching the harness you are configuring:

- **Copilot CLI** → [`cli.md`](cli.md) — env vars, base URL, available models, token overrides, CLI profiles, multiple accounts
- **VS Code Chat** → [`vs-code.md`](vs-code.md) — `chatLanguageModels.json` provider entries per model, per-agent model pinning

Shared facts that apply to both harnesses (and every provider) live in [`../../shared/`](../../shared/):

- [`../shared/environment-variables.md`](../../shared/environment-variables.md) — `COPILOT_PROVIDER_*` env-var semantics and wire-format rules
- [`../shared/api-key-storage.md`](../../shared/api-key-storage.md) — storing keys at User scope, `${ENV_VAR}` placeholders
- [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md) — `chatLanguageModels.json` mechanism, per-agent pinning
- [`../shared/reasoning-effort-lookup.md`](../../shared/reasoning-effort-lookup.md) — per-model `--reasoning-effort` support
- [`../shared/copilot-cli-accounts.md`](../../shared/copilot-cli-accounts.md) — multiple accounts for one provider (CLI registry)

## Key provider facts (Command Code)

- **Base URL**: `https://api.commandcode.ai/provider/v1` — OpenAI-compatible.
- **Plan**: GOAT ($10/month) required for API access. Go plan ($1/month) has CLI-only access, no API.
- **Model ID format**: `provider/model-name` (e.g., `deepseek/deepseek-v4-flash`) — differs from bare model IDs used by OpenCode Go profiles.
- **API key**: `COMMANDCODE_API_KEY` at User scope (see [`../shared/api-key-storage.md`](../../shared/api-key-storage.md)).
- **Token limits**: Context windows from official docs; `maxOutputTokens` = 32,768 by default (docs don't publish per-model max output) — exception: **MiMo V2.6 Flash = 128,000** per Xiaomi docs (prompt 872,000).
- **No special headers or proxies required** — standard OpenAI-compatible endpoint.
- **Free models available**: Ling 3.0 Flash Sante (`:free`), Laguna S 2.1, LongCat 2.0 (`:free`).

## Available models (GOAT plan)

| Model | Model ID | Context | Reasoning Effort | Notes |
|-------|----------|---------|-----------------|-------|
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | 1M | Supported (`low`, `medium`, `high`) | Off-peak pricing |
| DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` | 1M | Supported (`low`, `medium`, `high`) | Off-peak pricing |
| MiMo V2.6 Flash | `xiaomi/mimo-v2.6-flash` | 1M (128K max output) | Not supported (binary `thinking` toggle, on by default) | Deep thinking on by default; 128K max output |
| MiMo V2.5 | `xiaomi/mimo-v2.5` | 1M | Not supported | 99% off deal |
| MiMo V2.5 Pro | `xiaomi/mimo-v2.5-pro` | 1M | Not supported | 99% off deal |
| Muse Spark 1.3 Contributor | `meta/muse-spark-1.3-contributor` | 1.05M | Supported (verify) | Meta contributor tier |
| GPT-5.6 Luna | `gpt-5.6-luna` | 1.05M | Supported (full range) | Premium |
| Ling 3.0 Flash Sante | `inclusionai/ling-3.0-flash-sante:free` | 262K | Not supported | Free, 100 req/day |
| Laguna S 2.1 | `poolside/laguna-s-2.1-free` | 256K | Not supported | Free |
| LongCat 2.0 | `meituan/longcat-2.0:free` | 1.05M | Not supported | Free (while it lasts) |

> Reasoning-effort support for Command Code models is inferred from the underlying model capabilities, not verified against Command Code's gateway. Probe with `--reasoning-effort none` before assuming support.
