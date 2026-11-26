---
name: windows-dpapi
description: Encrypt and decrypt secrets for the current Windows user with DPAPI (Data Protection API, ProtectedData/CryptProtectData). Use when storing API keys, tokens or passwords encrypted in files instead of plaintext on Windows, when a secret exceeds Windows Credential Manager's 2560-byte limit (e.g. long ECR tokens used as Docker credsStore), when docker login/build fails with docker-credential-dpapi executable file not found (helper installed but its dir off PATH), or when asked to DPAPI-encrypt/decrypt data, protect config-file secrets, or convert secrets with ConvertFrom-SecureString without a key.
metadata:
  version: 1.0.1
  author: arisng
---

# Windows DPAPI

Encrypt data bound to the **current Windows user + machine** — no keys to manage, ciphertext only on disk, readable solely by that account. Windows Credential Manager itself uses DPAPI internally.

API: `[System.Security.Cryptography.ProtectedData]` after `Add-Type -AssemblyName System.Security` (scripts pin `powershell.exe` 5.1, where the assembly ships in-box).

## Recipes

```powershell
# Protect -> base64 ; Unprotect -> plaintext
$b64   = [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect(
             [Text.Encoding]::UTF8.GetBytes($secret), $null, 'CurrentUser'))
$plain = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
             [Convert]::FromBase64String($b64), $null, 'CurrentUser'))

# One-liner alternative (also DPAPI under the hood)
$enc    = ConvertTo-SecureString $secret -AsPlainText -Force | ConvertFrom-SecureString   # hex blob
$secure = ConvertTo-SecureString $enc                                                      # reverse
```

## Gotchas

- Scope: `CurrentUser` (default, safest) vs `LocalMachine` (any local account can decrypt).
- Not portable by design: ciphertext fails on another machine or account.
- No size limit — unlike Credential Manager's 2560-byte blob per entry.
- Keep the impl script named `docker-credential-dpapi-impl.ps1`, **not** `docker-credential-dpapi.ps1`: PowerShell would resolve the bare command to the `.ps1` and bind stdin via the pipeline (breaking console stdin), so only the `.cmd` may match the command name — Docker (Go) and PowerShell then share one execution path.
- Harness/agent shells often lack `%USERPROFILE%\.local\bin` on PATH even though the helper is installed — prepend it before diagnosing further (same class of gap as a missing task runner or `pwsh` on PATH).
- `pwsh` 7 needs the `System.Security.Cryptography.ProtectedData` package; use Windows PowerShell 5.1 for portable scripts.

## Docker credential helper (Credential Manager escape hatch)

For `credsStore` when registry tokens exceed 2560 chars (ECR): a helper storing secrets DPAPI-encrypted in `<store-dir>\dpapi-store.json` — same `store/get/erase/list` protocol, no size cap.

1. Install: `~/.agents/skills/windows-dpapi/scripts/Install-DpapiHelper.ps1` — copies the helper onto a PATH directory (prefers `%USERPROFILE%\.local\bin`, otherwise `%USERPROFILE%\.docker\bin` + user PATH registration). Add `-NoPathUpdate` to copy the files only, leaving the registry and the user PATH untouched — the safe mode for a smoke test or a throwaway install.
2. Migrate: run `~/.agents/skills/windows-credential-manager/scripts/Enable-DockerCredStore.ps1 -Helper dpapi`.
3. Verify: re-run the registry login (`docker login <registry>`, or whatever task wraps it) → `Login Succeeded` **without** the unencrypted-credentials warning; `dpapi-store.json` must contain ciphertext only.
