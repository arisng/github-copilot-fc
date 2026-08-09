# Multiple Accounts for the Same Provider (Copilot CLI)

Shared Copilot CLI mechanism, usable with any provider. When you hold multiple subscriptions for one provider (for example, **two OpenCode Zen accounts** with separate API keys), register them in the config and switch per session without editing profiles.

> VS Code does **not** read this registry — see [`shared/chat-language-models-json.md`](chat-language-models-json.md) for the VS Code equivalent (one provider entry per account).

## Config shape

`~/.copilot/byok-profiles.json`:

```json
{
  "accounts": {
    "opencode-home": { "keyEnv": "OPENCODE_API_KEY_HOME", "label": "OpenCode Zen (Home)" },
    "opencode-work": { "keyEnv": "OPENCODE_API_KEY_WORK", "label": "OpenCode Zen (Work)" }
  },
  "activeAccount": "opencode-home",
  "profiles": {
    "opencode-go-deepseek-v4-flash": {
      "baseUrl": "https://opencode.ai/zen/go/v1",
      "model": "deepseek-v4-flash",
      "type": "openai",
      "apiKey": "${OPENCODE_API_KEY_HOME}",
      "accountGroup": "opencode"
    }
  }
}
```

- `accounts.<name>.keyEnv` is the **name** of an environment variable holding that account's key. Raw keys are never stored in JSON.
- `activeAccount` selects the default account.
- `accountGroup` on a profile opts it into account resolution. Profiles without it are never affected. The `add` wizard (OpenCode Go preset) sets `accountGroup` automatically.

## Commands

| Command | Purpose |
|---------|---------|
| `byok-profile.ps1 accounts` | List registered accounts; mark the active one with `[active]`. |
| `byok-profile.ps1 use <account>` | Persist the default account. Errors on unknown names. |
| `byok-profile.ps1 run <profile> --account <account>` | Override the account for one session (both `--account <name>` and `--account=<name>` work). |
| `byok-profile.ps1 set-env <profile> --account <account>` | Apply the account override to the current shell. |

### Resolution order

`--account` flag → profile-level `account` pin → config-level `activeAccount` → `accounts[<name>].keyEnv`. When nothing resolves (no account selected, unknown account, or missing `keyEnv`), the profile falls back to its legacy `apiKey` placeholder and emits a warning.

### Sub-sessions

`Invoke-CopilotCliSubSession.ps1` (in the `copilot-cli-subsession` skill) supports the same lookup via `-ByokAccount <account>` (takes precedence over the profile pin and `activeAccount`). The resolved account is returned in the `ByokAccount` field of the result object.