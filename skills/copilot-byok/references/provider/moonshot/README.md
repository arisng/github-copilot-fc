# Moonshot (Kimi AI) — Provider Overview

Moonshot AI provides Kimi AI models via `https://api.moonshot.ai/v1`. All models use OpenAI-compatible format with 262K context window and support tool calling and streaming.

## Key Facts

| Property | Value |
|----------|-------|
| Base URL | `https://api.moonshot.ai/v1` |
| Provider Type | `openai` |
| Authentication | `MOONSHOT_API_KEY` environment variable |
| Context Window | 262K tokens |
| Tool Calling | Supported |
| Streaming | Supported |

## Models

All Kimi models use the same base URL and authentication:

- `kimi-k2.7-code` — Latest code-focused model
- `kimi-k2.6` — Previous generation
- `kimi-k2.5` — Legacy model

## Special Requirements

**`top_p` parameter:** Kimi models only accept `top_p=0.95`, but VS Code Copilot BYOK always sends `top_p=1.0`. A local HTTPS proxy is required to strip `top_p` before forwarding.

## Harness-specific Documentation

- [Copilot CLI](cli.md) — Profile setup, proxy configuration, credentials
- [VS Code Chat](vs-code.md) — `chatLanguageModels.json` configuration with proxy
