---
name: copilot-cli-byok
description: Configure and switch between BYOK (Bring Your Own Key) LLM providers for GitHub Copilot CLI. Use when setting up OpenAI, Azure OpenAI, Anthropic, Ollama, or other OpenAI-compatible endpoints; switching provider profiles; or troubleshooting COPILOT_PROVIDER_BASE_URL, COPILOT_PROVIDER_TYPE, COPILOT_PROVIDER_API_KEY, COPILOT_MODEL, and COPILOT_OFFLINE configuration.
---

# Copilot CLI BYOK LLM Provider Configuration

Configure GitHub Copilot CLI to use your own LLM provider instead of GitHub-hosted models.

## Quick Start

Use the bundled profile manager script to avoid manual environment-variable setup every time.

**Script path:** `scripts/byok-profile.ps1`

### Common Commands

```powershell
# List stored profiles
.\scripts\byok-profile.ps1 list

# Add a new profile interactively
.\scripts\byok-profile.ps1 add

# Run Copilot CLI with a specific profile (one-off session)
.\scripts\byok-profile.ps1 run ollama

# Apply a profile to the current shell session (dot-source)
. .\scripts\byok-profile.ps1 set-env openai
```

Pass extra arguments to `copilot` when using `run`:

```powershell
.\scripts\byok-profile.ps1 run openai --model gpt-4o
```

### Kimi / Moonshot Shortcut

The profile manager includes a preset for Kimi providers:

- **Kimi Code** (`api.kimi.com/coding/v1`) — for https://www.kimi.com/code subscribers. Creates a profile named `kimicode`. Note: Kimi Code currently blocks Copilot CLI with `403 Forbidden` (agent whitelist), so this profile acts as a placeholder.
- **Moonshot Open Platform** (`api.moonshot.cn/v1` or `api.moonshot.ai/v1`) — for general Moonshot API users. Creates a profile named `kimi`.

```powershell
.\scripts\byok-profile.ps1 add
# Select preset 5) Kimi / Moonshot, then choose your option
```

Then run:

```powershell
# Moonshot Open Platform (works today)
.\scripts\byok-profile.ps1 run kimi

# Kimi Code (placeholder until Copilot CLI is whitelisted)
.\scripts\byok-profile.ps1 run kimicode
```

### Profile Storage

Profiles are stored in `~/.copilot/byok-profiles.json` (or `$COPILOT_HOME/byok-profiles.json`). The `apiKey` field supports `${ENV_VAR}` syntax so secrets are not hard-coded.

Example profile file:

```json
{
  "profiles": {
    "ollama": {
      "type": "openai",
      "baseUrl": "http://localhost:11434",
      "model": "llama3.2",
      "apiKey": null,
      "offline": true
    },
    "openai": {
      "type": "openai",
      "baseUrl": "https://api.openai.com/v1",
      "model": "gpt-4o",
      "apiKey": "${OPENAI_API_KEY}",
      "offline": false
    },
    "kimi": {
      "type": "openai",
      "baseUrl": "https://api.moonshot.cn/v1",
      "model": "kimi-k2.5",
      "apiKey": "${MOONSHOT_API_KEY}",
      "maxPromptTokens": 262144,
      "offline": false
    }
  }
}
```

### Convenience Alias

Add this to your PowerShell profile (`$PROFILE`) for quick access without typing the full path:

```powershell
function copilot-byok {
    param(
        [Parameter(Position = 0)] [string]$Command = 'list',
        [Parameter(Position = 1)] [string]$Name,
        [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Remaining
    )
    & C:\path\to\repo\skills\copilot-cli-byok\scripts\byok-profile.ps1 $Command $Name @Remaining
}
```

Then use it anywhere:

```powershell
copilot-byok run ollama
copilot-byok add
```

#### One-time setup helper

Run this from the repository root to auto-inject the alias into your PowerShell profile:

```powershell
$repoRoot = (Get-Location).Path
$aliasLine = @"

function copilot-byok {
    param(
        [Parameter(Position = 0)] [string]`$Command = 'list',
        [Parameter(Position = 1)] [string]`$Name,
        [Parameter(ValueFromRemainingArguments = `$true)] [string[]]`$Remaining
    )
    & `"$repoRoot\skills\copilot-cli-byok\scripts\byok-profile.ps1`" `$Command `$Name @Remaining
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

If you prefer invoking the script directly by name:

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

## Manual Configuration

If you prefer not to use the profile manager, set the environment variables directly before launching `copilot`.

See [references/providers.md](references/providers.md) for:
- Full environment variable reference
- Supported providers and model requirements
- Copy-paste examples for Ollama, OpenAI, Azure OpenAI, and Anthropic
- Offline mode guidance

## Troubleshooting

**Copilot CLI returns a model error on startup:**
- Confirm the model supports tool calling and streaming.
- Verify the model identifier matches exactly what the provider expects.

**Authentication errors:**
- Double-check `COPILOT_PROVIDER_API_KEY`.
- For Azure, ensure the full deployment URL is used as the base URL.

**Profile not found:**
- Verify the profile name exists in the JSON file (`list` command).
- Confirm the script resolves the correct config directory (`$env:COPILOT_HOME` or `~/.copilot`).

## References

- [GitHub Docs: Use BYOK models with Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models)
- [Copilot CLI MCP Config Skill](../copilot-cli-mcp-config/SKILL.md)
