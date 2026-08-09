# OpenRouter Provider Reference

OpenRouter is an OpenAI-compatible endpoint that provides access to various models.

## Environment Variables

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

When using DeepSeek models on OpenRouter, you can leverage dynamic routing to capture active provider discounts:

- `deepseek/deepseek-v4-pro:floor` (Recommended for lowest price): Automatically routes your request to the provider offering the lowest rate (floor price / active discounts).
- `deepseek/deepseek-v4-pro:nitro`: Routes to the provider with the lowest latency/highest throughput.
- `deepseek/deepseek-v4-pro`: Default balance of availability, throughput, and pricing.

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

Set the environment variable `OPENROUTER_API_KEY` to your OpenRouter key.

### VS Code Chat

In VS Code, use **Chat: Manage Language Models → Add Models → Custom Endpoint**:
- Name: OpenRouter (or specific model)
- API Key: your OpenRouter key
- API Type: Chat Completions
- API URL: `https://openrouter.ai/api/v1/chat/completions`
- Model ID: e.g., `deepseek/deepseek-v4-pro:floor`

## Notes

- OpenRouter supports a wide range of models from different providers.
- Be aware of rate limits and costs associated with each model.
- For models that support reasoning (e.g., OpenAI's o1 series), you may need to adjust `COPILOT_PROVIDER_WIRE_API` and use `--reasoning-effort` accordingly.
- To verify which provider processed your request and the exact cost/discount applied, check your OpenRouter Activity Dashboard.