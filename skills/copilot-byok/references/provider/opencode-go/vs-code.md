# OpenCode Go — VS Code Chat

Configuring the OpenCode Go provider for **VS Code Chat** via `chatLanguageModels.json`. For Copilot CLI, see [`cli.md`](cli.md).

File-level mechanism (secret storage, `maxInputTokens + maxOutputTokens ≤ context`, model naming, per-agent pinning, quick start, troubleshooting): [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md). Read that first if this is your first VS Code BYOK setup.

## Complete Model Configuration

### OpenCode Go — OpenAI-compatible models (DeepSeek, Kimi, GLM, MiMo)

Use `vendor: "customendpoint"` with `apiType: "chat-completions"`. Start with **Add Models → Custom Endpoint** in the UI to store the API key in VS Code's secret storage, then edit the generated JSON to add all models.

Generated structure (after UI setup adds the `apiKey` secret reference):

```json
{
  "name": "OpenCode Go (OpenAI)",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.XXXXXXXX}",
  "apiType": "chat-completions",
  "models": [
    {
      "id": "deepseek-v4-flash",
      "name": "DeepSeek V4 Flash",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 325000,
      "maxOutputTokens": 64000,
      "thinking": true,
      "supportsReasoningEffort": ["low", "medium", "high"]
    },
    {
      "id": "deepseek-v4-pro",
      "name": "DeepSeek V4 Pro",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 325000,
      "maxOutputTokens": 64000,
      "thinking": true,
      "supportsReasoningEffort": ["low", "medium", "high"]
    },
    {
      "id": "kimi-k2.7-code",
      "name": "Kimi K2.7 Code",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 240000,
      "maxOutputTokens": 32768,
      "thinking": true
    },
    {
      "id": "kimi-k2.6",
      "name": "Kimi K2.6",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 240000,
      "maxOutputTokens": 32768,
      "thinking": true
    },
    {
      "id": "kimi-k2.5",
      "name": "Kimi K2.5",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 240000,
      "maxOutputTokens": 32768,
      "thinking": true
    },
    {
      "id": "glm-5.2",
      "name": "GLM-5.2",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 178000,
      "maxOutputTokens": 16384,
      "thinking": true
    },
    {
      "id": "glm-5.1",
      "name": "GLM-5.1",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 178000,
      "maxOutputTokens": 16384,
      "thinking": true
    },
    {
      "id": "glm-5",
      "name": "GLM-5",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 178000,
      "maxOutputTokens": 16384,
      "thinking": true
    },
    {
      "id": "mimo-v2.5",
      "name": "MiMo-V2.5",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 980000,
      "maxOutputTokens": 64000,
      "thinking": true
    },
    {
      "id": "mimo-v2.5-pro",
      "name": "MiMo-V2.5-Pro",
      "url": "https://opencode.ai/zen/go/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 980000,
      "maxOutputTokens": 64000,
      "thinking": true
    }
  ]
}
```

> **MiMo-V2.5 token grounding (empirical 2026-08-19).** The OpenCode Go gateway enforces a **1,048,576-token hard ceiling** (prompt + output combined). MiMo-V2.5 passes through the full gateway limit — 1M prompt tokens succeeded, 1.05M returned 400. Unlike DeepSeek V4 (~325K effective), MiMo-V2.5 has no gateway compaction below its theoretical 1M window. The values above (980K input + 64K output = 1,044K) stay safely under the ceiling. `maxOutputTokens: 64000` is practical for coding tasks; the model accepts output limits up to 1M at the API level.

### OpenCode Go — Responses API model (GPT-5.6 Luna)

