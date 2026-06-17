# Setup: moonshot.local DNS entry + trusted certificate
# Requires admin (elevates automatically)
# Cert data is stored in ~/.copilot/moonshot-proxy/

$proxyDir = Join-Path $HOME '.copilot' 'moonshot-proxy'
$hostname = "moonshot.local"
$pfxPath = Join-Path $proxyDir "moonshot.pfx"
$pfxPass = "proxy"

# Detect if running as admin
$isAdmin = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'
if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "RunAs"
    $psi.UseShellExecute = $true
    Start-Process -FilePath $psi.FileName -ArgumentList $psi.Arguments -Verb RunAs
    exit
}

# Ensure data dir exists
if (-not (Test-Path $proxyDir)) { New-Item -ItemType Directory -Path $proxyDir -Force | Out-Null }

Write-Host "=== Setting up $hostname for Moonshot Proxy ===" -ForegroundColor Cyan

# 1. Generate and trust cert for moonshot.local
Write-Host "[1/3] Generating SSL certificate for $hostname..." -ForegroundColor Yellow
$cert = New-SelfSignedCertificate -DnsName $hostname -CertStoreLocation "cert:\LocalMachine\My" -FriendlyName "Moonshot Proxy" -NotAfter (Get-Date).AddYears(5)
$thumbprint = $cert.Thumbprint
Write-Host "  Certificate thumbprint: $thumbprint" -ForegroundColor Gray

# Export PFX (with private key)
$securePass = ConvertTo-SecureString -String $pfxPass -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePass | Out-Null
Write-Host "  Exported to: $pfxPath" -ForegroundColor Gray

# Trust it in the Root store (so VS Code accepts it)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', 'LocalMachine'
$store.Open('ReadWrite')
$store.Add($cert)
$store.Close()
Write-Host "  Certificate trusted for: https://$hostname" -ForegroundColor Green

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
Write-Host "   Use: https://$hostname in your proxy configs" -ForegroundColor Cyan
Write-Host "   PFX: $pfxPath" -ForegroundColor Gray
Write-Host "   Run start-proxy.ps1 to start the proxy" -ForegroundColor Gray
