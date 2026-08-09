# OpenCode Go — Provider Overview (shared)

This index links the two harness-specific files for the **OpenCode Go** provider. Read only the file matching the harness you are configuring:

- **Copilot CLI** → [`cli.md`](cli.md) — env vars, base URL, available models, token overrides, CLI profiles, multiple accounts
- **VS Code Chat** → [`vs-code.md`](vs-code.md) — `chatLanguageModels.json` provider entries per model family, per-agent model pinning

Shared facts that apply to both harnesses (and every provider) live in [`../../shared/`](../../shared/):

- [`../shared/environment-variables.md`](../../shared/environment-variables.md) — `COPILOT_PROVIDER_*` env-var semantics and wire-format rules
- [`../shared/api-key-storage.md`](../../shared/api-key-storage.md) — storing keys at User scope, `${ENV_VAR}` placeholders
- [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md) — `chatLanguageModels.json` mechanism, per-agent pinning, quick start, troubleshooting
- [`../shared/reasoning-effort-lookup.md`](../../shared/reasoning-effort-lookup.md) — per-model `--reasoning-effort` support
- [`../shared/copilot-cli-accounts.md`](../../shared/copilot-cli-accounts.md) — multiple accounts for one provider (CLI registry)

## Key provider facts (OpenCode Go)

- **Single shared base URL**: `https://opencode.ai/zen/go/v1` — serves every model; Copilot CLI appends the correct path based on `COPILOT_PROVIDER_TYPE` / `COPILOT_PROVIDER_WIRE_API`; VS Code uses the full per-model URL.
- **Endpoint per family** (per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints)):
  - `chat/completions` — DeepSeek, GLM, Kimi, MiMo, Grok, Hy3
  - `responses` — GPT-5.6 Luna
  - `messages` — MiniMax (M3/M2.7/M2.5), Qwen (3.8 Max/3.7 Max/3.7 Plus/3.6 Plus); Anthropic Messages API, authenticates with `x-api-key` (not `Authorization: Bearer`)
- **CRITICAL: `COPILOT_MODEL` must use the bare model ID** (e.g., `deepseek-v4-flash`), **not** the `opencode-go/` prefix. The prefix is only used in OpenCode TUI config and in Copilot CLI profile names — never in `COPILOT_MODEL` or VS Code model `id`.
- **Gateway-enforced token limits** are often lower than the model's theoretical context window (e.g. DeepSeek V4 Flash: 1M theoretical vs ~325K effective) — see [`shared/environment-variables.md`](../../shared/environment-variables.md) "Provider-enforced limits".
- **Key env vars** (User scope): `OPENCODE_API_KEY_HOME` (personal), `OPENCODE_API_KEY_WORK` (work) — see [`../shared/api-key-storage.md`](../../shared/api-key-storage.md).
- **Reasoning effort support varies per model family** — GLM, MiMo, Kimi K2.x, Qwen3.x, MiniMax do not support it; DeepSeek V4 Flash/Pro support `low|medium|high`; GPT-5.6 Luna supports the full range. See [`../shared/reasoning-effort-lookup.md`](../../shared/reasoning-effort-lookup.md).

## Usage limits (OpenCode Go)

OpenCode Go imposes dollar-value usage limits tracked in the Zen console:

- **5 hour limit** — $12 of usage
- **Weekly limit** — $30 of usage
- **Monthly limit** — $60 of usage

If you also have OpenCode Zen credits, enable **Use balance** in the console to fall back to your balance after limits are reached.

Some models consume usage at a higher rate — notably **GPT-5.6 Luna** (~2,050 / 5,100 / 10,250 requests per 5-hour / week / month based on a typical 1,000 input + 50,000 cached + 220 output token request). Cheaper models like DeepSeek V4 Flash and MiMo-V2.5 allow far more requests within the same dollar budget.