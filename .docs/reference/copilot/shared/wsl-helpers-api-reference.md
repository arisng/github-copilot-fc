---
category: reference
source_session: 260302-001737
source_iteration: 2
source_artifacts:
  - "Iteration 2 task-2 (WSL utility extraction)"
  - "Iteration 2 task-2 report"
  - "Iteration 2 task-4 report"
extracted_at: 2026-03-02T12:35:33+07:00
promoted: true
promoted_at: 2026-03-02T12:41:22+07:00
---

# wsl-helpers.ps1 API Reference

Quick reference for the shared WSL utility at `scripts/publish/wsl-helpers.ps1`. The module now provides 5 functions for cross-platform publish script WSL integration, including deterministic command execution for Node-dependent CLI tools.

## Import

```powershell
. "$PSScriptRoot/wsl-helpers.ps1"
```

Must be dot-sourced at the script level (before function definitions that use it).

## Functions

### Invoke-WSLCommand

Runs a Bash command inside WSL using a temporary script file.

```powershell
Invoke-WSLCommand [-Command] <string> [-InitializeNode] [-SuppressStderr]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Command` | String | Yes | Bash command text to execute |
| `-InitializeNode` | Switch | No | Loads `nvm` from `$HOME/.nvm/nvm.sh` and activates the default alias before running the command |
| `-SuppressStderr` | Switch | No | Redirects WSL stderr to `$null` |

| Return | Type | Description |
|--------|------|-------------|
| stdout | String | Any stdout emitted by the WSL command |

**Behavior:**
- Writes a temporary UTF-8 no-BOM Bash script with LF line endings
- Executes the script via `wsl bash <script>` to avoid PowerShell-to-WSL inline quoting issues
- Keeps Node bootstrap opt-in via `-InitializeNode` so file-copy operations stay lightweight

**When to use:**
- Use for WSL commands that need deterministic shell behavior
- Use `-InitializeNode` for `copilot` CLI invocations or any command that depends on `nvm`
- Prefer this over raw `wsl bash -c ...` in publish scripts

### Test-WSLAvailable

Detects whether WSL is available and returns the WSL home directory.

```powershell
Test-WSLAvailable [-WslHome <ref>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-WslHome` | `[ref]` | No | Reference variable populated with WSL `$HOME` path (e.g., `/home/username`) |

| Return | Type | Description |
|--------|------|-------------|
| `$true` | Boolean | WSL available, `$WslHome` populated |
| `$false` | Boolean | WSL unavailable, no exception thrown |

**Detection pattern:** delegates to `Invoke-WSLCommand -Command 'echo $HOME' -SuppressStderr` with `$LASTEXITCODE` check. Returns `$false` gracefully when WSL is not installed.

**Usage:**
```powershell
$wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
if ($wslAvailable) {
    Write-Host "WSL home: $wslHome"
}
```

### Convert-ToWSLPath

Converts a Windows filesystem path to a WSL mount path.

```powershell
Convert-ToWSLPath [-Path] <string>
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Path` | String | Yes | Windows path (e.g., `C:\Users\admin\file.md`) |

| Return | Type | Description |
|--------|------|-------------|
| WSL path | String | Mount path (e.g., `/mnt/c/Users/admin/file.md`) |

Handles any drive letter (not just `C:`). Uses regex replacement for the drive prefix and backslash-to-forward-slash conversion.

### Copy-ToWSL

Copies a file or directory from the Windows filesystem to a WSL path.

```powershell
Copy-ToWSL [-Source] <string> [-Destination] <string> [-Recurse]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Source` | String | Yes | Windows source path |
| `-Destination` | String | Yes | WSL target path |
| `-Recurse` | Switch | No | Use directory mode (`test -d`, `cp -r`, `rm -rf`) instead of file mode (`test -f`, `cp`, `rm -f`) |

| Return | Type | Description |
|--------|------|-------------|
| `$true` | Boolean | Copy succeeded |
| `$false` | Boolean | Copy failed (warning written, no terminating error) |

**Behavior:**
- Auto-creates parent directories via `Invoke-WSLCommand`
- Auto-removes existing target before copy (idempotent overwrite)
- `-Recurse` selects between file mode and directory mode for the WSL test/copy/remove commands
- Uses `Write-Warning` on failure (non-terminating)
- Uses the shared command transport, so path-sensitive WSL operations no longer depend on inline command quoting

**When to use `-Recurse`:**
- Omit `-Recurse` for single files such as `.agent.md` artifacts
- Use `-Recurse` for directories such as skill folders

### Remove-FromWSL

Removes a file or directory from WSL.

```powershell
Remove-FromWSL [-Path] <string> [-Recurse]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Path` | String | Yes | WSL path to remove |
| `-Recurse` | Switch | No | Use directory mode (`rm -rf`) instead of file mode (`rm -f`) |

| Return | Type | Description |
|--------|------|-------------|
| `$true` | Boolean | Removal succeeded |
| `$false` | Boolean | Removal failed (warning written, no terminating error) |

**Behavior:**
- Delegates to `Invoke-WSLCommand`
- Uses non-terminating warnings so publish scripts can continue processing other artifacts
- Supports both file and directory cleanup through the `-Recurse` switch

## Notes

- Use `Invoke-WSLCommand -InitializeNode` only for commands that truly need a Node-managed runtime.
- Keep raw filesystem publishing on `Copy-ToWSL` and `Remove-FromWSL`; they already use the shared transport and avoid unnecessary shell bootstrap.
- Prefer helper reuse over script-local WSL command wrappers so fixes land once and propagate to all publish scripts.

## Related

- [How to Publish Customizations for Copilot CLI](../../../../how-to/copilot/cli/how-to-publish-customizations-for-copilot-cli.md)
- [How to Add Multi-Runtime Support to a Publish Script](../../../../how-to/copilot/shared/how-to-add-multi-runtime-support-to-publish-scripts.md)
- [Why WSL Publishing Broke from PowerShell and What Fixed It](../../../../explanation/copilot/shared/wsl-publish-shell-bootstrap-lessons.md)
