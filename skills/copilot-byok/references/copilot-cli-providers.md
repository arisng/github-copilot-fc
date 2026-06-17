# BYOK Provider Reference

Quick-reference for configuring Copilot CLI BYOK providers.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `COPILOT_PROVIDER_BASE_URL` | Yes | Base URL of the provider's API endpoint. |
| `COPILOT_MODEL` | Yes | Model identifier. Can also be set via `--model` flag. |
| `COPILOT_PROVIDER_TYPE` | No | Provider type: `openai`, `azure`, or `anthropic`. Defaults to `openai`. |
| `COPILOT_PROVIDER_API_KEY` | No | API key. Omit for unauthenticated providers (e.g., local Ollama). |
| `COPILOT_PROVIDER_WIRE_API` | No | Provider wire format: `completions` (default) or `responses`. For GPT-5 class OpenAI models, prefer `responses`. |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | No | Override the max prompt token limit Copilot CLI uses for the model. Useful when the model is not in Copilot's built-in catalog. |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | No | Override the max output token limit Copilot CLI uses for the model. |
| `COPILOT_OFFLINE` | No | Set to `true` to prevent Copilot CLI from contacting GitHub's servers. |

## Supported Providers

| Provider Type | Compatible Services |
|---------------|---------------------|
| `openai` | OpenAI, Ollama, vLLM, Foundry Local, OpenCode Go (OpenAI-compatible models), and any OpenAI Chat Completions API-compatible endpoint (default) |
| `azure` | Azure OpenAI Service |
| `anthropic` | Anthropic (Claude models), OpenCode Go (Anthropic-compatible models) |

## Model Requirements

The chosen model must support:
- **Tool calling** (function calling)
- **Streaming**

For best results, use a model with a context window of at least **128k tokens**. If your model supports a larger context window and is not in Copilot CLI's built-in catalog, set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to its actual limit so Copilot CLI doesn't fall back to a smaller default.

## Reasoning Effort

Reasoning level is configured via Copilot CLI option `--reasoning-effort` (alias: `--effort`) per invocation.

Supported levels:
- `none`
- `low`
- `medium`
- `high`
- `xhigh`
- `max`

Example:

```powershell
copilot --reasoning-effort medium
```

If you run through BYOK profile script passthrough:

```powershell
.\scripts\byok-profile.ps1 run dprocess-openai-gpt-54 --reasoning-effort medium
```

OpenAI-specific note:
- GPT-5 class models may perform best with `COPILOT_PROVIDER_WIRE_API=responses`.

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

OpenCode Go is a subscription-based provider offering reliable access to popular open coding models via a single shared base URL. Models use one of two endpoint formats depending on the model family.

### Prerequisites

1. Subscribe to OpenCode Go at **[OpenCode Zen](https://opencode.ai/auth)** ($5 first month, then $10/month).
2. Generate an API key from the console.
3. Store the key as the environment variable `OPENCODE_API_KEY`:

```powershell
[Environment]::SetEnvironmentVariable("OPENCODE_API_KEY", "<your-opencode-api-key>", "User")
```

### Base URL

```
https://opencode.ai/zen/go/v1
```

This single base URL serves both OpenAI-compatible and Anthropic-compatible models. Copilot CLI automatically appends the correct path based on `COPILOT_PROVIDER_TYPE`.

**Critical base URL pattern:**
- `COPILOT_PROVIDER_TYPE=openai` → use `https://opencode.ai/zen/go/v1` (SDK appends `/chat/completions`)
- `COPILOT_PROVIDER_TYPE=anthropic` → use `https://opencode.ai/zen/go` (SDK appends `/v1/messages`)

The Anthropic-type base URL strips the `/v1` because the SDK already adds it.

**CRITICAL: `COPILOT_MODEL` must use the bare model ID (e.g., `deepseek-v4-flash`), never the `opencode-go/` prefix.** The `opencode-go/<model-id>` format is used **only** in OpenCode TUI config (`opencode.json`) — not in Copilot CLI's `COPILOT_MODEL`. The prefix in profile names like `opencode-go-deepseek-v4-flash` is just a naming convention for the profile key, not the model value.

### Model naming convention

Use the bare model ID for `COPILOT_MODEL` (e.g., `deepseek-v4-flash`). The `opencode-go/<model-id>` prefix is used only in OpenCode TUI config — **never** in `COPILOT_MODEL`. Profile names like `opencode-go-deepseek-v4-flash` are just naming keys, not model values.

### Available Models

### Available Models

| Model | Bare Model ID (`COPILOT_MODEL`) | Provider Type | Wire Format |
|-------|-------------------------------|---------------|-------------|
| DeepSeek V4 Flash | `deepseek-v4-flash` | `openai` | `completions` |
| DeepSeek V4 Pro | `deepseek-v4-pro` | `openai` | `completions` |
| Kimi K2.7 Code | `kimi-k2.7-code` | `openai` | `completions` |
| Kimi K2.6 | `kimi-k2.6` | `openai` | `completions` |
| GLM-5.1 | `glm-5.1` | `openai` | `completions` |
| GLM-5 | `glm-5` | `openai` | `completions` |
| MiMo-V2.5 (Xiaomi, 1M context) | `mimo-v2.5` | `openai` | `completions` |
| MiMo-V2.5-Pro (Xiaomi, 1M context) | `mimo-v2.5-pro` | `openai` | `completions` |
| Qwen3.7 Plus | `qwen3.7-plus` | `anthropic` | `completions` |
| Qwen3.7 Max | `qwen3.7-max` | `anthropic` | `completions` |
| Qwen3.6 Plus | `qwen3.6-plus` | `anthropic` | `completions` |
| MiniMax M3 | `minimax-m3` | `anthropic` | `completions` |
| MiniMax M2.7 | `minimax-m2.7` | `anthropic` | `completions` |

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

### Examples

#### DeepSeek V4 Flash (OpenAI-compatible, cheapest)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY
$env:COPILOT_MODEL = 'deepseek-v4-flash'
copilot
```

#### Qwen3.7 Plus (Anthropic-compatible — note: base URL without `/v1` because SDK appends it)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go'
$env:COPILOT_PROVIDER_TYPE = 'anthropic'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY
$env:COPILOT_MODEL = 'qwen3.7-plus'
copilot
```

#### Kimi K2.7 Code (OpenAI-compatible)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY
$env:COPILOT_MODEL = 'kimi-k2.7-code'
copilot
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

## Offline Mode Notes

Offline mode prevents Copilot CLI from contacting GitHub's servers. It only guarantees full network isolation when the provider endpoint is also local or on-premises.
