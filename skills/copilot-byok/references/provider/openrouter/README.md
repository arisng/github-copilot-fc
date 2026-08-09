# OpenRouter — Provider Overview (shared)

This index links the two harness-specific files for the **OpenRouter** provider. Read only the file matching the harness you are configuring:

- **Copilot CLI** → [`cli.md`](cli.md) — env vars, `:floor` / `:nitro` routing suffixes, CLI profiles, per-model audit
- **VS Code Chat** → [`vs-code.md`](vs-code.md) — `chatLanguageModels.json` provider entries, per-agent model pinning

Shared facts that apply to both harnesses (and every provider) live in [`../../shared/`](../../shared/):

- [`../shared/environment-variables.md`](../../shared/environment-variables.md) — `COPILOT_PROVIDER_*` env-var semantics and wire-format rules
- [`../shared/api-key-storage.md`](../../shared/api-key-storage.md) — storing keys at User scope, `${ENV_VAR}` placeholders
- [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md) — `chatLanguageModels.json` mechanism, per-agent pinning, quick start, troubleshooting
- [`../shared/reasoning-effort-lookup.md`](../../shared/reasoning-effort-lookup.md) — per-model `--reasoning-effort` support

## Key provider facts (OpenRouter)

- **Base URL**: `https://openrouter.ai/api/v1` — OpenAI-compatible.
- **Routing suffixes**: `:floor` (cheapest provider), `:nitro` (fastest provider), no suffix (load-balanced). See [`cli.md`](cli.md).
- **API key**: `OPENROUTER_API_KEY` at User scope (see [`../shared/api-key-storage.md`](../../shared/api-key-storage.md)).
- **Token caps**: conservative 200K input / 64K output recommended across DeepSeek V4 models (routing across many upstream providers with variable per-request limits). See [`cli.md`](cli.md) for the empirical audit.