GPT-5.6 Luna is served through **both** the OpenAI Responses API (`/v1/responses`) and `chat/completions` — probes 2026-08-03 + re-verified 2026-08-05 (CLI 1.0.78) confirmed both work on OpenCode Go. `apiType: "responses"` is the **recommended** configuration for GPT-5-class models (it matches the CLI profile `wireApi: responses` and was verified end-to-end via the real CLI, exit 0, `model.call_start` = `gpt-5.6-luna`). Use `vendor: "customendpoint"` with `apiType: "responses"` (select **Responses** when adding via the UI). The `chat-completions` apiType also works if you prefer the completions wire.

```json
{
  "name": "OpenCode Go (Responses)",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.XXXXXXXX}",
  "apiType": "responses",
  "models": [
    {
      "id": "gpt-5.6-luna",
      "name": "GPT-5.6 Luna",
      "url": "https://opencode.ai/zen/go/v1/responses",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 200000,
      "maxOutputTokens": 64000,
      "thinking": true,
      "supportsReasoningEffort": ["low", "medium", "high", "max"],
      "reasoningEffortFormat": "responses"
    }
  ]
}
```

> **Token grounding.** [models.dev](https://models.dev/models/openai/gpt-5.6-luna/) lists the model's theoretical context as 1,050,000 tokens with a 128,000 output limit, but [OpenCode Go prices GPT-5.6 Luna in two per-request tiers split at 272K tokens](https://opencode.ai/docs/go/) (≤272K: $0.20/$1.20 · >272K: $0.40/$1.80 per MTok). The values above (200K input + 64K output = 264K) keep requests inside the cheaper tier and mirror the caps used by the other OpenCode Go OpenAI profiles. VS Code requires `maxInputTokens + maxOutputTokens` to stay within the model's context window — setting the theoretical 1,050,000 here would push requests into the 2x-priced tier and invite gateway compaction failures.
>
> `reasoningEffortFormat: "responses"` forwards thinking effort as a nested `reasoning.effort` object (it defaults to that automatically because the URL ends in `/responses`; per the VS Code schema, `responses` = nested `reasoning.effort`, `chat-completions` = top-level `reasoning_effort`). This is the *correct* form — a top-level `reasoning_effort` field on the responses wire is rejected with 400, and `max_prompt_tokens` is likewise rejected on `/v1/responses` (but VS Code does not send it there; see the [CLI wire-format matrix](cli.md) for the full curl evidence). Note GPT-5.6 Luna data is retained for 30 days under OpenAI policy — it does **not** have Zero Data Retention, so leave `zeroDataRetentionEnabled` unset.

### OpenCode Go — Anthropic-compatible models (MiniMax, Qwen)

Use `vendor: "customendpoint"` with `apiType: "messages"`. Add via UI first to store the API key, then edit JSON to add all models:

> **Endpoint correction (2026-08-05)**: the [OpenCode Go docs](https://opencode.ai/docs/go/#endpoints) list MiniMax (M3/M2.7/M2.5) and Qwen (3.8 Max/3.7 Max/3.7 Plus/3.6 Plus) at **`https://opencode.ai/zen/go/v1/messages`** with `@ai-sdk/anthropic`. An earlier 2026-08-03 probe reported 401 on `/v1/messages`, but that used `Authorization: Bearer` — the Anthropic Messages API requires `x-api-key` (+ `anthropic-version`) headers, which VS Code's `messages` apiType sends automatically. So the 401 was an auth-header artifact, **not** evidence the endpoint is unsupported. The same models also responded on `chat/completions` in that probe, so the gateway tolerates both — but `/v1/messages` is the documented path and the one to configure.

```json
{
  "name": "OpenCode Go (Anthropic)",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.XXXXXXXX}",
  "apiType": "messages",
  "models": [
    {
      "id": "minimax-m3",
      "name": "MiniMax M3",
      "url": "https://opencode.ai/zen/go/v1/messages",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 960000,
      "maxOutputTokens": 4096,
      "thinking": true
    },
    {
      "id": "minimax-m2.7",
      "name": "MiniMax M2.7",
      "url": "https://opencode.ai/zen/go/v1/messages",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 178000,
      "maxOutputTokens": 16384,
      "thinking": true
    },
    {
      "id": "qwen3.7-plus",
      "name": "Qwen3.7 Plus",
      "url": "https://opencode.ai/zen/go/v1/messages",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 960000,
      "maxOutputTokens": 32768,
      "thinking": true
    },
    {
      "id": "qwen3.7-max",
      "name": "Qwen3.7 Max",
      "url": "https://opencode.ai/zen/go/v1/messages",
      "toolCalling": true,
      "vision": false,
      "streaming": true,
      "maxInputTokens": 960000,
      "maxOutputTokens": 32768,
      "thinking": true
    },
    {
      "id": "qwen3.6-plus",
      "name": "Qwen3.6 Plus",
      "url": "https://opencode.ai/zen/go/v1/messages",
      "toolCalling": true,
      "vision": true,
      "streaming": true,
      "maxInputTokens": 960000,
      "maxOutputTokens": 32768,
      "thinking": true
    }
  ]
}
```

### Multiple OpenCode Zen accounts (Home / Work)

If you hold two OpenCode Zen subscriptions — personal and work — VS Code does **not** read the CLI `accounts` registry in `byok-profiles.json`; that file only drives Copilot CLI (`byok-profile.ps1` / `Invoke-CopilotCliSubSession.ps1`). In VS Code each account is a **separate provider entry**, each with its own API key in secret storage.

To mirror the CLI convention (`opencode-home` / `opencode-work`), create one provider per account per API type:

| Provider `name` in `chatLanguageModels.json` | Account | Env var (CLI) | `apiType` |
|----------------------------------------------|---------|---------------|-----------|
| `OpenCode Go (Home, OpenAI)` | personal | `OPENCODE_API_KEY_HOME` | `chat-completions` |
| `OpenCode Go (Home, Responses)` | personal | `OPENCODE_API_KEY_HOME` | `responses` |
| `OpenCode Go (Home, Anthropic)` | personal | `OPENCODE_API_KEY_HOME` | `messages` |
| `OpenCode Go (Work, OpenAI)` | work | `OPENCODE_API_KEY_WORK` | `chat-completions` |
| `OpenCode Go (Work, Responses)` | work | `OPENCODE_API_KEY_WORK` | `responses` |
| `OpenCode Go (Work, Anthropic)` | work | `OPENCODE_API_KEY_WORK` | `messages` |

Setup:

1. **Chat: Manage Language Models → Add Models → Custom Endpoint** — repeat once per row (6 providers). When prompted, paste the raw API key for that account; VS Code stores it in secret storage and writes a `${input:chat.lm.secret.XXXX}` reference. Never hand-edit `apiKey`.
2. Paste the model list from the [OpenAI-compatible](#opencode-go--openai-compatible-models-deepseek-kimi-glm-mimo), [Responses](#opencode-go--responses-api-model-gpt-56-luna), or [Anthropic-compatible](#opencode-go--anthropic-compatible-models-minimax-qwen) section into each provider's `models` array.
3. Reload the window.

**Automation for the common two-account case** (Home + Work): after the UI step that stores the *work* key (Add Models → Custom Endpoint named `OpenCode Go (Work, OpenAI)`, API Type *Chat Completions*), run the skill's helper to rename existing providers to `(Home, …)` and clone the full model lists as `(Work, …)`:

```powershell
.\scripts\opencode-vscode-add-work-account.ps1
```

It backs up `chatLanguageModels.json`, reuses the UI-generated secret reference, and is safe to re-run (it replaces the generated `(Work, …)` entries from fresh `(Home, …)` clones).

Model `name` fields are identical across accounts (e.g. `DeepSeek V4 Flash`), so the provider `name` is what distinguishes Home from Work in the picker. Per-agent model pinning and `chat.*Agent.model` settings still reference model names; choose the account by selecting the corresponding provider in the conversation.