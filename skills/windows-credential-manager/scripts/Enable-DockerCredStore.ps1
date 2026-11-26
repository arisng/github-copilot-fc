# Enable a Docker credential helper and migrate plaintext registry secrets into it.
# Backs up config.json first; leaves it untouched if any migration step fails.
[CmdletBinding()]
param(
    [ValidateSet('wincred', 'desktop', 'dpapi')]
    [string]$Helper = 'wincred',

    [switch]$SkipMigration
)

$ErrorActionPreference = 'Stop'

$configPath = Join-Path $env:USERPROFILE '.docker\config.json'
if (-not (Test-Path $configPath)) {
    throw "Docker config not found: $configPath"
}

$helperCmd = "docker-credential-$Helper"
if (-not (Get-Command $helperCmd -ErrorAction SilentlyContinue)) {
    throw "$helperCmd not found on PATH. Docker Desktop provides wincred/desktop; for dpapi run Install-DpapiHelper.ps1 from the windows-dpapi skill."
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Preflight: Windows Credential Manager caps credential blobs at 2560 bytes
# (measured: 2560 OK, 2561 fails), and both wincred and desktop helpers hit it
# on Windows. Oversized secrets make credsStore break 'docker login'.
# The dpapi helper stores in a file - no limit, skip the check.
$blobLimit = 2560
if ($Helper -ne 'dpapi' -and $config.auths) {
    foreach ($name in @($config.auths.PSObject.Properties.Name)) {
        $entry = $config.auths.PSObject.Properties[$name].Value
        if (-not $entry -or -not $entry.auth) { continue }
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($entry.auth))
        $colon = $text.IndexOf(':')
        if ($colon -lt 1) { continue }
        $secretLen = $text.Length - $colon - 1
        if ($secretLen -gt $blobLimit) {
            throw ("Secret for ${name} is $secretLen chars, over the $blobLimit-byte Windows Credential Manager limit. " +
                "Enabling credsStore would break 'docker login' with 'error saving credentials: ... The stub received bad data'. " +
                "Re-run with -Helper dpapi (windows-dpapi skill) or keep plaintext (tokens expire in ~12h). config.json not modified.")
        }
    }
}

$backupPath = '{0}.bak-{1}' -f $configPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item $configPath $backupPath -Force
Write-Host "Backup: $backupPath"

$migrated = 0
if (-not $SkipMigration -and $config.auths) {
    foreach ($name in @($config.auths.PSObject.Properties.Name)) {
        $entry = $config.auths.PSObject.Properties[$name].Value
        if (-not $entry -or -not $entry.auth) { continue } # already helper-managed

        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($entry.auth))
        $colon = $text.IndexOf(':')
        if ($colon -lt 1) {
            Write-Warning "Skipping ${name}: unexpected auth format (no 'user:secret' split)."
            continue
        }

        $payload = @{
            ServerURL = $name
            Username  = $text.Substring(0, $colon)
            Secret    = $text.Substring($colon + 1)
        } | ConvertTo-Json -Compress

        $payload | & $helperCmd store
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to store credential for '$name' via $helperCmd. config.json not modified."
        }

        [void]$config.auths.PSObject.Properties.Remove($name)
        $migrated++
        Write-Host "Migrated: $name -> $helperCmd"
    }
}

if ($config.PSObject.Properties['credsStore']) {
    $config.credsStore = $Helper
}
else {
    $config | Add-Member -NotePropertyName credsStore -NotePropertyValue $Helper
}

$json = $config | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($configPath, $json, (New-Object Text.UTF8Encoding($false)))

Write-Host "credsStore set to '$Helper'. Migrated $migrated plaintext entr$(if ($migrated -eq 1) { 'y' } else { 'ies' })."
