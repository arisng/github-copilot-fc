# API Key Storage Guide

Never paste real API keys directly into `byok-profiles.json`. The `apiKey` field supports `${ENV_VAR}` syntax — the profile manager resolves the variable at runtime.

Use an environment variable placeholder in your profile:

```json
"apiKey": "${OPENAI_API_KEY}"
```

## Ways to Store Keys Persistently (User Scope, Windows)

Four options from simplest to most complex:

| # | Method | Persistent | Survives shell restart | Setup effort |
|---|--------|------------|----------------------|--------------|
| 1 | PowerShell .NET API | Yes (User scope) | Yes | One command per key |
| 2 | `setx` command | Yes (User scope) | Yes | One command per key |
| 3 | Windows UI (System Properties) | Yes (User scope) | Yes | Manual, no scripting |
| 4 | `$PROFILE` export block | Effective per shell | Yes (re-runs on startup) | Edit profile file |

## Recommended: PowerShell .NET API (Option 1)

Simplest one-shot setup. Run once per key, then restart your terminal or VS Code.

```powershell
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "<your-real-key>", "User")
[Environment]::SetEnvironmentVariable("MOONSHOT_API_KEY", "<your-real-key>", "User")
```

Verify the keys are stored:

```powershell
[Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "User")
[Environment]::GetEnvironmentVariable("MOONSHOT_API_KEY", "User")
```

> **Security note:** The value is stored in the Windows registry under `HKCU\Environment` and is visible to any process running as your user. Do not share registry exports or system snapshots that include this hive.

## Option 2: setx

Works from any terminal (cmd or pwsh). Note: `setx` caps values at 1024 characters.

```powershell
setx OPENAI_API_KEY "<your-real-key>"
setx MOONSHOT_API_KEY "<your-real-key>"
```

Restart your terminal after running — `setx` does not update the current shell session.

## Option 3: Windows UI

1. Open **Start → Search** for "Edit the system environment variables".
2. Click **Environment Variables…**.
3. Under **User variables**, click **New**.
4. Set Variable name: `OPENAI_API_KEY` and Variable value: `<your-real-key>`.
5. Repeat for other keys.
6. Click OK and restart any open terminals.

## Option 4: PowerShell Profile Script

Useful when you rotate keys often or prefer a single editable file. Keys are re-set on every new shell.

Open your profile:

```powershell
code $PROFILE
```

Add at the end:

```powershell
$env:OPENAI_API_KEY   = "<your-real-key>"
$env:MOONSHOT_API_KEY = "<your-real-key>"
```

> **Important:** `$PROFILE` is a plain text file. Avoid committing it to any repository. Consider encrypting the file or using Windows Credential Manager for higher-assurance setups.

## Key Rotation

To update or remove a key set with Option 1 or 2:

```powershell
# Update
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "<new-key>", "User")

# Remove
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $null, "User")
```

Restart your terminal after any change.

## Checklist

- [ ] Profile JSON uses `${ENV_VAR}` placeholder, not a raw key.
- [ ] Key is stored at User scope (not Machine scope, which requires admin).
- [ ] Terminal/VS Code restarted after setting the variable.
- [ ] `byok-profile.ps1 show <profile>` shows `apiKey` as the placeholder, not the resolved value.
