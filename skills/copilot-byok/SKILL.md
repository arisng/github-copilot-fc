---
name: copilot-byok
description: Configure and switch between BYOK (Bring Your Own Key) LLM providers for both GitHub Copilot CLI and VS Code Chat. Use when setting up OpenAI, Azure OpenAI, Anthropic, Ollama, Moonshot, OpenCode Go, or other OpenAI-compatible endpoints; creating or switching reusable provider profiles for CLI; configuring chatLanguageModels.json for VS Code; calculating max prompt or output token overrides; configuring wire API and reasoning effort; or troubleshooting COPILOT_PROVIDER_BASE_URL, COPILOT_PROVIDER_TYPE, COPILOT_PROVIDER_API_KEY, COPILOT_MODEL, COPILOT_PROVIDER_WIRE_API, COPILOT_PROVIDER_MAX_PROMPT_TOKENS, COPILOT_PROVIDER_MAX_OUTPUT_TOKENS, COPILOT_OFFLINE, and VS Code language model settings.
metadata:
  author: arisng
  version: 0.5.0
---

# Copilot BYOK Provider Configuration

Use this skill to configure BYOK (Bring Your Own Key) LLM providers for **both GitHub Copilot CLI and VS Code Chat**. Manage repeatable CLI provider profiles and VS Code `chatLanguageModels.json` from a single source of truth.

## Follow this workflow

1. Determine whether the user needs a **CLI profile-based setup**, **VS Code BYOK setup**, a **one-off manual setup**, or **troubleshooting**.
2. For CLI, prefer `scripts/byok-profile.ps1` for repeated use or quick switching between providers.
3. For VS Code, read `references/copilot-vscode-providers.md` and use the **Chat: Manage Language Models** UI command.
4. Read only the reference file that matches the current need.
5. Keep secrets out of files. Prefer `${ENV_VAR}` placeholders and user-scoped environment variables.

## Choose the path

### CLI paths

- **Reusable profile workflow**: Use `scripts/byok-profile.ps1`.
- **Manual one-off environment setup**: Read `references/copilot-cli-providers.md`.
- **API key storage or rotation**: Read `references/api-key-storage.md`.
- **Token-limit sizing**: Read `references/copilot-cli-providers.md` first, then calculate conservative prompt and output limits.
- **Reasoning-level configuration**: Read `references/copilot-cli-providers.md`, then apply `--reasoning-effort` per invocation.

### VS Code path

- **VS Code BYOK setup**: Read `references/copilot-vscode-providers.md` and use the **Chat: Manage Language Models** UI command to add models. VS Code uses `chatLanguageModels.json` and ignores `COPILOT_PROVIDER_*` env vars.

## Use the profile manager first

Use `scripts/byok-profile.ps1` when the user wants repeatable setup, named profiles, or quick switching.

Run the following commands from the installed `copilot-byok` skill folder (the folder that contains this `SKILL.md`).

Common commands:

```powershell
# List profiles
.\scripts\byok-profile.ps1 list

# Add a profile interactively
.\scripts\byok-profile.ps1 add

# Inspect a stored profile
.\scripts\byok-profile.ps1 show openai

# Run Copilot CLI with a profile for one session
.\scripts\byok-profile.ps1 run ollama

# Apply a profile to the current shell
. .\scripts\byok-profile.ps1 set-env openai
```

Pass extra Copilot CLI arguments through `run` (do not pass `--model`; model is sourced from the profile):

```powershell
.\scripts\byok-profile.ps1 run openai --help
```

Profiles are stored in `~/.copilot/byok-profiles.json` or `$env:COPILOT_HOME\byok-profiles.json`.

## Read references on demand

- `references/copilot-cli-providers.md`
  - Read when you need CLI-specific provider environment variables, examples, model requirements, or offline-mode notes.
- `references/copilot-vscode-providers.md`
  - Read when the user wants to configure BYOK models in **VS Code Chat**. VS Code uses a completely different mechanism (`chatLanguageModels.json`) and ignores `COPILOT_PROVIDER_*` env vars. This reference covers multi-provider setup, per-agent model pinning via `.agent.md` frontmatter, agent-specific model settings, and the full model-to-VS-Code mapping from `byok-profiles.json`.
- `references/api-key-storage.md`
  - Read when the user needs secure key storage, persistent Windows environment variables, key rotation, or `${ENV_VAR}` placeholder guidance.

## Apply these operating rules

- Prefer `${ENV_VAR}` placeholders over raw API keys in JSON.
- Treat `openai` as the default provider type for OpenAI-compatible endpoints such as Ollama, vLLM, Foundry Local, and Moonshot.
- Set `COPILOT_PROVIDER_TYPE=azure` only for Azure OpenAI and `anthropic` only for Anthropic.
- **OpenCode Go** uses a shared base URL with two possible provider types: `openai` (append `/v1`) for DeepSeek, GLM, Kimi, and MiMo models; `anthropic` (no `/v1` suffix — SDK adds it) for MiniMax and Qwen models. Store the OpenCode API key as `OPENCODE_API_KEY`.
- **CRITICAL: `COPILOT_MODEL` must use the bare model ID** (e.g., `deepseek-v4-flash`), **not** the `opencode-go/` prefix. The prefix is only used in OpenCode TUI config and in Copilot CLI profile names — never in `COPILOT_MODEL`.
- For GPT-5 class OpenAI models, prefer `COPILOT_PROVIDER_WIRE_API=responses`.
- Use `COPILOT_OFFLINE=true` only when the user explicitly wants Copilot CLI isolated from GitHub services; note that full isolation still depends on the provider endpoint being local or private.
- If the model is not in Copilot CLI's built-in catalog, set explicit prompt and output token overrides instead of assuming Copilot will infer them correctly.

## Configure reasoning effort correctly

Use Copilot CLI's `--reasoning-effort` option for model reasoning level control.

- Supported levels: `none`, `low`, `medium`, `high`, `xhigh`, `max`.
- Apply it per run, for example:

```powershell
.\scripts\byok-profile.ps1 run dprocess-openai-gpt-54 --reasoning-effort medium
```

For OpenAI models, you may also enable summaries:

```powershell
.\scripts\byok-profile.ps1 run dprocess-openai-gpt-54 --reasoning-effort high --enable-reasoning-summaries
```

Do not claim a dedicated `COPILOT_*` environment variable exists for reasoning effort unless `copilot help environment` in the user's installed CLI version explicitly lists one.

## Grounding and evidence standard

When answering questions in this domain, always separate grounded facts from inference:

1. Cite authoritative evidence used (for example, `copilot --help`, `copilot help environment`, provider model docs).
2. State what is directly evidenced versus inferred operational guidance.
3. End with an explicit conclusion:
  - `Grounding status: evidence-backed` when all key claims are directly supported.
  - `Grounding status: mixed (evidence + inference)` when any recommendation is inferred.

Do not present inferred workarounds (for example wrapper aliases for sticky defaults) as first-class documented product features.

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

## Moonshot/Kimi AI credentials

Use `MOONSHOT_API_KEY` for the Kimi AI Platform (`api.moonshot.ai/v1`). All models use OpenAI-compatible format, 262K context, and support tool calling and streaming.

## Related skill

For MCP server configuration rather than model-provider configuration, read `../copilot-cli-mcp-config/SKILL.md`.
