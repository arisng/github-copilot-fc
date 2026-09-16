# Moonshot — VS Code Chat

Configuring the Moonshot (Kimi AI) provider for **VS Code Chat** (`chatLanguageModels.json`). For Copilot CLI, see [`cli.md`](cli.md).

## Prerequisites

1. Store your Moonshot API key in VS Code secret storage (via **Chat: Manage Language Models → Add Models → Custom Endpoint**).
2. **One-time setup: configure DNS + cert for the `top_p` proxy.** Run once as admin:

```powershell
.\scripts\setup-dns.ps1
```

3. **Start the proxy** (after every reboot):

```powershell
.\scripts\start-proxy.ps1
```

Or use the VS Code task: **Terminal → Run Task → "Moonshot Proxy"**.

## UI Quick-Add

1. Open **Chat: Manage Language Models → Add Models → Custom Endpoint**.
2. Name: `Moonshot (Kimi AI)`.
3. API Type: `Chat Completions`.
4. Base URL: `https://moonshot.local/v1/chat/completions` (requires proxy).
5. Paste your API key.

This creates a single provider entry. To add more models, edit `chatLanguageModels.json` directly.

## Full Provider JSON

Add this to `chatLanguageModels.json` to register all Kimi models with proxy support:

```json
{
  "providers": [
    {
      "id": "moonshot-proxy",
      "baseUrl": "https://moonshot.local/v1/chat/completions",
      "apiKey": "${input:chat.lm.secret.moonshot}",
      "model": "kimi-k2.7-code",
      "name": "Moonshot Kimi K2.7 Code",
      "modelId": "kimi-k2.7-code"
    },
    {
      "id": "moonshot-proxy",
      "baseUrl": "https://moonshot.local/v1/chat/completions",
      "apiKey": "${input:chat.lm.secret.moonshot}",
      "model": "kimi-k2.6",
      "name": "Moonshot Kimi K2.6",
      "modelId": "kimi-k2.6"
    },
    {
      "id": "moonshot-proxy",
      "baseUrl": "https://moonshot.local/v1/chat/completions",
      "apiKey": "${input:chat.lm.secret.moonshot}",
      "model": "kimi-k2.5",
      "name": "Moonshot Kimi K2.5",
      "modelId": "kimi-k2.5"
    }
  ]
}
```

## VS Code Tasks Configuration

Add to `.vscode/tasks.json` to auto-start the proxy on folder open:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Moonshot Proxy",
      "type": "shell",
      "command": "pwsh -NoProfile -File \"${env:USERPROFILE}\\.copilot\\skills\\copilot-byok\\scripts\\start-proxy.ps1\"",
      "runOptions": {
        "runOn": "folderOpen"
      },
      "presentation": {
        "reveal": "silent",
        "panel": "dedicated"
      }
    }
  ]
}
```

## Troubleshooting

1. **Proxy not running**: Check `curl -s https://moonshot.local/health`. If failed, run `.\scripts\start-proxy.ps1`.
2. **Certificate error**: Re-run `.\scripts\setup-dns.ps1` to trust the cert.
3. **`top_p` error**: Ensure you're using `moonshot.local` URL, not `api.moonshot.ai` directly.
4. **Models not appearing**: Reload VS Code window (**Developer: Reload Window**) after editing `chatLanguageModels.json`.
