# OpenCode Go — Copilot CLI

Configuring the OpenCode Go provider for **GitHub Copilot CLI**. For VS Code Chat, see [`vs-code.md`](vs-code.md). Provider-independent env-var semantics: [`../shared/environment-variables.md`](../../shared/environment-variables.md).

## Prerequisites

1. Subscribe to OpenCode Go at **[OpenCode Zen](https://opencode.ai/auth)** ($5 first month, then $10/month).
2. Generate an API key from the console.
3. Store the key as an environment variable at **User scope**: `OPENCODE_API_KEY_HOME` for personal usage, `OPENCODE_API_KEY_WORK` for work usage (see [`../shared/api-key-storage.md`](../../shared/api-key-storage.md)):

```powershell
[Environment]::SetEnvironmentVariable("OPENCODE_API_KEY_HOME", "<your-opencode-api-key>", "User")
[Environment]::SetEnvironmentVariable("OPENCODE_API_KEY_WORK", "<your-work-opencode-api-key>", "User")
```

## Base URL

```
https://opencode.ai/zen/go/v1
```

This single base URL serves every model. Copilot CLI appends the correct path based on `COPILOT_PROVIDER_TYPE` / `COPILOT_PROVIDER_WIRE_API`.

**Endpoint per family (per [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints)):**
- `COPILOT_PROVIDER_TYPE=openai` + wire API `completions` (default) → `https://opencode.ai/zen/go/v1/chat/completions` — DeepSeek, GLM, Kimi, MiMo (also verified working for the models probed 2026-08-03)
- `COPILOT_PROVIDER_TYPE=openai` + wire API `responses` → `https://opencode.ai/zen/go/v1/responses` — GPT-5.6 Luna
- `COPILOT_PROVIDER_TYPE=anthropic` → `https://opencode.ai/zen/go/v1/messages` — MiniMax (M3/M2.7/M2.5), Qwen (3.8 Flash/3.8 Max/3.7 Max/3.7 Plus/3.6 Plus). Note: the Messages API authenticates with `x-api-key` (not `Authorization: Bearer`); an early 2026-08-03 Bearer probe returned 401, which was an auth-header artifact, not an unsupported endpoint.

**CRITICAL: `COPILOT_MODEL` must use the bare model ID (e.g., `deepseek-v4-flash`), never the `opencode-go/` prefix.** The `opencode-go/<model-id>` format is used **only** in OpenCode TUI config (`opencode.json`) — not in Copilot CLI's `COPILOT_MODEL`. The prefix in profile names like `opencode-go-deepseek-v4-flash` is just a naming convention for the profile key, not the model value.

## Model naming convention

Use the bare model ID for `COPILOT_MODEL` (e.g., `deepseek-v4-flash`). The `opencode-go/<model-id>` prefix is used only in OpenCode TUI config — **never** in `COPILOT_MODEL`. Profile names like `opencode-go-deepseek-v4-flash` are just naming keys, not model values.

## Available Models

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
| GLM-5.3-Flash (Zhipu AI, 1M context) | `glm-5.3-flash` | `openai` | `completions` | Not supported (thinking always-on, defaults to `max`) |
| MiMo-V2.5 (Xiaomi, 1M context) | `mimo-v2.5` | `openai` | `completions` | Not supported |
| MiMo-V2.5-Pro (Xiaomi, 1M context) | `mimo-v2.5-pro` | `openai` | `completions` | Not supported |
| Qwen3.7 Plus | `qwen3.7-plus` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Qwen3.7 Max | `qwen3.7-max` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Qwen3.6 Plus | `qwen3.6-plus` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Qwen3.8-Flash (Alibaba, 1M context) | `qwen3.8-flash` | `anthropic` | `messages` | Supported (`low`, `medium`, `high`, `xhigh`) — verify on gateway |
| MiniMax M3 | `minimax-m3` | `anthropic` | `messages` | Not supported (implicit thinking) |
| MiniMax M2.7 | `minimax-m2.7` | `anthropic` | `messages` | Not supported (implicit thinking) |
| Hy3 (Tencent, 256K context) | `hy3` | `openai` | `completions` | Supported (`high` only; `no_think` maps to `none`) |
| Muse Spark 1.2 Contributor (Meta, 1M context) | `muse-spark-1.2-contributor` | `openai` | `completions` | Supported (`minimal`, `low`, `medium`, `high`, `xhigh`) |
| Ox Alpha Free (free for limited time) | `ox-alpha-free` | `openai` | `completions` | Supported (full range, incl. `max`) |
| LongCat-2.0 (Meituan, 1M context) | `longcat-2.0` | `openai` | `completions` | Not supported |

> **MiMo-V2.5 token grounding (empirical 2026-08-19, revised 2026-08-29).** The OpenCode Go gateway enforces a hard ceiling of **1,048,576 tokens** (prompt + output combined) — confirmed by a 400 error at 1.05M tokens. The theoretical context window is 1M tokens, but **practical testing shows the effective prompt limit is ~325K tokens**, matching the same gateway-enforced cap observed on DeepSeek V4 models. Exceeding this causes upstream provider errors. Output is unconstrained by the API (tested up to 1M `max_tokens`). Conservative limits:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 325,000 | Safe under gateway-enforced effective cap; matches DeepSeek V4 behavior |
> | `maxOutputTokens` | 64,000 | Practical for coding tasks; well under combined ceiling |
> | Combined budget | 389,000 | Stays under effective gateway limit |

> **GLM-5.3-Flash token grounding (2026-08-26).** GLM-5.3-Flash is a 320B-A18B MoE model from Zhipu AI with 1M context, 131K max output, natively multimodal (text/image/video/PDF), MIT license. Released 2026-08-26. Same gateway-enforced ~325K effective prompt cap applies. Conservative limits:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 325,000 | Safe under gateway-enforced effective cap; matches DeepSeek V4/GLM behavior |
> | `maxOutputTokens` | 64,000 | Practical for coding tasks |
> | Combined budget | 389,000 | Stays under effective gateway limit |

> **LongCat-2.0 token grounding (2026-08-30).** LongCat-2.0 is a 1.6T-parameter MoE coding model from Meituan with 1M context, 262K max output, MIT license. Same gateway-enforced ~325K effective prompt cap applies. Conservative limits:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 325,000 | Safe under gateway-enforced effective cap |
> | `maxOutputTokens` | 64,000 | Practical for coding tasks |
> | Combined budget | 389,000 | Stays under effective gateway limit |

> **Qwen3.8-Flash token grounding (2026-08-31).** Qwen3.8-Flash is a 125B MoE model from Alibaba with 1M context (native 262K, YaRN-extended to 1M), 131K max output. No empirical prompt-limit test exists for this model on the OpenCode Go gateway. Theoretical 1M context cannot be used as `maxPromptTokens` without gateway validation. Safe default matches the ~325K effective cap observed for DeepSeek V4 and GLM families:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 325,000 | No gateway-specific test; conservative default matching DeepSeek V4/GLM cap |
> | `maxOutputTokens` | 65,536 | Per Qwen's own Codex integration config |
> | Combined budget | 390,536 | Stays under effective gateway limit |
>
> Increase `maxPromptTokens` only after empirical compaction testing on the OpenCode Go gateway.

> **Hy3 token grounding (2026-08-20).** Hy3 has a 256K context window with 64K max output tokens. Conservative token overrides:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 184,000 | 256K - 64K output - 8K safety buffer |
> | `maxOutputTokens` | 64,000 | Matches model's max output |
> | Combined budget | 248,000 | Stays under 256K context window |

> **Muse Spark 1.2 Contributor token grounding (2026-08-20).** Muse Spark 1.2 Contributor has a 1M context window with 131K max output tokens. The contributor tier is heavily discounted but Meta uses your data for training. Conservative token overrides:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 909,504 | 1,048,576 - 131,072 output - 8,000 safety buffer |
> | `maxOutputTokens` | 131,072 | Matches model's max output |
> | Combined budget | 1,040,576 | Stays under 1,048,576 context window |

> **Ox Alpha Free token grounding (empirical 2026-08-24).** Ox Alpha Free is a free reasoning model with a 1M context window and 131K max output tokens. The model supports tool calling, vision, streaming, and reasoning effort (full range). Conservative token overrides:
>
> | Parameter | Empirical value | Rationale |
> |-----------|----------------|-----------|
> | `maxPromptTokens` | 980,000 | 1,048,576 - 131,072 output - 37,504 safety buffer |
> | `maxOutputTokens` | 131,072 | Matches model's max output |
> | Combined budget | 1,111,072 | Exceeds context window; see note |
>
> **Note:** The combined budget exceeds the 1,048,576 context window. The OpenCode Go gateway may enforce a lower effective limit. Use these values as a starting point and reduce if you encounter 400 errors.

> **Endpoint note (2026-08-05)**: per the [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints), Qwen3.x and MiniMax are listed at `/v1/messages` with `@ai-sdk/anthropic` (provider type `anthropic`, wire `messages`). A 2026-08-03 probe found these models also respond on `openai` / `chat/completions` (gateway tolerates both), but the documented path is `messages`. An early "401 on `/v1/messages`" observation used `Authorization: Bearer` — the Anthropic Messages API requires `x-api-key`, so that 401 was an auth-header artifact.

> The model list may change over time. Fetch the current list at any time:
> ```
> curl https://opencode.ai/zen/go/v1/models
> ```

## Examples (manual env-var setup)

### DeepSeek V4 Flash (OpenAI-compatible, cheapest)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'deepseek-v4-flash'
copilot
```

### Qwen3.7 Plus (OpenAI-compatible per 2026-08-03 probe)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'qwen3.7-plus'
copilot
```

### Qwen3.8-Flash (Anthropic-compatible, 1M context, multimodal)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'anthropic'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'qwen3.8-flash'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 325000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 65536
copilot
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-qwen3.8-flash": {
  "type": "anthropic",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 325000,
  "model": "qwen3.8-flash",
  "accountGroup": "opencode",
  "maxOutputTokens": 65536
}
```

### MiMo-V2.5 (OpenAI-compatible, 1M context)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'mimo-v2.5'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 980000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
copilot
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-mimo-v25": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 980000,
  "model": "mimo-v2.5",
  "accountGroup": "opencode",
  "maxOutputTokens": 64000
}
```

