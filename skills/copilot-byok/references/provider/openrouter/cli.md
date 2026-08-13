# OpenRouter — Copilot CLI

Configuring the OpenRouter provider for **GitHub Copilot CLI**. For VS Code Chat, see [`vs-code.md`](vs-code.md). Provider-independent env-var semantics: [`../shared/environment-variables.md`](../../shared/environment-variables.md).

OpenRouter is an OpenAI-compatible endpoint that provides access to various models.

## Environment Variables

> Full variable semantics: [`shared/environment-variables.md`](../../shared/environment-variables.md).

| Variable | Required | Description |
|----------|----------|-------------|
| `COPILOT_PROVIDER_BASE_URL` | Yes | Set to `https://openrouter.ai/api/v1` |
| `COPILOT_PROVIDER_MODEL` | Yes | Model identifier from OpenRouter (e.g., `openai/gpt-4o`, `anthropic/claude-3.5-sonnet`, `deepseek/deepseek-v4-pro`) |
| `COPILOT_PROVIDER_TYPE` | No | Defaults to `openai` (OpenRouter uses OpenAI-compatible API) |
| `COPILOT_PROVIDER_API_KEY` | Yes | Your OpenRouter API key |
| `COPILOT_PROVIDER_WIRE_API` | No | Use `completions` (default) or `responses` if the model supports it. Check model documentation. |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | No | Override if needed; OpenRouter models may have different context limits. |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | No | Override if needed. |
| `COPILOT_OFFLINE` | No | Set to `true` to prevent Copilot CLI from contacting GitHub's servers (not typical for OpenRouter). |

## Discount Routing for DeepSeek Models

OpenRouter supports routing-mode suffixes that work universally across **all** models — DeepSeek V4 Pro, DeepSeek V4 Flash 0423, and DeepSeek V4 Flash 0731:

- **`:floor`** — Equivalent to `provider.sort: "price"`. Routes to the cheapest active provider. Recommended for lowest cost. Note: floor-priced providers often use more aggressive quantization, which may marginally affect output quality; for coding-agent use where reliability matters, consider omitting the suffix (balanced default).
- **`:nitro`** — Equivalent to `provider.sort: "throughput"`. Routes to the fastest provider (highest tokens/sec) at that moment. Use when latency matters more than cost.
- **No suffix** — Default load-balanced routing: balances availability, throughput, and pricing across eligible providers.

Works for any model slug:
- `deepseek/deepseek-v4-pro:floor` / `deepseek/deepseek-v4-pro:nitro`
- `deepseek/deepseek-v4-flash:floor` / `deepseek/deepseek-v4-flash:nitro`
- `deepseek/deepseek-v4-flash-0731:floor` / `deepseek/deepseek-v4-flash-0731:nitro`

