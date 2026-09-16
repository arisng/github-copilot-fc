# Command Code — Copilot CLI

Configuring the Command Code provider for **GitHub Copilot CLI**. For VS Code Chat, see [`vs-code.md`](vs-code.md). Provider-independent env-var semantics: [`../shared/environment-variables.md`](../../shared/environment-variables.md).

## Prerequisites

1. Subscribe to Command Code **GOAT plan** ($10/month) at [commandcode.ai](https://commandcode.ai). The Go plan ($1/month) does **not** include API access.
2. Generate an API key from the Command Code dashboard.
3. Store the key as an environment variable at **User scope**:

```powershell
[Environment]::SetEnvironmentVariable("COMMANDCODE_API_KEY", "<your-commandcode-api-key>", "User")
```

Restart your terminal after setting the variable.

## Base URL

```
https://api.commandcode.ai/provider/v1
```

This single base URL serves every model. Copilot CLI appends the correct path based on `COPILOT_PROVIDER_TYPE` / `COPILOT_PROVIDER_WIRE_API`.

**Endpoints:**
- `COPILOT_PROVIDER_TYPE=openai` + wire API `completions` (default) → `https://api.commandcode.ai/provider/v1/chat/completions`
- All models use OpenAI-compatible format.

## Model naming convention

Command Code uses `provider/model-name` format for model IDs (e.g., `deepseek/deepseek-v4-flash`). **This is different from OpenCode Go**, which uses bare model IDs. Use the full `provider/model-name` format in `COPILOT_MODEL`.

Profile names use `cc-goat-` prefix for easy identification (e.g., `cc-goat-deepseek-v4-flash`).

## Available Models

| Model | Model ID (`COPILOT_MODEL`) | Provider Type | Wire Format | Context | Reasoning Effort |
|-------|---------------------------|---------------|-------------|---------|-----------------|
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | `openai` | `completions` | 1M | Supported (`low`, `medium`, `high`) |
| DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` | `openai` | `completions` | 1M | Supported (`low`, `medium`, `high`) |
| MiMo V2.5 | `xiaomi/mimo-v2.5` | `openai` | `completions` | 1M | Not supported |
| MiMo V2.5 Pro | `xiaomi/mimo-v2.5-pro` | `openai` | `completions` | 1M | Not supported |
| Muse Spark 1.3 Contributor | `meta/muse-spark-1.3-contributor` | `openai` | `completions` | 1.05M | Supported (verify) |
| GPT-5.6 Luna | `openai/gpt-5.6-luna` | `openai` | `completions` | 1.05M | Supported (full range) |
| Ling 3.0 Flash Sante (free) | `inclusionai/ling-3.0-flash-sante:free` | `openai` | `completions` | 262K | Not supported |
| Laguna S 2.1 (free) | `poolside/laguna-s-2.1-free` | `openai` | `completions` | 256K | Not supported |
| LongCat 2.0 (free) | `meituan/longcat-2.0:free` | `openai` | `completions` | 1.05M | Not supported |

> Reasoning-effort support is inferred from the underlying model capabilities, not verified against Command Code's gateway. Probe with `--reasoning-effort none` before assuming support.

## Token overrides

Context windows are from official Command Code docs. `maxOutputTokens` = 32,768 (docs don't publish per-model max output).

| Model | Context Window | maxPromptTokens | maxOutputTokens |
|-------|---------------|-----------------|-----------------|
| DeepSeek V4.1 Flash | 1M | 1,000,000 | 32,768 |
| DeepSeek V4 Flash | 1M | 1,000,000 | 32,768 |
| MiMo V2.5 | 1M | 1,000,000 | 32,768 |
| MiMo V2.5 Pro | 1M | 1,000,000 | 32,768 |
| Muse Spark 1.3 Contributor | 1.05M | 1,050,000 | 32,768 |
| GPT-5.6 Luna | 1.05M | 1,050,000 | 32,768 |
| Ling 3.0 Flash Sante | 262K | 262,000 | 32,768 |
| Laguna S 2.1 | 256K | 256,000 | 32,768 |
| LongCat 2.0 | 1.05M | 1,050,000 | 32,768 |

> Unlike OpenCode Go, Command Code does not appear to enforce gateway-level token caps below the model's theoretical context window. If you encounter compaction failures, reduce `maxPromptTokens` by 5-10%.

## Pricing notes

- **DeepSeek V4.1/V4 Flash**: Peak pricing (01–04 & 06–10 UTC Mon–Fri): input $0.30/MTok, output $1.20/MTok. Off-peak: input $0.15/MTok, output $0.60/MTok.
- **MiMo V2.5/Pro**: 99% off deal active.
- **Free models**: Ling 3.0 Flash Sante (100 req/day), Laguna S 2.1, LongCat 2.0 (while it lasts).

## Examples (manual env-var setup)

### DeepSeek V4 Flash (cheapest paid model)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.commandcode.ai/provider/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:COMMANDCODE_API_KEY
$env:COPILOT_MODEL = 'deepseek/deepseek-v4-flash'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = '1000000'
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = '32768'
copilot
```

### LongCat 2.0 (free, large context)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.commandcode.ai/provider/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:COMMANDCODE_API_KEY
$env:COPILOT_MODEL = 'meituan/longcat-2.0:free'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = '1050000'
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = '32768'
copilot
```

## CLI profiles

Profiles use `cc-goat-` prefix. Add to `~/.copilot/byok-profiles.json`:

```json
{
  "cc-goat-deepseek-v4-flash": {
    "offline": false,
    "model": "deepseek/deepseek-v4-flash",
    "apiKey": "${COMMANDCODE_API_KEY}",
    "maxPromptTokens": 1000000,
    "type": "openai",
    "baseUrl": "https://api.commandcode.ai/provider/v1",
    "maxOutputTokens": 32768
  }
}
```

Run with:

```powershell
.\scripts\byok-profile.ps1 run cc-goat-deepseek-v4-flash
```

## Multiple accounts

Register Command Code accounts in the `accounts` section of `byok-profiles.json`:

```json
{
  "accounts": {
    "commandcode": { "keyEnv": "COMMANDCODE_API_KEY", "label": "Command Code GOAT" }
  }
}
```

See [`../../shared/copilot-cli-accounts.md`](../../shared/copilot-cli-accounts.md) for the full account-switching reference.
