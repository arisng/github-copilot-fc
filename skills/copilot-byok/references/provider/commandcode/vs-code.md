# Command Code — VS Code Chat

Configuring the Command Code provider for **VS Code Chat** via `chatLanguageModels.json`. For Copilot CLI, see [`cli.md`](cli.md).

File-level mechanism (secret storage, `maxInputTokens + maxOutputTokens ≤ context`, model naming, per-agent pinning, quick start, troubleshooting): [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md). Read that first if this is your first VS Code BYOK setup.

## Quick Add via UI

Use **Chat: Manage Language Models → Add Models → Custom Endpoint**:
- Name: Command Code (GOAT)
- API Key: your Command Code API key
- API Type: Chat Completions
- API URL: `https://api.commandcode.ai/provider/v1/chat/completions`
- Model ID: e.g., `deepseek/deepseek-v4-flash`

## Ready-to-Use JSON Config

Add this provider entry to `chatLanguageModels.json` (open via **Chat: Manage Language Models → Edit in settings.json** or directly at `%APPDATA%\Code - Insiders\User\chatLanguageModels.json`):

```json
{
	"name": "Command Code (GOAT)",
	"vendor": "customendpoint",
	"apiKey": "${input:chat.lm.secret.XXXXXXXX}",
	"apiType": "chat-completions",
	"models": [
		{
			"id": "deepseek/deepseek-v4.1-flash",
			"name": "DeepSeek V4.1 Flash (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1000000,
			"maxOutputTokens": 32768,
			"thinking": true,
			"supportsReasoningEffort": ["low", "medium", "high"]
		},
		{
			"id": "deepseek/deepseek-v4-flash",
			"name": "DeepSeek V4 Flash (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1000000,
			"maxOutputTokens": 32768,
			"thinking": true,
			"supportsReasoningEffort": ["low", "medium", "high"]
		},
		{
			"id": "xiaomi/mimo-v2.5",
			"name": "MiMo V2.5 (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1000000,
			"maxOutputTokens": 32768,
			"thinking": true
		},
		{
			"id": "xiaomi/mimo-v2.5-pro",
			"name": "MiMo V2.5 Pro (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1000000,
			"maxOutputTokens": 32768,
			"thinking": true
		},
		{
			"id": "meta/muse-spark-1.3-contributor",
			"name": "Muse Spark 1.3 Contributor (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1050000,
			"maxOutputTokens": 32768,
			"thinking": true
		},
		{
			"id": "openai/gpt-5.6-luna",
			"name": "GPT-5.6 Luna (CC)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1050000,
			"maxOutputTokens": 32768,
			"thinking": true,
			"supportsReasoningEffort": ["none", "low", "medium", "high", "xhigh", "max"]
		},
		{
			"id": "inclusionai/ling-3.0-flash-sante:free",
			"name": "Ling 3.0 Flash Sante (CC, Free)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 262000,
			"maxOutputTokens": 32768,
			"thinking": true
		},
		{
			"id": "poolside/laguna-s-2.1-free",
			"name": "Laguna S 2.1 (CC, Free)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 256000,
			"maxOutputTokens": 32768,
			"thinking": true
		},
		{
			"id": "meituan/longcat-2.0:free",
			"name": "LongCat 2.0 (CC, Free)",
			"url": "https://api.commandcode.ai/provider/v1/chat/completions",
			"toolCalling": true,
			"vision": false,
			"streaming": true,
			"maxInputTokens": 1050000,
			"maxOutputTokens": 32768,
			"thinking": true
		}
	]
}
```

### Per-agent model pinning in VS Code

Model `name` fields (e.g. `DeepSeek V4 Flash (CC)`) are what `.agent.md` `model:` frontmatter and `chat.*Agent.model` settings reference — not the `id`. See [`../shared/chat-language-models-json.md`](../../shared/chat-language-models-json.md) for the full pinning reference.

## Notes

- **No special headers or proxies required** — Command Code is a standard OpenAI-compatible endpoint.
- Replace `XXXXXXX` in the `apiKey` reference with the actual secret ID created by the VS Code UI (**Chat: Manage Language Models → Add Models → Custom Endpoint**).
- Token limits use documented context windows from Command Code's model pages. If you encounter issues, reduce `maxInputTokens` by 5-10%.