> **Source:** [OpenRouter Blog — Introducing Nitro and Floor Price Shortcuts](https://openrouter.ai/blog/announcements/introducing-nitro-and-floor-price-shortcuts/) (2025-02-12); suffixes are confirmed universal on all model pages as of 2026-08-09.

## Usage Example

### CLI Profile

Add a profile using the byok-profile script:

```powershell
.\scripts\byok-profile.ps1 add
```
Then follow the prompts, or manually create a profile in `~/.copilot/byok-profiles.json`:

```json
{
  "openrouter": {
    "baseUrl": "https://openrouter.ai/api/v1",
    "model": "deepseek/deepseek-v4-pro:floor",
    "type": "openai",
    "apiKeyEnv": "OPENROUTER_API_KEY",
    "wireApi": "completions"
  }
}
```

Set the environment variable `OPENROUTER_API_KEY` to your OpenRouter key (see [`../shared/api-key-storage.md`](../../shared/api-key-storage.md)).

### Manual one-off environment setup

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://openrouter.ai/api/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENROUTER_API_KEY
$env:COPILOT_MODEL = 'deepseek/deepseek-v4-pro:floor'
copilot
```

## Empirical Audit (2026-08-09)

Findings from live inspection of OpenRouter model pages and API docs.

### DeepSeek V4 Pro (`deepseek/deepseek-v4-pro`)

| Property | OpenRouter Value | Source |
|----------|-----------------|--------|
| Context window | 1,048,576 tokens (1M) | [OpenRouter model page](https://openrouter.ai/deepseek/deepseek-v4-pro) |
| Max output (reported) | 65,536 tokens | OpenRouter Parameters table — `max_tokens` field |
| Theoretical max output | ~384,000 tokens | [DeepSeek AI Guide](https://deepseekai.guide/guides/deepseek-character-limits/) — hard output ceiling |
| Reasoning effort | `high`, `xhigh` (xhigh → max) | OpenRouter model page description |
| Wire API | `completions` (default); `responses` also listed | OpenRouter Endpoints section |
| Price (weighted avg) | $0.14 / $1.08 per MTok (in/out) | OpenRouter weighted avg (7d) |
| Cheapest provider | StreamLake at $0.03 / $0.22 per MTok | OpenRouter Providers table |
| Appears in VS Code docs? | Yes (as model `deepseek-v4-pro`) | DeepSeek API docs: Responses API *not yet* supported for Pro (ETA early Aug 2026) |

**Recommended maxInputTokens:** 200,000  
**Rationale:** 1,048,576 context − 64,000 output budget − 8,000 safety buffer = ~976K theoretical. However, OpenRouter routes across many upstream providers, each with differing per-request limits. The conservative 200K figure aligns with real-world coding-agent workloads and reduces risk of provider-level compaction failures. If you routinely hit context-limit errors, reduce by 5–10%.

**Recommended maxOutputTokens:** 64,000  
**Rationale:** OpenRouter documents 65,536 as the per-request `max_tokens` ceiling for this model. Rounding down to 64,000 for a clean value stays safely under the documented limit while leaving headroom for reasoning tokens.

### DeepSeek V4 Flash 0731 (`deepseek/deepseek-v4-flash-0731`)

| Property | OpenRouter Value | Source |
|----------|-----------------|--------|
| Context window | 1,048,576 tokens (1M) | [OpenRouter model page](https://openrouter.ai/deepseek/deepseek-v4-flash-0731) |
| Max output (reported) | 131,072 tokens | OpenRouter model page description |
| Theoretical max output | ~384,000 tokens | [DeepSeek AI Guide](https://deepseekai.guide/guides/deepseek-character-limits/) — hard output ceiling |
| Reasoning effort | `high`, `xhigh` (xhigh → max) | OpenRouter model page description |
| Wire API | `completions` (default); `responses` also listed | OpenRouter Endpoints section |
| Price (weighted avg) | $0.04 / $0.26 per MTok (in/out) | OpenRouter weighted avg (7d) |
| Cheapest provider | Baidu Qianfan at $0.03 / $0.18 per MTok | OpenRouter Providers table |
| DeepSeek native API | v4-flash supports `low`/`medium`/`high` effort | [DeepSeek API docs](https://api-docs.deepseek.com/api/create-chat-completion/) |

**Recommended maxInputTokens:** 200,000  
**Rationale:** Same conservative approach as Pro. The 0731 revision has a higher documented output ceiling (131K) but provider-level routing still faces the same variable per-provider limits. 200K is a safe initial value for Copilot CLI/VS Code BYOK.

**Recommended maxOutputTokens:** 64,000  
**Rationale:** OpenRouter documents 131,072 for the 0731 revision (vs 65,536 for the original V4 Flash 0423). However, for Copilot CLI use with reasoning tokens consuming part of the output budget, 64,000 is a conservative choice. Bump to 96,000 or 128,000 if your workload frequently truncates at the output ceiling and you have confirmed your typical upstream provider supports it.

### DeepSeek V4 Flash 0423 (`deepseek/deepseek-v4-flash`, original)

- **maxOutputTokens:** 65,536 (per OpenRouter model page)
- Same recommended token values as 0731 above apply.

### Empirical Token-Cap Audit (2026-08-13)

Live probes via `POST https://openrouter.ai/api/v1/chat/completions` (Completions wire, `temperature=0`, `max_tokens=16`) against `:floor` routing and forced per-provider endpoints. The gateway enforces **no** `max_prompt_tokens` cap — the effective limit is the routed upstream provider's context window.

| Model route | Probed prompt tokens | Result | Routed provider (ctx) |
|-------------|---------------------|--------|------------------------|
| `deepseek-v4-flash-0731:floor` | 137K | OK | deepinfra (1M) |
| `deepseek-v4-flash-0731:floor` | 204K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731:floor` | 266K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731:floor` | 348K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731:floor` | 512K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731:floor` | 717K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731:floor` | 389K | OK | DeepInfra (1M) |
| `deepseek-v4-flash-0731` (default) | 154K | OK | Cloudflare (384K) |
| `deepseek-v4-flash-0731` (default) | 205K | OK | Inceptron (1M) |
| `deepseek-v4-flash-0731` (default) | 246K | OK | SiliconFlow (1M) |
| `deepseek-v4-flash-0731` forced `AkashML` | 138K | **ERR** 131072-token cap | akashml/fp8 (131,072) |
| `deepseek-v4-pro:floor` | 205K | OK | StreamLake (1M) |
| `deepseek-v4-pro:floor` | 307K | OK | StreamLake (1M) |
| `deepseek-v4-pro:floor` | 410K | OK | StreamLake (1M) |
| `deepseek-v4-pro:floor` | 256K | OK | StreamLake (1M) |
| `deepseek-v4-pro:floor` | 276K | OK | StreamLake (1M) |

**Findings**

1. **No gateway cap.** Both models handle several hundred K tokens with no provider-level `400` (contrast with the OpenCode Go ~300K gateway cap). Probed ceiling on the live floor route: **>717K (flash)** and **>410K (pro)**; both pull the 1M-context window when the prompt demands it.
2. **`:floor` self-selects capable providers.** OpenRouter only routes to providers whose context window satisfies the request (prompt + max_tokens). Observed floor providers all expose full 1M context (DeepInfra, StreamLake, DigitalOcean, Baidu). This is why large prompts always succeed.
3. **The binding constraint is the smallest floor pool member**, which varies by market conditions and is not reliably predictable:
   - **Flash 0731 pool** min: `akashml/fp8` at **131,072** (also Decart / OpenInference / Sail / CoreWeave at 262,144).
   - **Pro pool** min: `baseten/fp4` at **262,144** (also Together at 512,000).
   - Forcing AkashML above 131K returns: `This endpoint's maximum context length is 131072 tokens.`
4. **`maxOutputTokens` 64,000 stays safe** for both — every floor provider reports ≥131K max completion, leaving ample headroom.

**Conclusion / updated recommendation**

The previously documented `maxPromptTokens: 200,000` for both OpenRouter DeepSeek V4 profiles is **empirically validated and safe** — it succeeded on every route and provider tested. Given the ~1M real headroom and floor routing that self-selects capable providers, 200K is conservative; you could raise both to **300,000** for a comfortable margin above the smallest floor members (AkashML 131K / BaseTen 262K) with no behavior change on current routes. Keep 200K if you prefer the most conservative, cost-bounded profile. `maxOutputTokens` remains 64,000.

**Note:** today (2026-08-13) OpenRouter also lists a new GA release `deepseek/deepseek-v4-pro-0813` (`context_length: 1,048,576`, `max_completion_tokens: 384,000`, efforts `max|high|low`). The audited `deepseek-v4-pro` slug above remains valid.

### Reasoning Effort Notes

OpenRouter's model page for **both** V4 Pro and V4 Flash lists only `high` and `xhigh` (with `xhigh` mapping to max reasoning). However, the **DeepSeek native API docs** clarify:

- `deepseek-v4-flash` supports all three effort levels: `low`, `medium`, `high`.
- `deepseek-v4-pro` **temporarily** treats `low` as `high` and only supports `high` / `max` (alias `xhigh`); all levels expected to be supported in early August 2026.

When using OpenRouter as the gateway, it passes the reasoning effort parameter through to the upstream provider. If a provider honors the native DeepSeek effort levels, `low` and `medium` may work for Flash even though OpenRouter doesn't document them. If you get errors, fall back to `high` or omit `--reasoning-effort`.

### Routing Suffixes on OpenRouter

The `:floor` and `:nitro` suffixes are universal shortcuts documented by OpenRouter:
- **`:floor`** → `provider.sort: "price"` — cheapest provider, typically uses FP4/INT4 quantization
- **`:nitro`** → `provider.sort: "throughput"` — fastest provider (highest tokens/sec)
- **No suffix** → OpenRouter's default load-balanced routing (price × speed × availability)

> These are **not** separate model endpoints — they adjust the provider-sort order before routing. A `:floor` request to `deepseek/deepseek-v4-pro:floor` still hits the same model on whichever provider is cheapest at that moment.

## Notes

- OpenRouter supports a wide range of models from different providers.
- Be aware of rate limits and costs associated with each model.
- For models that support reasoning (e.g., OpenAI's o1 series), you may need to adjust `COPILOT_PROVIDER_WIRE_API` and use `--reasoning-effort` accordingly.
- To verify which provider processed your request and the exact cost/discount applied, check your OpenRouter Activity Dashboard.