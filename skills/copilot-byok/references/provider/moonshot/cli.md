# Moonshot — Copilot CLI

Configuring the Moonshot (Kimi AI) provider for **GitHub Copilot CLI**. For VS Code Chat, see [`vs-code.md`](vs-code.md). Provider-independent env-var semantics: [`../shared/environment-variables.md`](../../shared/environment-variables.md).

## Prerequisites

1. Obtain a Moonshot API key from [Kimi AI Platform](https://api.moonshot.ai).
2. Store the key as an environment variable at **User scope**: `MOONSHOT_API_KEY`:

```powershell
[Environment]::SetEnvironmentVariable("MOONSHOT_API_KEY", "<your-moonshot-api-key>", "User")
```

3. **One-time setup: configure DNS + cert for the `top_p` proxy.** Moonshot models only accept `top_p=0.95`, but Copilot CLI sends `top_p=1.0` by default. A local proxy strips `top_p` before forwarding. Run once as admin:

```powershell
.\scripts\setup-dns.ps1
```

This adds `127.0.0.1 moonshot.local` to your hosts file and trusts the SSL certificate.

## Base URL

```
https://api.moonshot.ai/v1
```

All Kimi models use the same base URL. Copilot CLI appends `/chat/completions` based on `COPILOT_PROVIDER_TYPE=openai`.

## Available Models

| Model | Bare Model ID (`COPILOT_MODEL`) | Provider Type | Context Window | Reasoning Effort |
|-------|--------------------------------|---------------|----------------|-----------------|
| Kimi K2.7 Code | `kimi-k2.7-code` | `openai` | 262K | Not supported (thinking always-on) |
| Kimi K2.6 | `kimi-k2.6` | `openai` | 262K | Not supported (implicit thinking) |
| Kimi K2.5 | `kimi-k2.5` | `openai` | 262K | Not supported (implicit thinking) |

> All Kimi models have implicit/always-on thinking. Do not use `--reasoning-effort` with these models.

## Manual Environment Variables

```powershell
# Set provider
[Environment]::SetEnvironmentVariable("COPILOT_PROVIDER_TYPE", "openai", "User")
[Environment]::SetEnvironmentVariable("COPILOT_PROVIDER_BASE_URL", "https://api.moonshot.ai/v1", "User")
[Environment]::SetEnvironmentVariable("COPILOT_PROVIDER_API_KEY", "${MOONSHOT_API_KEY}", "User")

# Set model
[Environment]::SetEnvironmentVariable("COPILOT_MODEL", "kimi-k2.7-code", "User")

# Token overrides (Moonshot enforces 262K context)
[Environment]::SetEnvironmentVariable("COPILOT_PROVIDER_MAX_PROMPT_TOKENS", "200000", "User")
[Environment]::SetEnvironmentVariable("COPILOT_PROVIDER_MAX_OUTPUT_TOKENS", "32768", "User")
```

## Profile Examples

### Direct connection (bypasses proxy, may fail with `top_p` error)

```json
{
  "name": "moonshot-kimi-k27-code",
  "providerType": "openai",
  "model": "kimi-k2.7-code",
  "baseUrl": "https://api.moonshot.ai/v1",
  "apiKey": "${MOONSHOT_API_KEY}",
  "maxPromptTokens": 200000,
  "maxOutputTokens": 32768,
  "reasoningEffortSupported": false
}
```

### With proxy (recommended for VS Code)

```json
{
  "name": "moonshot-kimi-k27-code-proxy",
  "providerType": "openai",
  "model": "kimi-k2.7-code",
  "baseUrl": "https://moonshot.local/v1",
  "apiKey": "${MOONSHOT_API_KEY}",
  "maxPromptTokens": 200000,
  "maxOutputTokens": 32768,
  "reasoningEffortSupported": false,
  "proxyPort": 443
}
```

The `proxyPort` field tells `byok-profile.ps1 run` to auto-start the Moonshot proxy and route through `https://moonshot.local/v1`.

## Multiple Accounts

Moonshot does not support multiple accounts in the same way as OpenCode Go. If you have multiple Moonshot API keys, create separate profiles with different names (e.g., `moonshot-kimi-k27-code-personal`, `moonshot-kimi-k27-code-work`).

## Troubleshooting

1. **`top_p` error**: Ensure the proxy is running (`curl -s https://moonshot.local/health`). If using CLI, consider using the proxy profile or accept the error.
2. **Authentication error**: Verify `MOONSHOT_API_KEY` is set at User scope and the key is valid.
3. **Context limit**: Moonshot enforces 262K context. Set `maxPromptTokens` to ~200K to leave room for output.
