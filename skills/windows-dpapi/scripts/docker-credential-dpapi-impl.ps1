# Docker credential-helper protocol (store/get/erase/list) backed by DPAPI.
# Secrets are encrypted for the current Windows user - no 2560-byte vault limit.
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Security

$storePath = Join-Path $env:USERPROFILE '.docker\dpapi-store.json'

function Find-StoreEntry([object]$Store, [string]$ServerUrl) {
    $prop = $Store.PSObject.Properties[$ServerUrl]
    if ($prop) { return $prop }
    # The helper protocol passes "host", "host:port" or "https://host/v1/" forms for the
    # same registry; compare on the bare host so lookups stay stable across forms.
    $normalized = (($ServerUrl -replace '^https?://', '') -split '/')[0].TrimEnd(':')
    foreach ($p in $Store.PSObject.Properties) {
        $key = (($p.Name -replace '^https?://', '') -split '/')[0].TrimEnd(':')
        if ($key -ieq $normalized) { return $p }
    }
    return $null
}

function Protect-Secret([string]$Secret) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Secret)
    [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser'))
}

function Unprotect-Secret([string]$Blob) {
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Blob), $null, 'CurrentUser')
    [Text.Encoding]::UTF8.GetString($bytes)
}

function Read-Store {
    if (-not (Test-Path $storePath)) { return [pscustomobject]@{} }
    $raw = Get-Content $storePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    $raw | ConvertFrom-Json
}

function Write-Store([object]$Store) {
    $json = $Store | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($storePath, $json, (New-Object Text.UTF8Encoding($false)))
}

$exitCode = 0
try {
    $request = $null
    if ($Command -ne 'list') {
        $stdin = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($stdin)) {
            [Console]::Error.WriteLine('docker-credential-dpapi: missing request payload on stdin')
            $exitCode = 1
        }
        else {
            if ($Command -eq 'store') {
                # store receives a JSON payload: { "ServerURL", "Username", "Secret" }.
                $request = $stdin | ConvertFrom-Json
            }
            else {
                # get/erase receive the server URL as plain text (credential-helper protocol).
                $request = [pscustomobject]@{ ServerURL = $stdin.Trim() }
            }
        }
    }

    if ($exitCode -eq 0) {
        switch ($Command) {
            'store' {
                $store = Read-Store
                $entry = [pscustomobject]@{
                    Username = $request.Username
                    Blob     = Protect-Secret $request.Secret
                }
                if ($store.PSObject.Properties[$request.ServerURL]) {
                    $store.PSObject.Properties[$request.ServerURL].Value = $entry
                }
                else {
                    $store | Add-Member -NotePropertyName $request.ServerURL -NotePropertyValue $entry
                }
                Write-Store $store
            }
            'get' {
                $store = Read-Store
                $prop = Find-StoreEntry $store $request.ServerURL
                if (-not $prop) {
                    # Docker special-cases this exact message on STDOUT (docker-credential-wincred's
                    # convention) to fall back to anonymous access instead of failing the request.
                    [Console]::Out.WriteLine('credentials not found in native keychain')
                    [Console]::Error.WriteLine('credentials not found in native keychain')
                    $exitCode = 1
                }
                else {
                    [pscustomobject]@{
                        ServerURL = $request.ServerURL
                        Username  = $prop.Value.Username
                        Secret    = Unprotect-Secret $prop.Value.Blob
                    } | ConvertTo-Json -Compress
                }
            }
            'erase' {
                $store = Read-Store
                $prop = Find-StoreEntry $store $request.ServerURL
                if ($prop) {
                    [void]$store.PSObject.Properties.Remove($request.ServerURL)
                    Write-Store $store
                }
            }
            'list' {
                $store = Read-Store
                $map = [ordered]@{}
                foreach ($prop in $store.PSObject.Properties) { $map[$prop.Name] = $prop.Value.Username }
                [pscustomobject]$map | ConvertTo-Json -Compress
            }
            default {
                [Console]::Error.WriteLine("docker-credential-dpapi: unknown command '$Command'")
                $exitCode = 1
            }
        }
    }
}
catch {
    [Console]::Error.WriteLine("docker-credential-dpapi: $($_.Exception.Message)")
    $exitCode = 1
}
exit $exitCode
