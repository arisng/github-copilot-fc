# OpenRouter — VS Code Chat

Configuring the OpenRouter provider for **VS Code Chat** via `chatLanguageModels.json`. For Copilot CLI, see [`cli.md`](cli.md).

File-level mechanism (secret storage, `maxInputTokens + maxOutputTokens ≤ context`, model naming, per-agent pinning, quick start, troubleshooting): [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md). Read that first if this is your first VS Code BYOK setup.

## Quick Add via UI

Use **Chat: Manage Language Models → Add Models → Custom Endpoint**:
- Name: OpenRouter (Floor)
- API Key: your OpenRouter key
- API Type: Chat Completions
- API URL: `https://openrouter.ai/api/v1/chat/completions`
- Model ID: e.g., `deepseek/deepseek-v4-pro:floor`

## Ready-to-Use JSON Config

Add this provider entry to `chatLanguageModels.json` (open via **Chat: Manage Language Models → Edit in settings.json** or directly at `%APPDATA%\Code - Insiders\User\chatLanguageModels.json`):

```json
{
	"name": "OpenRouter (Floor)",
	"vendor": "customendpoint",
	"apiKey": "${input:chat.lm.secret.73b04361}",
	"apiType": "chat-completions",
	"models": [
		{
			"id": "deepseek/deepseek-v4-pro:floor",
			"name": "DeepSeek V4 Pro (Floor)",
			"url": "https://openrouter.ai/api/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 200000,
			"maxOutputTokens": 64000,
			"thinking": true,
			"supportsReasoningEffort": [
				"high"
			]
		},
		{
			"id": "deepseek/deepseek-v4-flash-0731:floor",
			"name": "DeepSeek V4 Flash 0731 (Floor)",
			"url": "https://openrouter.ai/api/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 200000,
			"maxOutputTokens": 64000,
			"thinking": true,
			"supportsReasoningEffort": [
				"low",
				"medium",
				"high"
			]
		}
	]
}
```

### Per-agent model pinning in VS Code

Model `name` fields (e.g. `DeepSeek V4 Pro (Floor)`) are what `.agent.md` `model:` frontmatter and `chat.*Agent.model` settings reference — not the `id`. See [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md) for the full pinning reference.