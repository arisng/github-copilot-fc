# Start the Moonshot top_p fix proxy
# Auto-elevates to admin so port 443 (clean URL, no port number) can bind.
# Cert data is stored in ~/.copilot/moonshot-proxy/

$proxyDir = Join-Path $HOME '.copilot' 'moonshot-proxy'
$pfxPath = Join-Path $proxyDir 'moonshot.pfx'
$certPfx = Join-Path $proxyDir 'cert.pfx'
$proxyJs = Join-Path $PSScriptRoot 'proxy.js'

# Elevate if not admin (required for port 443)
$isAdmin = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'
if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell"
    $psi.Verb = "RunAs"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.UseShellExecute = $true
    Start-Process -FilePath $psi.FileName -ArgumentList $psi.Arguments -Verb RunAs
    exit
}

# Ensure data dir exists
if (-not (Test-Path $proxyDir)) { New-Item -ItemType Directory -Path $proxyDir -Force | Out-Null }

# Ensure a cert exists
if (-not (Test-Path $pfxPath) -and -not (Test-Path $certPfx)) {
    Write-Host "Exporting .NET dev certificate..." -ForegroundColor Yellow
    dotnet dev-certs https --export-path "$certPfx" --password proxy --format Pfx
}

# Validate proxy.js exists
if (-not (Test-Path $proxyJs)) {
    Write-Error "proxy.js not found at $proxyJs"
    exit 1
}

# Kill existing proxies on our ports
foreach ($port in @(3002, 443)) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($conn) { Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
}

# Start proxy
Start-Process -NoNewWindow -FilePath "node" -ArgumentList "`"$proxyJs`""
Start-Sleep 2

# Verify
if ((Get-NetTCPConnection -LocalPort 3002 -ErrorAction SilentlyContinue).State -eq 'Listen') {
    Write-Host "✅ Proxy on https://moonshot.local:3002" -ForegroundColor Green
    if ((Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue).State -eq 'Listen') {
        Write-Host "✅ Also on https://moonshot.local (no port!)" -ForegroundColor Green
    }
} else {
    Write-Host "❌ Proxy failed to start" -ForegroundColor Red
}
