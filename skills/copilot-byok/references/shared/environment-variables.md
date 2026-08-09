# Copilot CLI Environment Variables (BYOK)

The canonical env-var reference for Copilot CLI BYOK, shared by every provider. Per-provider values and examples live in the provider folders; this file documents the variables and the wire-format rules that apply to all of them.

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

## Supported Provider Types

| Provider Type | Compatible Services |
|---------------|---------------------|
| `openai` | OpenAI, Ollama, vLLM, Foundry Local, OpenCode Go (OpenAI-compatible models), and any OpenAI Chat Completions / Responses API-compatible endpoint (default) |
| `azure` | Azure OpenAI Service |
| `anthropic` | Anthropic (Claude models), OpenCode Go (Anthropic-compatible models — MiniMax, Qwen; see [OpenCode Go docs endpoints](https://opencode.ai/docs/go/#endpoints)) |

## Wire-format rules (apply to every provider)

On the `responses` wire:

- The reasoning effort must be **nested** as `reasoning.effort` (what Copilot CLI / VS Code send). A top-level `reasoning_effort` field is rejected with 400 (verified 2026-08-05 curl probes).
- `max_prompt_tokens` is rejected. The CLI does not send it on this wire, so profiles with the default settings work end-to-end.
- Hand-rolled callers of `/v1/responses` must use the nested form and omit `max_prompt_tokens`; `chat/completions` accepts all of these fields without caveats.

## Model Requirements

The chosen model must support:

- **Tool calling** (function calling)
- **Streaming**

For best results, use a model with a context window of at least **128k tokens**. If your model supports a larger context window and is not in Copilot CLI's built-in catalog, set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to its actual limit so Copilot CLI doesn't fall back to a smaller default.

## Calculate token overrides conservatively

When configuring `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` or `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS`:

1. Get the model's documented context window.
2. Pick a realistic max output budget for the workload.
3. Reserve a safety buffer for tool calls, system instructions, and multi-turn variance.
4. Compute:

`maxPromptTokens = contextWindow - plannedMaxOutput - safetyBuffer`

Prefer stable values over theoretical maximums. If the user reports context-limit failures, reduce prompt tokens by 5-10% and retry.

### Provider-enforced limits vs theoretical context windows

Some gateway providers (notably **OpenCode Go**) enforce per-request token limits **lower than the model's theoretical context window**. The native DeepSeek V4 Flash model supports 1M context, but OpenCode Go's gateway enforces an effective limit around ~300K for prompt tokens. Using the theoretical 1M to calculate maxPromptTokens (840K) will cause compaction failures with `400 Error from provider (Console Go): Upstream request failed`.

**Empirical approach**: Test compaction at increasing context-usage levels. When compaction fails, derive the provider's effective limit:

```
maxPromptTokens = successfulCompactionTokens / 0.78
```

For OpenCode Go's DeepSeek V4 models, the empirically validated safe values are:

- `maxPromptTokens`: 325,000
- `maxOutputTokens`: 64,000

This same limit discovery process applies to any provider whose gateway enforces stricter limits than the model's published context window.

## Reasoning effort

Reasoning level is configured via Copilot CLI option `--reasoning-effort` (alias: `--effort`) per invocation, **not** via an environment variable.

Supported levels: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` (per-model subset may vary). The authoritative per-model lookup — which levels a specific model supports and the recommended default — is [`shared/reasoning-effort-lookup.md`](reasoning-effort-lookup.md) (OpenCode Go focus; method applies to any BYOK model).

Do not assume a `COPILOT_*` environment variable exists for reasoning effort unless `copilot help environment` in the installed CLI version explicitly lists one.

## Examples (provider-agnostic)

These examples use the env-var mechanism directly. For repeatable, multi-provider setups, prefer the profile manager (`scripts/byok-profile.ps1` in the skill root) — see [`provider/opencode-go/cli.md`](../provider/opencode-go/cli.md) etc. for provider-specific profiles.

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

## Offline mode

Offline mode (`COPILOT_OFFLINE=true`) prevents Copilot CLI from contacting GitHub's servers. Use it only when the user explicitly wants Copilot CLI isolated from GitHub services; note that full isolation still depends on the provider endpoint being local or private. It only guarantees full network isolation when the provider endpoint is also local or on-premises.

Use `COPILOT_OFFLINE=true` only when the user explicitly wants Copilot CLI isolated from GitHub services; note that full isolation still depends on the provider endpoint being local or private.