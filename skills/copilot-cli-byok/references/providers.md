# BYOK Provider Reference

Quick-reference for configuring Copilot CLI BYOK providers.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `COPILOT_PROVIDER_BASE_URL` | Yes | Base URL of the provider's API endpoint. |
| `COPILOT_MODEL` | Yes | Model identifier. Can also be set via `--model` flag. |
| `COPILOT_PROVIDER_TYPE` | No | Provider type: `openai`, `azure`, or `anthropic`. Defaults to `openai`. |
| `COPILOT_PROVIDER_API_KEY` | No | API key. Omit for unauthenticated providers (e.g., local Ollama). |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | No | Override the max prompt token limit Copilot CLI uses for the model. Useful when the model is not in Copilot's built-in catalog. |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | No | Override the max output token limit Copilot CLI uses for the model. |
| `COPILOT_OFFLINE` | No | Set to `true` to prevent Copilot CLI from contacting GitHub's servers. |

## Supported Providers

| Provider Type | Compatible Services |
|---------------|---------------------|
| `openai` | OpenAI, Ollama, vLLM, Foundry Local, and any OpenAI Chat Completions API-compatible endpoint (default) |
| `azure` | Azure OpenAI Service |
| `anthropic` | Anthropic (Claude models) |

## Model Requirements

The chosen model must support:
- **Tool calling** (function calling)
- **Streaming**

For best results, use a model with a context window of at least **128k tokens**. If your model supports a larger context window and is not in Copilot CLI's built-in catalog, set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to its actual limit so Copilot CLI doesn't fall back to a smaller default.

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

### Kimi Code (kimi.com/code subscription)

If you have a Kimi Code subscription and generated an API key from https://www.kimi.com/code/console, use the Kimi Code OpenAI-compatible endpoint:

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.kimi.com/coding/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:KIMICODE_API_KEY
$env:COPILOT_MODEL = 'kimi-for-coding'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 262144
copilot
```

> **Important:** Kimi Code's backend currently enforces an agent whitelist. It returns `403 Forbidden` for clients other than Kimi CLI, Claude Code, Roo Code, and Kilo Code. GitHub Copilot CLI is **not yet whitelisted**, so this configuration is effectively a placeholder for now.

### Moonshot Open Platform

For the general Moonshot API (not Kimi Code), use the Moonshot OpenAI-compatible endpoint with `provider type = openai`:

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.moonshot.cn/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:MOONSHOT_API_KEY
$env:COPILOT_MODEL = 'kimi-k2.5'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 256000
copilot
```

Available regions:
- China: `https://api.moonshot.cn/v1`
- Global: `https://api.moonshot.ai/v1`

Common Moonshot models: `kimi-k2.5`, `kimi-k2`, `moonshot-v1-8k`, `moonshot-v1-32k`, `moonshot-v1-128k`.

Models from Moonshot may support up to **256,000 tokens** (or 262,144 in some coding-tool configs). Explicitly set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to avoid Copilot CLI defaulting to a smaller limit.

## Offline Mode Notes

Offline mode prevents Copilot CLI from contacting GitHub's servers. It only guarantees full network isolation when the provider endpoint is also local or on-premises.
