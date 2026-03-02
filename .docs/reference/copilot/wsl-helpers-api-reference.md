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

Quick reference for the shared WSL utility at `scripts/publish/wsl-helpers.ps1`. Provides 4 functions for cross-platform publish script WSL integration.

## Import

```powershell
. "$PSScriptRoot/wsl-helpers.ps1"
```

Must be dot-sourced at the script level (before function definitions that use it).

## Functions

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

**Detection pattern:** `wsl bash -c 'echo $HOME'` with try/catch + `$LASTEXITCODE` check. Returns `$false` gracefully when WSL is not installed.

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
- Auto-creates parent directories via `mkdir -p`
- Auto-removes existing target before copy (idempotent overwrite)
- `-Recurse` selects between file mode and directory mode for the WSL test/copy/remove commands
- Uses `Write-Warning` on failure (non-terminating)

**When to use `-Recurse`:**
