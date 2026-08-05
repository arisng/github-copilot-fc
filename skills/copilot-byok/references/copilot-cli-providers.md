# BYOK Provider Reference

Quick-reference for configuring Copilot CLI BYOK providers.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `COPILOT_PROVIDER_BASE_URL` | Yes | Base URL of the provider's API endpoint. |
| `COPILOT_MODEL` | Yes | Model identifier. Can also be set via `--model` flag. |
| `COPILOT_PROVIDER_TYPE` | No | Provider type: `openai`, `azure`, or `anthropic`. Defaults to `openai`. |
| `COPILOT_PROVIDER_API_KEY` | No | API key. Omit for unauthenticated providers (e.g., local Ollama). |
| `COPILOT_PROVIDER_WIRE_API` | No | Provider wire format: `completions` (default) or `responses`. GPT-5 class OpenAI models (e.g. OpenCode Go's GPT-5.6 Luna) work on **both** on OpenCode Go (probe 2026-08-03, re-verified 2026-08-05); `responses` is the recommended default for GPT-5-class. On the `responses` wire the reasoning field must be **nested** (`reasoning.effort`, what Copilot CLI sends) — a top-level `reasoning_effort` is rejected with 400. `max_prompt_tokens` is also rejected on the `responses` wire, but the CLI never sends it there (verified end-to-end 2026-08-05, CLI 1.0.78). |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | No | Override the max prompt token limit Copilot CLI uses for the model. Useful when the model is not in Copilot's built-in catalog. |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | No | Override the max output token limit Copilot CLI uses for the model. |
| `COPILOT_OFFLINE` | No | Set to `true` to prevent Copilot CLI from contacting GitHub's servers. |

## Supported Providers

| Provider Type | Compatible Services |
|---------------|---------------------|
| `openai` | OpenAI, Ollama, vLLM, Foundry Local, OpenCode Go (OpenAI-compatible models), and any OpenAI Chat Completions / Responses API-compatible endpoint (default) |
| `azure` | Azure OpenAI Service |
| `anthropic` | Anthropic (Claude models), OpenCode Go (Anthropic-compatible models — MiniMax, Qwen; see [OpenCode Go docs endpoints](https://opencode.ai/docs/go/#endpoints)) |

## Model Requirements

The chosen model must support:
- **Tool calling** (function calling)
- **Streaming**

For best results, use a model with a context window of at least **128k tokens**. If your model supports a larger context window and is not in Copilot CLI's built-in catalog, set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to its actual limit so Copilot CLI doesn't fall back to a smaller default.

## Reasoning Effort

Reasoning level is configured via Copilot CLI option `--reasoning-effort` (alias: `--effort`) per invocation.

Supported levels:
- `none`
- `minimal`
- `low`
- `medium`
- `high`
- `xhigh`
- `max`

> Not all models support every level. For example, DeepSeek V4 models on OpenCode Go support only `low`, `medium`, `high`. Check the Reasoning Effort column in the Available Models table below for per-model notes.

Example:

```powershell
copilot --reasoning-effort medium
```

If you run through BYOK profile script passthrough:

```powershell
.\scripts\byok-profile.ps1 run dprocess-openai-gpt-54 --reasoning-effort medium
```

### Model compatibility

Not all models support `--reasoning-effort`. If you get:

```
Model "glm-5.2" does not support reasoning effort configuration (requested: "high").
```

it means the model's API does not expose controllable reasoning effort levels. Models from the **GLM** (Zhipu AI), **Kimi K2.x** (Moonshot AI), **MiMo** (Xiaomi), **Qwen3.x** (Alibaba), and **MiniMax** families do not support reasoning effort. OpenAI GPT-5.x-class models (for example `gpt-5.6-luna` on OpenCode Go) **do** support it, including the `max` level. See the Available Models table above for per-model notes.

When using these models, omit `--reasoning-effort` entirely. The model will use its built-in default reasoning behavior.

The profile system tracks this per model. Profiles set `"reasoningEffortSupported": false` for models that don't support it. The `run` command warns if you try to pass `--reasoning-effort` to an incompatible profile.

OpenAI-specific note:
- GPT-5 class models may perform best with `COPILOT_PROVIDER_WIRE_API=responses`.
- On OpenCode Go, GPT-5.6 Luna works on **both** `completions` and `responses` (probe 2026-08-03, re-verified 2026-08-05) — the earlier "Responses-API only" constraint was falsified. GPT-5.6-class models also support the full `--reasoning-effort` range including `max`, unlike the GLM/Kimi/MiMo/Qwen/MiniMax families listed above.
- **Wire-format caveat (2026-08-05 curl probes)**: on the `responses` wire, the reasoning effort must be nested as `reasoning.effort` (what Copilot CLI / VS Code send); a top-level `reasoning_effort` field is rejected with 400. `max_prompt_tokens` is likewise rejected on the `responses` wire — but the CLI does not send it there, so the stored profile (`wireApi: responses` + `maxPromptTokens: 200000`) works end-to-end (verified via real CLI run, exit 0, `model.call_start` = `gpt-5.6-luna`). The `completions` wire accepts all of these fields without caveats.

Version note:
- Do not assume a `COPILOT_*` environment variable exists for reasoning effort unless it appears in `copilot help environment` for the installed CLI version.

## Examples

### Local Ollama

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'http://localhost:11434'
$env:COPILOT_MODEL = 'llama3.2'
copilot
```

### OpenAI

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.openai.com/v1'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENAI_API_KEY
$env:COPILOT_MODEL = 'gpt-4o'
copilot
```

### Azure OpenAI

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT'
$env:COPILOT_PROVIDER_TYPE = 'azure'
$env:COPILOT_PROVIDER_API_KEY = $env:AZURE_OPENAI_API_KEY
$env:COPILOT_MODEL = 'YOUR-DEPLOYMENT'
copilot
```

### Anthropic

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.anthropic.com'
$env:COPILOT_PROVIDER_TYPE = 'anthropic'
$env:COPILOT_PROVIDER_API_KEY = $env:ANTHROPIC_API_KEY
$env:COPILOT_MODEL = 'claude-opus-4-5'
copilot
```

### Kimi AI / Moonshot Open Platform

The [Kimi AI Platform](https://platform.kimi.ai/docs/overview) (backed by Moonshot AI) provides OpenAI-compatible API access to the Kimi model family. All models support tool calling, streaming, and thinking mode.

> ⚠️ **Known limitation:** The `kimi-k2.7-code` model only accepts `top_p=0.95`. When used directly with Copilot CLI, the default `top_p` is fine. But in VS Code BYOK, the extension always sends `top_p=1.0`, causing a 400 error. See the Moonshot proxy section below for the workaround.

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.moonshot.ai/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:MOONSHOT_API_KEY
$env:COPILOT_MODEL = 'kimi-k2.6'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 240000
copilot
```

Available regions:
- Global: `https://api.moonshot.ai/v1`
- China: `https://api.moonshot.cn/v1`

Available models:

| Model | Model ID | Context | Thinking | Input Price | Output Price | Notes |
|-------|----------|---------|----------|-------------|--------------|-------|
| Kimi K2.7 Code | `kimi-k2.7-code` | 262,144 | Always on | $0.95 / MTok | $4.00 / MTok | Coding-optimized; cannot disable thinking |
| Kimi K2.6 | `kimi-k2.6` | 262,144 | Optional | $0.95 / MTok | $4.00 / MTok | Latest flagship; text, image, video |
| Kimi K2.5 | `kimi-k2.5` | 262,144 | Optional | $0.60 / MTok | $3.00 / MTok | Cost-effective; text, image, video |

> All models support automatic context caching (cache hit prices: K2.7 $0.19, K2.6 $0.16, K2.5 $0.10 per MTok).

Store your API key persistently:

```powershell
[Environment]::SetEnvironmentVariable("MOONSHOT_API_KEY", "<your-api-key>", "User")
```

### Moonshot proxy (top_p workaround)

For Kimi K2.7 Code in VS Code BYOK, use a local proxy since VS Code always sends `top_p=1.0`. Scripts are in the `copilot-byok` skill's `scripts/` folder.

| File | Location |
|------|----------|
| Proxy server | `skills/copilot-byok/scripts/proxy.js` (workspace) / `~/.copilot/skills/copilot-byok/scripts/proxy.js` (published) |
| Start script | `skills/copilot-byok/scripts/start-proxy.ps1` |
| Setup script | `skills/copilot-byok/scripts/setup-dns.ps1` (run once as admin) |
| Runtime certs | `~/.copilot/moonshot-proxy/` |
| Health check | `curl -s https://moonshot.local/health` |

Add `"proxyPort": 443` to the profile in `byok-profiles.json` to auto-start the proxy on `run`:

```json
"kimi-ai-k27-code": {
  "baseUrl": "https://api.moonshot.ai/v1",
  "model": "kimi-k2.7-code",
  "apiKey": "${MOONSHOT_API_KEY}",
  "proxyPort": 443
}
```

When `proxyPort` is set, `run` auto-starts `start-proxy.ps1` (elevated) and overrides `baseUrl` to `https://moonshot.local/v1`.

### Moonshot Open Platform (legacy)

Older Moonshot models (`kimi-k2`, `moonshot-v1-*`) are deprecated. Use the Kimi AI Platform models above instead.

## OpenCode Go

OpenCode Go is a subscription-based provider offering reliable access to popular open coding models via a single shared base URL. The [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints) list the models by endpoint family: `chat/completions` (DeepSeek, GLM, Kimi, MiMo, Grok, Hy3), `responses` (GPT-5.6 Luna), and `messages` (MiniMax, Qwen). A 2026-08-03 probe confirmed the OpenAI-compatible paths work for the models tested; an early "401 on `/v1/messages`" observation used `Authorization: Bearer` — the Anthropic Messages API requires `x-api-key` (+ `anthropic-version`) headers, so that 401 was an auth-header artifact, not evidence the endpoint is unsupported. Use the documented endpoint per family.

### Prerequisites

1. Subscribe to OpenCode Go at **[OpenCode Zen](https://opencode.ai/auth)** ($5 first month, then $10/month).
2. Generate an API key from the console.
3. Store the key as an environment variable at **User scope**: `OPENCODE_API_KEY_HOME` for personal usage, `OPENCODE_API_KEY_WORK` for work usage:

```powershell
[Environment]::SetEnvironmentVariable("OPENCODE_API_KEY_HOME", "<your-opencode-api-key>", "User")
[Environment]::SetEnvironmentVariable("OPENCODE_API_KEY_WORK", "<your-work-opencode-api-key>", "User")
```

### Base URL

```
https://opencode.ai/zen/go/v1
```

This single base URL serves every model. Copilot CLI appends the correct path based on `COPILOT_PROVIDER_TYPE` / `COPILOT_PROVIDER_WIRE_API`.

**Endpoint per family (per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints)):**
- `COPILOT_PROVIDER_TYPE=openai` + wire API `completions` (default) → `https://opencode.ai/zen/go/v1/chat/completions` — DeepSeek, GLM, Kimi, MiMo (also verified working for the models probed 2026-08-03)
- `COPILOT_PROVIDER_TYPE=openai` + wire API `responses` → `https://opencode.ai/zen/go/v1/responses` — GPT-5.6 Luna
- `COPILOT_PROVIDER_TYPE=anthropic` → `https://opencode.ai/zen/go/v1/messages` — MiniMax (M3/M2.7/M2.5), Qwen (3.8 Max/3.7 Max/3.7 Plus/3.6 Plus). Note: the Messages API authenticates with `x-api-key` (not `Authorization: Bearer`); an early 2026-08-03 Bearer probe returned 401, which was an auth-header artifact, not an unsupported endpoint.

**CRITICAL: `COPILOT_MODEL` must use the bare model ID (e.g., `deepseek-v4-flash`), never the `opencode-go/` prefix.** The `opencode-go/<model-id>` format is used **only** in OpenCode TUI config (`opencode.json`) — not in Copilot CLI's `COPILOT_MODEL`. The prefix in profile names like `opencode-go-deepseek-v4-flash` is just a naming convention for the profile key, not the model value.

### Model naming convention

Use the bare model ID for `COPILOT_MODEL` (e.g., `deepseek-v4-flash`). The `opencode-go/<model-id>` prefix is used only in OpenCode TUI config — **never** in `COPILOT_MODEL`. Profile names like `opencode-go-deepseek-v4-flash` are just naming keys, not model values.

### Available Models

| Model | Bare Model ID (`COPILOT_MODEL`) | Provider Type | Wire Format | Reasoning Effort |
|-------|-------------------------------|---------------|-------------|-----------------|
| GPT-5.6 Luna | `gpt-5.6-luna` | `openai` | `completions` or `responses` | Supported (full range, incl. `max`) |
| DeepSeek V4 Flash | `deepseek-v4-flash` | `openai` | `completions` | Supported (`low`, `medium`, `high`) |
| DeepSeek V4 Pro | `deepseek-v4-pro` | `openai` | `completions` | Supported (`low`, `medium`, `high`) |
| Kimi K2.7 Code | `kimi-k2.7-code` | `openai` | `completions` | Not supported (thinking always-on) |
| Kimi K2.6 | `kimi-k2.6` | `openai` | `completions` | Not supported (implicit thinking) |
| Kimi K2.5 | `kimi-k2.5` | `openai` | `completions` | Not supported (implicit thinking) |
| GLM-5.2 | `glm-5.2` | `openai` | `completions` | Not supported |
| GLM-5.1 | `glm-5.1` | `openai` | `completions` | Not supported |
| GLM-5 | `glm-5` | `openai` | `completions` | Not supported |
| MiMo-V2.5 (Xiaomi, 1M context) | `mimo-v2.5` | `openai` | `completions` | Not supported |
| MiMo-V2.5-Pro (Xiaomi, 1M context) | `mimo-v2.5-pro` | `openai` | `completions` | Not supported |
| Qwen3.7 Plus | `qwen3.7-plus` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Qwen3.7 Max | `qwen3.7-max` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Qwen3.6 Plus | `qwen3.6-plus` | `anthropic` | `messages` | Not supported (implicit thinking) |
| MiniMax M3 | `minimax-m3` | `anthropic` | `messages` | Not supported (implicit thinking) |
| MiniMax M2.7 | `minimax-m2.7` | `anthropic` | `messages` | Not supported (implicit thinking) |

> **Endpoint note (2026-08-05)**: per the [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints), Qwen3.x and MiniMax are listed at `/v1/messages` with `@ai-sdk/anthropic` (provider type `anthropic`, wire `messages`). A 2026-08-03 probe found these models also respond on `openai` / `chat/completions` (gateway tolerates both), but the documented path is `messages`. An early "401 on `/v1/messages`" observation used `Authorization: Bearer` — the Anthropic Messages API requires `x-api-key`, so that 401 was an auth-header artifact.

> The model list may change over time. Fetch the current list at any time:
> ```
> curl https://opencode.ai/zen/go/v1/models
> ```

### Usage limits

OpenCode Go imposes dollar-value usage limits tracked in the Zen console:
- **5 hour limit** — $12 of usage
- **Weekly limit** — $30 of usage
- **Monthly limit** — $60 of usage

If you also have OpenCode Zen credits, enable **Use balance** in the console to fall back to your balance after limits are reached.

Some models consume usage at a higher rate — notably **GPT-5.6 Luna** (~2,050 / 5,100 / 10,250 requests per 5-hour / week / month based on a typical 1,000 input + 50,000 cached + 220 output token request). Cheaper models like DeepSeek V4 Flash and MiMo-V2.5 allow far more requests within the same dollar budget.

### Examples

#### DeepSeek V4 Flash (OpenAI-compatible, cheapest)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'deepseek-v4-flash'
copilot
```

#### Qwen3.7 Plus (OpenAI-compatible per 2026-08-03 probe)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'qwen3.7-plus'
copilot
```

#### Kimi K2.7 Code (OpenAI-compatible)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'kimi-k2.7-code'
copilot
```

### GPT-5.6 Luna (Responses API — both wire formats verified)

GPT-5.6 Luna is OpenCode Go's cost-efficient GPT-5.6 entry point. Probes 2026-08-03 + 2026-08-05: it responds through **both** the OpenAI Responses API (`/v1/responses`) and `chat/completions` (`/v1/chat/completions`). `COPILOT_PROVIDER_WIRE_API=responses` remains the recommended configuration for GPT-5-class models, but it is no longer mandatory on OpenCode Go. Re-verified 2026-08-05 (CLI 1.0.78) with the real CLI against the stored profile (`responses` wire + `maxPromptTokens: 200000` + `--reasoning-effort high`): exit 0, `model.call_start` = `gpt-5.6-luna`, clean completion.

| Property | Value | Source |
|----------|-------|--------|
| Endpoint | `https://opencode.ai/zen/go/v1/responses` | [OpenCode Go docs](https://opencode.ai/docs/go/) |
| Wire API | `responses` | OpenCode Go docs |
| Theoretical context | 1,050,000 tokens | [models.dev](https://models.dev/models/openai/gpt-5.6-luna/) |
| Theoretical max output | 128,000 tokens | models.dev |
| Capabilities | tool calling, reasoning (incl. `max`), structured output; text / image / PDF input | models.dev |
| Gateway price tiers | ≤ 272K tokens: $0.20 / $1.20 per MTok → > 272K tokens: $0.40 / $1.80 (2x) | [OpenCode Go docs](https://opencode.ai/docs/go/) |
| Go usage | Lower multiplier — ~2,050 / 5,100 / 10,250 requests per 5-hour / week / month (typical request: 1,000 input + 50,000 cached + 220 output tokens) | OpenCode Go docs |

**Wire-format nuance (2026-08-05 curl matrix).** Raw-API probes of `gpt-5.6-luna`:

| Request | `chat/completions` | `responses` |
|---------|--------------------|------------|
| bare (or `max_output_tokens` only) | 200 ✅ | 200 ✅ |
| + `reasoning_effort` (top-level) | 200 ✅ (`high`/`max`) | **400 ❌** (top-level field is wrong placement) |
| + nested `reasoning.effort` | — | 200 ✅ (`high`/`low`) |
| + `max_prompt_tokens` | 200 ✅ | **400 ❌** |

Copilot CLI sends the nested `reasoning.effort` form on the `responses` wire and does not send `max_prompt_tokens` there, so the stored `responses` profile works end-to-end. Hand-rolled callers of `/v1/responses` must use the nested form and omit `max_prompt_tokens`; `chat/completions` accepts all fields without caveats.

**Grounded token overrides.** OpenCode Go prices GPT-5.6 Luna in two per-request tiers split at **272K tokens**. Staying under that boundary avoids both the 2x price and gateway compaction failures — the same gateway-limit discovery process used for DeepSeek V4 Flash (whose empirically validated 325K prompt cap is far below its 1M theoretical context) applies here:

```powershell
# Conservative values: 272K tier − 64K output budget − ~8K safety margin = 200K prompt cap
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 200000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
```

`maxOutputTokens = 64000` matches the other OpenCode Go OpenAI profiles and stays well under the 128K theoretical output limit, leaving headroom for reasoning tokens. If you need to push past 200K prompt tokens, verify the true gateway ceiling with the compaction test from the skill before raising the cap.

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_WIRE_API = 'responses'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'gpt-5.6-luna'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 200000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
copilot --reasoning-effort high
```

Profile entry (stored in `~/.copilot/byok-profiles.json`, account-grouped so `--account` / `activeAccount` resolve the key):

```json
"opencode-go-gpt-5.6-luna": {
  "apiKey": "${OPENCODE_API_KEY_WORK}",
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "wireApi": "responses",
  "offline": false,
  "maxPromptTokens": 200000,
  "model": "gpt-5.6-luna",
  "accountGroup": "opencode",
  "maxOutputTokens": 64000
}
```

### Profile-based setup

Use the profile manager script with preset **6 (OpenCode Go)**:

```powershell
.\scripts\byok-profile.ps1 add
```

Then run:

```powershell
.\scripts\byok-profile.ps1 run my-opencode-go-profile
```

## Multiple Accounts for the Same Provider

When you hold multiple subscriptions for one provider (for example, **two OpenCode Zen accounts** with separate API keys), register them in the config and switch per session without editing profiles.

### Config shape

`~/.copilot/byok-profiles.json`:

```json
{
  "accounts": {
    "opencode-home": { "keyEnv": "OPENCODE_API_KEY_HOME", "label": "OpenCode Zen (Home)" },
    "opencode-work": { "keyEnv": "OPENCODE_API_KEY_WORK", "label": "OpenCode Zen (Work)" }
  },
  "activeAccount": "opencode-home",
  "profiles": {
    "opencode-go-deepseek-v4-flash": {
      "baseUrl": "https://opencode.ai/zen/go/v1",
      "model": "deepseek-v4-flash",
      "type": "openai",
      "apiKey": "${OPENCODE_API_KEY_HOME}",
      "accountGroup": "opencode"
    }
  }
}
```

- `accounts.<name>.keyEnv` is the **name** of an environment variable holding that account's key. Raw keys are never stored in JSON.
- `activeAccount` selects the default account.
- `accountGroup` on a profile opts it into account resolution. Profiles without it are never affected. The `add` wizard (OpenCode Go preset) sets `accountGroup` automatically.

### Commands

| Command | Purpose |
|---------|---------|
| `byok-profile.ps1 accounts` | List registered accounts; mark the active one with `[active]`. |
| `byok-profile.ps1 use <account>` | Persist the default account. Errors on unknown names. |
| `byok-profile.ps1 run <profile> --account <account>` | Override the account for one session (both `--account <name>` and `--account=<name>` work). |
| `byok-profile.ps1 set-env <profile> --account <account>` | Apply the account override to the current shell. |

### Resolution order

`--account` flag → profile-level `account` pin → config-level `activeAccount` → `accounts[<name>].keyEnv`. When nothing resolves (no account selected, unknown account, or missing `keyEnv`), the profile falls back to its legacy `apiKey` placeholder and emits a warning.

### Sub-sessions

`Invoke-CopilotCliSubSession.ps1` supports the same lookup via `-ByokAccount <account>` (takes precedence over the profile pin and `activeAccount`). The resolved account is returned in the `ByokAccount` field of the result object.

## Offline Mode Notes

Offline mode prevents Copilot CLI from contacting GitHub's servers. It only guarantees full network isolation when the provider endpoint is also local or on-premises.
