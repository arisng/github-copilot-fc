---
name: windows-credential-manager
description: Store CLI/tool secrets in Windows Credential Manager instead of plaintext files on Windows. Use when Docker warns "Your credentials are stored unencrypted in config.json", when configuring credsStore or docker-credential-wincred/docker-credential-desktop, when migrating plaintext registry tokens (ECR, Docker Hub, ACR, GCR) out of .docker config.json, when auditing or deleting stored credentials with cmdkey, or whenever a request asks to keep tool secrets out of plaintext JSON/config files on Windows.
metadata:
  version: 1.0.0
  author: arisng
---

# Windows Credential Manager

Keep secrets in the OS secure store instead of plaintext config files. Tools plug in on Windows via credential-helper executables named `docker-credential-<helper>`; `cmdkey` is the built-in CLI for listing/deleting entries.

## Locations

| Item | Path |
|---|---|
| Docker config (plaintext risk) | `%USERPROFILE%\.docker\config.json` |
| Helpers (Docker Desktop) | `C:\Program Files\Docker\Docker\resources\bin\docker-credential-{wincred,desktop}.exe` |
| The store itself | OS Credential Manager — inspect with `cmdkey /list` |

## Workflow: enable Docker credential store

1. **Detect**: warning `Your credentials are stored unencrypted`, or plaintext `auths` values in `config.json`.
2. **Pick helper**: `wincred` → Windows Credential Manager (the usual default); `desktop` → Docker Desktop's store (on Windows this *is* Credential Manager — same 2560-byte limit); `dpapi` → DPAPI-encrypted file, **no size limit** — install first via the [windows-dpapi](../windows-dpapi/SKILL.md) skill. Confirm with `Get-Command docker-credential-wincred`.
3. **Migrate + enable**: run `scripts/Enable-DockerCredStore.ps1 -Helper wincred`. It preflights token sizes against the 2560-byte credential limit (refusing unsafe configs), backs up `config.json`, moves every plaintext `auths` secret into the helper, sets `credsStore`, and rewrites the file (UTF-8, no BOM) preserving `currentContext`/`plugins`/`features`.
4. **Re-login**: re-run the original login (e.g. `docker login <registry>`, or the task/build command that wraps it). Expect `Login Succeeded` with no warning.
5. **Verify**: `cmdkey /list | findstr /i ecr` shows entries; `config.json` has `"credsStore"` and an empty `auths`.

## Script options

- `-Helper wincred|desktop|dpapi` — helper to use (default `wincred`).
- `-SkipMigration` — only set `credsStore`, leave existing plaintext entries in place.
- Refuses to run when any plaintext secret exceeds 2560 chars and the helper is `wincred`/`desktop` (see gotchas); `dpapi` skips that check.

## Gotchas

- **2560-byte blob limit** (measured: 2560 ✓ / 2561 ✗). On Windows the `desktop` helper delegates to Credential Manager too — same limit. Oversized secrets (e.g. ECR tokens of 2960+ chars) make `credsStore` **break `docker login`**: `error saving credentials: ... The stub received bad data.` — verify token size before enabling; options are staying plaintext (tokens expire ~12 h anyway) or the DPAPI helper from the [windows-dpapi](../windows-dpapi/SKILL.md) skill (`-Helper dpapi`).
- `auths` values are `base64("user:secret")`; split at the **first** colon.
- ECR tokens expire after 12 h — re-run login instead of debugging `unauthorized`.
- Never commit `config.json`; after migration it holds no secrets but still has machine-specific config.
- `cmdkey /delete /name:<target>` removes an entry; `cmdkey` cannot add credentials non-interactively — helpers do that.
