# How to configure BYOK LLM providers for Copilot CLI

This guide shows how to configure GitHub Copilot CLI to use your own LLM provider (Bring Your Own Key) instead of GitHub-hosted models.

## Prerequisites

- GitHub Copilot CLI is installed.
- You have an API key from a supported provider, or a local model running (e.g., Ollama).

## Supported providers

Copilot CLI supports three provider types:

| Provider type | Compatible services |
|---------------|---------------------|
| `openai` | OpenAI, Ollama, vLLM, Foundry Local, and any OpenAI Chat Completions API-compatible endpoint. This is the default. |
| `azure` | Azure OpenAI Service. |
| `anthropic` | Anthropic (Claude models). |

## Model requirements

The chosen model must support **tool calling** and **streaming**. For best results, use a model with at least a **128k token** context window.

## Manual configuration

Set the following environment variables before launching `copilot`:

| Variable | Required | Description |
|----------|----------|-------------|
| `COPILOT_PROVIDER_BASE_URL` | Yes | The base URL of the API endpoint. |
| `COPILOT_PROVIDER_TYPE` | No | `openai` (default), `azure`, or `anthropic`. |
| `COPILOT_PROVIDER_API_KEY` | No | API key. Omit for unauthenticated local endpoints. |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` | No | Override the max prompt token limit. Useful for models not in Copilot CLI's built-in catalog. |
| `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS` | No | Override the max output token limit. |
| `COPILOT_MODEL` | Yes | Model identifier. |

### Example: Ollama (local)

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'http://localhost:11434'
$env:COPILOT_MODEL = 'llama3.2'
copilot
```

### Example: OpenAI

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.openai.com/v1'
$env:COPILOT_PROVIDER_API_KEY = $env:OPENAI_API_KEY
$env:COPILOT_MODEL = 'gpt-4o'
copilot
```

### Example: Azure OpenAI

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT'
$env:COPILOT_PROVIDER_TYPE = 'azure'
$env:COPILOT_PROVIDER_API_KEY = $env:AZURE_OPENAI_API_KEY
$env:COPILOT_MODEL = 'YOUR-DEPLOYMENT'
copilot
```

### Example: Anthropic

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.anthropic.com'
$env:COPILOT_PROVIDER_TYPE = 'anthropic'
$env:COPILOT_PROVIDER_API_KEY = $env:ANTHROPIC_API_KEY
$env:COPILOT_MODEL = 'claude-opus-4-5'
copilot
```

### Example: Kimi Code (kimi.com/code subscription)

If you have a Kimi Code subscription and generated an API key from https://www.kimi.com/code/console, use the Kimi Code OpenAI-compatible endpoint with `provider type = openai`:

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.kimi.com/coding/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:KIMICODE_API_KEY
$env:COPILOT_MODEL = 'kimi-for-coding'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 262144
copilot
```

> **Note:** As of now, Kimi Code's backend enforces an agent whitelist and returns `403 Forbidden` for clients other than Kimi CLI, Claude Code, Roo Code, and Kilo Code. GitHub Copilot CLI is not yet whitelisted, so this configuration serves as a placeholder.

### Example: Moonshot Open Platform

For the general Moonshot API, use the Moonshot OpenAI-compatible endpoint with `provider type = openai`:

```powershell
$env:COPILOT_PROVIDER_BASE_URL = 'https://api.moonshot.cn/v1'
$env:COPILOT_PROVIDER_TYPE = 'openai'
$env:COPILOT_PROVIDER_API_KEY = $env:MOONSHOT_API_KEY
$env:COPILOT_MODEL = 'kimi-k2.5'
$env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = 256000
copilot
```

Available regions:
- China: `https://api.moonshot.cn/v1`
- Global: `https://api.moonshot.ai/v1`

Common Moonshot models: `kimi-k2.5`, `kimi-k2`, `moonshot-v1-8k`, `moonshot-v1-32k`, `moonshot-v1-128k`.

Explicitly set `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` to avoid Copilot CLI defaulting to a smaller limit.

## Using the BYOK profile manager script

Switching between providers manually can be tedious. The `byok-profile.ps1` script stores provider configurations as named profiles and launches Copilot CLI with the correct environment variables.

**Script location:** `skills/copilot-cli-byok/scripts/byok-profile.ps1`

### List profiles

```powershell
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 list
```

### Add a profile interactively

```powershell
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 add
```

### Run Copilot CLI with a specific profile

This launches Copilot CLI with the profile's environment variables applied only to that process:

```powershell
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 run ollama
```

You can also pass extra arguments to `copilot`:

```powershell
.\skills\copilot-cli-byok\scripts\byok-profile.ps1 run openai --model gpt-4o
```

### Apply a profile to the current shell session

Dot-source the script so the environment variables persist in your current terminal session:

```powershell
. .\skills\copilot-cli-byok\scripts\byok-profile.ps1 set-env openai
```

### Create a shell alias (optional)

Add the following to your PowerShell profile (`$PROFILE`) for quick access without typing the full path:

```powershell
function copilot-byok {
    & C:\path\to\repo\skills\copilot-cli-byok\scripts\byok-profile.ps1 @args
}
```

Then use it anywhere:

```powershell
copilot-byok run ollama
copilot-byok list
```

#### One-time setup helper

Run this from the repository root to auto-inject the alias into your PowerShell profile:

```powershell
$repoRoot = (Get-Location).Path
$aliasLine = @"

function copilot-byok {
    & `"$repoRoot\skills\copilot-cli-byok\scripts\byok-profile.ps1`" @args
}
"@

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
if ((Get-Content $PROFILE -Raw) -notlike '*function copilot-byok*') {
    Add-Content -Path $PROFILE -Value $aliasLine
    Write-Host "Added 'copilot-byok' alias to `$PROFILE. Restart your shell to use it." -ForegroundColor Green
}
else {
    Write-Host "'copilot-byok' alias already exists in `$PROFILE." -ForegroundColor Yellow
}
```

#### Alternative: add the scripts folder to PATH

If you prefer invoking the script directly by name without an alias:

```powershell
# Permanent (User scope)
[Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;C:\path\to\repo\skills\copilot-cli-byok\scripts",
    "User"
)
```

After restarting your shell, run:

```powershell
byok-profile.ps1 list
byok-profile.ps1 run kimi
```

## Offline mode

To prevent Copilot CLI from contacting GitHub's servers entirely, set `COPILOT_OFFLINE=true`:

```powershell
$env:COPILOT_OFFLINE = 'true'
copilot
```

When using the profile manager, enable offline mode during `add` or set `"offline": true` in the JSON file.

> **Important:** Full network isolation is only guaranteed when the provider endpoint is also local or on-premises.
