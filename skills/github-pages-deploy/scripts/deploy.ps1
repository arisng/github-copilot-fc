[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [string]$Owner,

    [string]$Branch = 'gh-pages',

    [string]$CName,

    [switch]$NoWait
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Get-CommandOrFail {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        Fail "Required command not found: $Name"
    }

    return $command.Source
}

function Get-GitHubToken {
    if ($env:GITHUB_TOKEN) {
        return $env:GITHUB_TOKEN
    }

    if ($env:GH_TOKEN) {
        return $env:GH_TOKEN
    }

    Fail 'Set GITHUB_TOKEN or GH_TOKEN before running this script.'
}

function Invoke-GitHubApi {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Token,
        [object]$Body,
        [switch]$AllowNotFound,
        [switch]$PassThruStatus
    )

    $headers = @{
        Accept                 = 'application/vnd.github+json'
        Authorization          = "Bearer $Token"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'github-pages-deploy-skill'
    }

    $requestParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $requestParams.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        $requestParams.ContentType = 'application/json'
    }

    try {
        $response = Invoke-WebRequest @requestParams
        if ($PassThruStatus) {
            return [pscustomobject]@{
                StatusCode = [int]$response.StatusCode
                Content    = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
            }
        }

        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            return $null
        }

        return $response.Content | ConvertFrom-Json
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($AllowNotFound -and $statusCode -eq 404) {
            return $null
        }

        $details = ''
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $details = $reader.ReadToEnd()
            $reader.Dispose()
        }

        if ($details) {
            Fail "GitHub API request failed ($Method $Uri): $statusCode $details"
        }

        throw
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$WorkingDirectory = (Get-Location).Path,

        [switch]$AllowFailure
    )

    $output = & git @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $rendered = if ($output) { ($output | Out-String).Trim() } else { '' }
        Fail "git $($Arguments -join ' ') failed with exit code $exitCode`n$rendered"
    }

    return [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-RemoteBranchExists {
    param(
        [string]$RemoteUrl,
        [string]$BranchName,
        [string]$AuthHeader
    )

    $result = Invoke-Git -Arguments @('-c', "http.extraheader=$AuthHeader", 'ls-remote', '--heads', $RemoteUrl, $BranchName) -AllowFailure
    if ($result.ExitCode -ne 0) {
        return $false
    }

    return -not [string]::IsNullOrWhiteSpace(($result.Output | Out-String).Trim())
}

Get-CommandOrFail -Name 'git' | Out-Null

$token = Get-GitHubToken
$authUser = Invoke-GitHubApi -Method 'GET' -Uri 'https://api.github.com/user' -Token $token

$repoParts = $Repo.Split('/', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
if ($repoParts.Count -eq 2) {
    $resolvedOwner = $repoParts[0]
    $resolvedRepo = $repoParts[1]
}
else {
    $resolvedOwner = if ($Owner) { $Owner } else { $authUser.login }
    $resolvedRepo = $Repo
}

if (-not (Test-Path -LiteralPath $Path)) {
    Fail "Path not found: $Path"
}

$inputItem = Get-Item -LiteralPath $Path
if ($inputItem.PSIsContainer) {
    $inputMode = 'directory'
}
elseif ($inputItem.Extension -in '.html', '.htm') {
    $inputMode = 'html-file'
}
else {
    Fail 'Path must be a directory or a single .html/.htm file.'
}

$repoInfo = Invoke-GitHubApi -Method 'GET' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo" -Token $token -AllowNotFound
$createdRepo = $false

if ($null -eq $repoInfo) {
    Write-Info "Creating repository $resolvedOwner/$resolvedRepo..."

    $createBody = @{
        name     = $resolvedRepo
        private  = $false
        auto_init = $false
    }

    if ($resolvedOwner -eq $authUser.login) {
        $repoInfo = Invoke-GitHubApi -Method 'POST' -Uri 'https://api.github.com/user/repos' -Token $token -Body $createBody
    }
    else {
        $repoInfo = Invoke-GitHubApi -Method 'POST' -Uri "https://api.github.com/orgs/$resolvedOwner/repos" -Token $token -Body $createBody
    }

    $createdRepo = $true
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("github-pages-deploy-" + [System.Guid]::NewGuid().ToString('n'))
$stageDir = Join-Path $tempRoot 'stage'
$workDir = Join-Path $tempRoot 'work'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

try {
    if ($inputMode -eq 'directory') {
        Copy-DirectoryContents -Source $inputItem.FullName -Destination $stageDir
    }
    else {
        Copy-Item -LiteralPath $inputItem.FullName -Destination (Join-Path $stageDir 'index.html') -Force
    }

    $noJekyllPath = Join-Path $stageDir '.nojekyll'
    if (-not (Test-Path -LiteralPath $noJekyllPath)) {
        New-Item -ItemType File -Path $noJekyllPath -Force | Out-Null
    }

    if ($CName) {
        Set-Content -LiteralPath (Join-Path $stageDir 'CNAME') -Value $CName -NoNewline
    }

    $remoteUrl = "https://github.com/$resolvedOwner/$resolvedRepo.git"
    $basicAuthBytes = [System.Text.Encoding]::ASCII.GetBytes("x-access-token:$token")
    $basicAuthHeader = 'AUTHORIZATION: basic ' + [Convert]::ToBase64String($basicAuthBytes)

    if (Get-RemoteBranchExists -RemoteUrl $remoteUrl -BranchName $Branch -AuthHeader $basicAuthHeader) {
        Write-Info "Cloning existing branch $Branch..."
        Remove-Item -LiteralPath $workDir -Recurse -Force
        Invoke-Git -Arguments @('-c', "http.extraheader=$basicAuthHeader", 'clone', '--branch', $Branch, '--single-branch', $remoteUrl, $workDir) | Out-Null
        Get-ChildItem -LiteralPath $workDir -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
    }
    else {
        Write-Info "Creating branch $Branch..."
        Invoke-Git -Arguments @('-C', $workDir, 'init') | Out-Null
        Invoke-Git -Arguments @('-C', $workDir, 'checkout', '-b', $Branch) | Out-Null
        Invoke-Git -Arguments @('-C', $workDir, 'remote', 'add', 'origin', $remoteUrl) | Out-Null
    }

    Copy-DirectoryContents -Source $stageDir -Destination $workDir

    Invoke-Git -Arguments @('-C', $workDir, 'config', 'user.name', $authUser.login) | Out-Null
    Invoke-Git -Arguments @('-C', $workDir, 'config', 'user.email', "$($authUser.id)+$($authUser.login)@users.noreply.github.com") | Out-Null
    Invoke-Git -Arguments @('-C', $workDir, 'add', '--all') | Out-Null

    $status = Invoke-Git -Arguments @('-C', $workDir, 'status', '--porcelain')
    $hasChanges = -not [string]::IsNullOrWhiteSpace(($status.Output | Out-String).Trim())
    $commitSha = $null

    if ($hasChanges) {
        $message = "Deploy static site $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Invoke-Git -Arguments @('-C', $workDir, 'commit', '-m', $message) | Out-Null
        $commitSha = ((Invoke-Git -Arguments @('-C', $workDir, 'rev-parse', 'HEAD')).Output | Out-String).Trim()
        Write-Info "Pushing to $resolvedOwner/$resolvedRepo@$Branch..."
        Invoke-Git -Arguments @('-c', "http.extraheader=$basicAuthHeader", '-C', $workDir, 'push', '--set-upstream', 'origin', $Branch) | Out-Null
    }
    else {
        $commitSha = ((Invoke-Git -Arguments @('-C', $workDir, 'rev-parse', 'HEAD') -AllowFailure).Output | Out-String).Trim()
        Write-Info 'No file changes detected. Reusing current branch contents.'
    }

    $pagesBody = @{
        source = @{
            branch = $Branch
            path   = '/'
        }
    }

    if ($CName) {
        $pagesBody.cname = $CName
    }

    $pagesInfo = Invoke-GitHubApi -Method 'GET' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages" -Token $token -AllowNotFound
    if ($null -eq $pagesInfo) {
        Write-Info 'Configuring GitHub Pages...'
        $pagesInfo = Invoke-GitHubApi -Method 'POST' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages" -Token $token -Body $pagesBody
    }
    else {
        Write-Info 'Updating GitHub Pages configuration...'
        Invoke-GitHubApi -Method 'PUT' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages" -Token $token -Body $pagesBody | Out-Null
        $pagesInfo = Invoke-GitHubApi -Method 'GET' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages" -Token $token
    }

    $buildStatus = $null
    if (-not $NoWait) {
        Write-Info 'Waiting for GitHub Pages build...'
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 5
            $pagesInfo = Invoke-GitHubApi -Method 'GET' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages" -Token $token -AllowNotFound
            $latestBuild = Invoke-GitHubApi -Method 'GET' -Uri "https://api.github.com/repos/$resolvedOwner/$resolvedRepo/pages/builds/latest" -Token $token -AllowNotFound

            if ($latestBuild) {
                $buildStatus = $latestBuild.status
            }
            elseif ($pagesInfo) {
                $buildStatus = $pagesInfo.status
            }

            if ($buildStatus -in @('built', 'errored', 'error', 'failed')) {
                break
            }
        }
        while ((Get-Date) -lt $deadline)
    }

    $siteUrl = if ($pagesInfo.html_url) { $pagesInfo.html_url } elseif ($resolvedRepo -eq "$resolvedOwner.github.io") { "https://$resolvedOwner.github.io/" } else { "https://$resolvedOwner.github.io/$resolvedRepo/" }
    $repoUrl = $repoInfo.html_url
    if (-not $repoUrl) {
        $repoUrl = "https://github.com/$resolvedOwner/$resolvedRepo"
    }

    Write-Host ''
    Write-Success 'GitHub Pages deployment ready.'
    Write-Host "Site URL: $siteUrl" -ForegroundColor Green
    Write-Host "Repo URL: $repoUrl" -ForegroundColor Cyan
    Write-Host "Branch:   $Branch" -ForegroundColor Cyan
    if ($buildStatus) {
        Write-Host "Build:    $buildStatus" -ForegroundColor Cyan
    }
    Write-Host ''

    $result = [pscustomobject]@{
        siteUrl     = $siteUrl
        repoUrl     = $repoUrl
        owner       = $resolvedOwner
        repo        = $resolvedRepo
        branch      = $Branch
        createdRepo = $createdRepo
        pagesStatus = if ($pagesInfo) { $pagesInfo.status } else { $null }
        buildStatus = $buildStatus
        commitSha   = $commitSha
    }

    $result | ConvertTo-Json -Compress
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}