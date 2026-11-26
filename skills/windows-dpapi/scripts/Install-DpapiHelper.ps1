# Install the docker-credential-dpapi helper onto a directory that is (or becomes) on PATH.
[CmdletBinding()]
param(
    # Override the install directory; must be on PATH or it will be added to the user PATH.
    [string]$InstallDir,

    # Copy the helper files only: touch neither the registry nor the user PATH.
    # Use for smoke tests and throwaway installs - the default writes a
    # persistent per-user environment change that outlives the process.
    [switch]$NoPathUpdate
)

$ErrorActionPreference = 'Stop'
$skillScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE '.local\bin' }

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
foreach ($file in 'docker-credential-dpapi-impl.ps1', 'docker-credential-dpapi.cmd') {
    Copy-Item (Join-Path $skillScripts $file) $InstallDir -Force
}

if ($NoPathUpdate) {
    Write-Host "Copied docker-credential-dpapi -> $InstallDir (PATH unchanged: -NoPathUpdate)"
    Write-Host "Add it to PATH yourself, or re-run without -NoPathUpdate, to invoke the helper by name."
    exit 0
}

$normalized = { param($list) @($list | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }) }

# Make it visible to this session.
if ((& $normalized ($env:Path -split ';')) -notcontains $InstallDir.TrimEnd('\')) {
    $env:Path += ';' + $InstallDir
}

# Make it visible to future terminals (preserve value kind; REG_EXPAND_SZ stays expandable).
$addedToRegistry = $false
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
if ($null -eq $key) { $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment') }
$exists = $key.GetValueNames() -contains 'Path'
$raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
if ((& $normalized ($raw -split ';')) -notcontains $InstallDir.TrimEnd('\')) {
    $kind = if ($exists) { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::String }
    $newRaw = if ([string]::IsNullOrWhiteSpace($raw)) { $InstallDir } else { $raw.TrimEnd(';') + ';' + $InstallDir }
    $key.SetValue('Path', $newRaw, $kind)
    $addedToRegistry = $true
}
$key.Close()

if ($addedToRegistry) {
    # Broadcast WM_SETTINGCHANGE so Explorer-launched terminals pick up the new PATH.
    Add-Type -Namespace Win32 -Name Broadcast -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $result = [UIntPtr]::Zero
    [void][Win32.Broadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    Write-Host "Added to user PATH: $InstallDir (new terminals pick it up; restart already-open terminals like VS Code)"
}

if (-not (Get-Command docker-credential-dpapi -ErrorAction SilentlyContinue)) {
    throw "docker-credential-dpapi not resolvable on PATH after install to $InstallDir"
}
Write-Host "Installed docker-credential-dpapi -> $InstallDir"