### GLM-5.3-Flash (OpenAI-compatible, 1M context, multimodal)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'glm-5.3-flash'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 325000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
copilot
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-glm-5.3-flash": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 325000,
  "model": "glm-5.3-flash",
  "accountGroup": "opencode",
  "maxOutputTokens": 64000
}
```

### LongCat-2.0 (OpenAI-compatible, 1M context, coding model)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'longcat-2.0'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 325000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
copilot
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-longcat-2.0": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 325000,
  "model": "longcat-2.0",
  "accountGroup": "opencode",
  "maxOutputTokens": 64000
}
```

### Kimi K2.7 Code (OpenAI-compatible)

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

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-gpt-5.6-luna": {
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

### Hy3 (Tencent, 256K context)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'hy3'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 184000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 64000
copilot --reasoning-effort high
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-hy3": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 184000,
  "model": "hy3",
  "accountGroup": "opencode",
  "maxOutputTokens": 64000
}
```

### Muse Spark 1.2 Contributor (Meta, 1M context, discounted tier)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'muse-spark-1.2-contributor'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 909504
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 131072
copilot --reasoning-effort medium
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-muse-spark-1.2-contributor": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 909504,
  "model": "muse-spark-1.2-contributor",
  "accountGroup": "opencode",
  "maxOutputTokens": 131072
}
```

### Ox Alpha Free (free for limited time)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://opencode.ai/zen/go/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENCODE_API_KEY_HOME
$env:COPILOT_MODEL = 'ox-alpha-free'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 980000
$env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = 131072
copilot --reasoning-effort high
```

Profile entry (account-grouped — `apiKey` is optional since account resolution overrides it):

```json
"opencode-go-ox-alpha-free": {
  "type": "openai",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "offline": false,
  "maxPromptTokens": 980000,
  "model": "ox-alpha-free",
  "accountGroup": "opencode",
  "maxOutputTokens": 131072
}
```

## Profile-based setup

Use the profile manager script with preset **6 (OpenCode Go)**:

```powershell
.\scripts\byok-profile.ps1 add
```

Then run:

```powershell
.\scripts\byok-profile.ps1 run my-opencode-go-profile
```

For multiple OpenCode Zen accounts (Home / Work), see [`../shared/copilot-cli-accounts.md`](../../shared/copilot-cli-accounts.md).