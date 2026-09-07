#Requires -Version 7.0
# Setup: opencode-go.local DNS entry + trusted certificate
# Requires admin (elevates automatically)
# Generates a combined cert with both moonshot.local AND opencode-go.local

$proxyDir = Join-Path $HOME '.copilot' 'moonshot-proxy'
$hostname = "opencode-go.local"
$pfxPath = Join-Path $proxyDir "moonshot.pfx"
$pfxPass = "proxy"

# Detect if running as admin
$isAdmin = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'
if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "RunAs"
    $psi.UseShellExecute = $true
    Start-Process -FilePath $psi.FileName -ArgumentList $psi.Arguments -Verb RunAs
    exit
}

# Ensure data dir exists
if (-not (Test-Path $proxyDir)) { New-Item -ItemType Directory -Path $proxyDir -Force | Out-Null }

Write-Host "=== Setting up $hostname for OpenCode Go Proxy ===" -ForegroundColor Cyan

# 1. Generate combined cert with BOTH moonshot.local AND opencode-go.local
Write-Host "[1/3] Generating SSL certificate for moonshot.local + $hostname ..." -ForegroundColor Yellow
$cert = New-SelfSignedCertificate -DnsName 'moonshot.local', $hostname -CertStoreLocation "cert:\LocalMachine\My" -FriendlyName "Proxy Cert (Moonshot + OpenCode Go)" -NotAfter (Get-Date).AddYears(5)
$thumbprint = $cert.Thumbprint
Write-Host "  Certificate thumbprint: $thumbprint" -ForegroundColor Gray
Write-Host "  SANs: moonshot.local, $hostname" -ForegroundColor Gray

# Export PFX (with private key)
$securePass = ConvertTo-SecureString -String $pfxPass -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePass | Out-Null
Write-Host "  Exported to: $pfxPath" -ForegroundColor Gray

# Trust it in the Root store (so VS Code accepts it)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', 'LocalMachine'
$store.Open('ReadWrite')
$store.Add($cert)
$store.Close()
Write-Host "  Certificate trusted" -ForegroundColor Green

# 2. Add hosts entry
Write-Host "[2/3] Adding hosts entry 127.0.0.1 $hostname ..." -ForegroundColor Yellow
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsPath -Raw
if ($hostsContent -match [regex]::Escape($hostname)) {
    Write-Host "  Already exists in hosts file" -ForegroundColor Gray
} else {
    Add-Content -Path $hostsPath -Value "`n127.0.0.1`t$hostname`n::1`t$hostname" -Encoding UTF8
    Write-Host "  Added $hostname -> 127.0.0.1" -ForegroundColor Green
}

Write-Host "[3/3] Verifying..." -ForegroundColor Yellow
$resolved = Resolve-DnsName $hostname -ErrorAction SilentlyContinue
if ($resolved) {
    Write-Host "  DNS resolves: $($resolved.IPAddress)" -ForegroundColor Green
} else {
    Write-Host "  ⚠ DNS check failed, but hosts entry should still work" -ForegroundColor Yellow
}

Start-Sleep 2
Write-Host ""
Write-Host "✅ Setup complete!" -ForegroundColor Green
Write-Host "   Cert covers: moonshot.local + $hostname" -ForegroundColor Cyan
Write-Host "   PFX: $pfxPath" -ForegroundColor Gray
Write-Host "   Restart both proxies for the new cert to take effect." -ForegroundColor Yellow
