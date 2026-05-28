---
name: copilot-cli-byok
description: Configure and switch between BYOK (Bring Your Own Key) LLM providers for GitHub Copilot CLI. Use when setting up OpenAI, Azure OpenAI, Anthropic, Ollama, Moonshot, or other OpenAI-compatible endpoints; creating or switching reusable provider profiles; calculating max prompt or output token overrides; or troubleshooting COPILOT_PROVIDER_BASE_URL, COPILOT_PROVIDER_TYPE, COPILOT_PROVIDER_API_KEY, COPILOT_MODEL, COPILOT_PROVIDER_MAX_PROMPT_TOKENS, COPILOT_PROVIDER_MAX_OUTPUT_TOKENS, and COPILOT_OFFLINE.
---

# Copilot CLI BYOK Provider Configuration

Use this skill to configure Copilot CLI against non-GitHub-hosted model providers and to manage repeatable provider profiles.

## Follow this workflow

1. Determine whether the user needs a **profile-based setup**, a **one-off manual setup**, or **troubleshooting**.
2. Prefer `scripts/byok-profile.ps1` for repeated use or when the user wants to switch providers quickly.
3. Read only the reference file that matches the current need.
4. Keep secrets out of files. Prefer `${ENV_VAR}` placeholders and user-scoped environment variables.

## Choose the path

- **Reusable profile workflow**: Use `scripts/byok-profile.ps1`.
- **Manual one-off environment setup**: Read `references/providers.md`.
- **API key storage or rotation**: Read `references/api-key-storage.md`.
- **Token-limit sizing**: Read `references/providers.md` first, then calculate conservative prompt and output limits.

## Use the profile manager first

Use `scripts/byok-profile.ps1` when the user wants repeatable setup, named profiles, or quick switching.

Common commands:

```powershell
# List profiles
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 list

# Add a profile interactively
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 add

# Inspect a stored profile
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 show openai

# Run Copilot CLI with a profile for one session
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 run ollama

# Apply a profile to the current shell
. .\skills\copilot-cli-byok\scripts\byok-profile.ps1 set-env openai
```

Pass extra CLI arguments through `run`:

```powershell
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 run openai --model gpt-5.4
```

Profiles are stored in `~/.copilot/byok-profiles.json` or `$env:COPILOT_HOME\byok-profiles.json`.

## Read references on demand

- `references/providers.md`
  - Read when you need provider-specific environment variables, examples, model requirements, or offline-mode notes.
- `references/api-key-storage.md`
  - Read when the user needs secure key storage, persistent Windows environment variables, key rotation, or `${ENV_VAR}` placeholder guidance.

## Apply these operating rules

- Prefer `${ENV_VAR}` placeholders over raw API keys in JSON.
- Treat `openai` as the default provider type for OpenAI-compatible endpoints such as Ollama, vLLM, Foundry Local, and Moonshot.
- Set `COPILOT_PROVIDER_TYPE=azure` only for Azure OpenAI and `anthropic` only for Anthropic.
- Use `COPILOT_OFFLINE=true` only when the user explicitly wants Copilot CLI isolated from GitHub services; note that full isolation still depends on the provider endpoint being local or private.
- If the model is not in Copilot CLI's built-in catalog, set explicit prompt and output token overrides instead of assuming Copilot will infer them correctly.

## Calculate token overrides conservatively

When the user asks for `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` or `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS`:

1. Get the model's documented context window.
2. Pick a realistic max output budget for the workload.
3. Reserve a safety buffer for tool calls, system instructions, and multi-turn variance.
4. Compute:

`maxPromptTokens = contextWindow - plannedMaxOutput - safetyBuffer`

Prefer stable values over theoretical maximums. If the user reports context-limit failures, reduce prompt tokens by 5-10% and retry.

## Troubleshoot in this order

1. Confirm the base URL, provider type, model name, and API key source.
2. Confirm the model supports streaming and tool calling.
3. If using a stored profile, run `show` or `list` to verify the saved values.
4. If `${ENV_VAR}` placeholders are used, confirm the environment variable actually exists.
5. If long-context models fail, add or lower explicit max prompt and output token overrides.

## Important provider caveat

Kimi Code (`https://api.kimi.com/coding/v1`) is currently useful only as a placeholder profile for Copilot CLI because that backend enforces an allowlist and may return `403 Forbidden` for unsupported clients. Use Moonshot Open Platform endpoints for working OpenAI-compatible Kimi-family access unless the provider explicitly adds Copilot CLI support.

## Related skill

For MCP server configuration rather than model-provider configuration, read `../copilot-cli-mcp-config/SKILL.md`.
