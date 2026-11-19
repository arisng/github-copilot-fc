# Shared issue-id helpers for the issue-tracking skill (dot-sourced, no params,
# no side effects). Scope: the local-markdown tracker only.
#
# Collision model: ids are allocated from the store (active NNNN-*.md +
# archived) PLUS outstanding leases. A lease is an exclusively-created file in
# a lease store chosen by identity strength:
#   1. <temp>/issue-id-leases/<sha1(origin url)> - keyed by the repo's
#      normalized remote URL, so every worktree AND every clone of this repo on
#      this machine (same OS user) shares one reservation pool;
#   2. no remote configured -> <git common dir>/issue-id-leases - shared by all
#      worktrees of this clone;
#   3. no git at all -> per-repo-root temp bucket.
# Two racing sessions on one machine can therefore never be handed the same id.
# Leases expire after -TtlHours (default 24h) so a crashed session's reservation
# is reclaimed. Isolated machines cannot see each other's uncommitted work; there
# the always-on duplicate-id lint (the repo's issue lint / pre-commit gate) refuses to let
# a collision land, and the skill's cross-machine resolution protocol (SKILL.md
# step 5) re-allocates the losing id before pushing.

function Get-ShortSha1 {
    param([string]$Text, [int]$Length = 16)
    $norm = $Text.ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', '').ToLowerInvariant()
    return $hash.Substring(0, [Math]::Min($Length, $hash.Length))
}

function Get-RepoOriginUrl {
    # Normalized origin URL (userinfo stripped so credential styles don't split
    # the lease pool), or $null when git/origin is unavailable.
    param([string]$RepoRoot = (Get-Location).Path)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($out -join ''))) { return $null }
    }
    catch { return $null }
    finally { $ErrorActionPreference = $prev }
    $url = ($out -join '').Trim()
    $url = $url -replace '^(https?://)[^/@]+@', '$1'
    return $url
}

function Get-IssueIdLeaseDir {
    # Lease store: machine-shared URL-keyed bucket first (worktrees + clones of
    # this repo on this machine), git common dir second, per-root temp last.
    param([string]$RepoRoot = (Get-Location).Path)

    $originUrl = Get-RepoOriginUrl -RepoRoot $RepoRoot
    if ($originUrl) {
        $key = Get-ShortSha1 -Text $originUrl
        return (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "issue-id-leases/$key")
    }

    $gitDir = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = & git -C $RepoRoot rev-parse --git-common-dir 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($out -join ''))) {
                $gitDir = ($out -join '').Trim()
            }
        }
        catch { $gitDir = $null }
        finally { $ErrorActionPreference = $prev }
    }
    if ($gitDir) {
        if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
            $gitDir = Join-Path -Path $RepoRoot -ChildPath $gitDir
        }
        return (Join-Path -Path $gitDir -ChildPath 'issue-id-leases')
    }

    # Not a git repo: per-repo-root bucket under temp (still atomic per machine).
    $norm = $RepoRoot.TrimEnd('\', '/').ToLowerInvariant()
    return (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "issue-id-leases/root-$(Get-ShortSha1 -Text $norm)")
}

function Get-IssueIdLeases {
    # Reads *.lease files: id -> @{ Path; CreatedUtc; Host; Worktree }.
    # Expired leases are returned separately so the caller can prune them.
    param(
        [string]$LeaseDir,
        [int]$TtlHours = 24
    )
    $active = @{}
    $expired = @{}
    if (-not (Test-Path -LiteralPath $LeaseDir)) { return @{ Active = $active; Expired = $expired } }
    $now = [DateTime]::UtcNow
    foreach ($file in (Get-ChildItem -LiteralPath $LeaseDir -File -Filter '*.lease' -ErrorAction SilentlyContinue)) {
        if ($file.BaseName -notmatch '^\d{4}$') { continue }
        $id = $file.BaseName
        $created = $file.CreationTimeUtc
        $hostName = ''
        $worktree = ''
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            $obj = $raw | ConvertFrom-Json
            if ($obj.createdUtc) {
                $parsedCreated = $obj.createdUtc
                if ($parsedCreated -is [DateTime]) {
                    # ConvertFrom-Json already turned the ISO value into a DateTime:
                    # keep instants, shift Local/Unspecified (machine-local) to UTC.
                    if ($parsedCreated.Kind -eq [DateTimeKind]::Utc) { $created = $parsedCreated }
                    else { $created = $parsedCreated.ToUniversalTime() }
                }
                else {
                    $created = [DateTime]::Parse([string]$parsedCreated, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                    if ($created.Kind -ne [DateTimeKind]::Utc) { $created = $created.ToUniversalTime() }
                }
            }
            if ($obj.host) { $hostName = [string]$obj.host }
            if ($obj.worktree) { $worktree = [string]$obj.worktree }
        }
        catch { }   # unreadable lease: fall back to file timestamps
        $lease = [pscustomobject]@{ Id = $id; Path = $file.FullName; CreatedUtc = $created; Host = $hostName; Worktree = $worktree }
        if ($now -gt $created.AddHours($TtlHours)) { $expired[$id] = $lease }
        else { $active[$id] = $lease }
    }
    return @{ Active = $active; Expired = $expired }
}

function New-IssueIdLease {
    # Atomic reservation: FileMode::CreateNew either wins or throws - on the same
    # filesystem two processes can never both create <id>.lease.
    param(
        [string]$LeaseDir,
        [string]$Id,
        [string]$File = ''
    )
    if (-not (Test-Path -LiteralPath $LeaseDir)) {
        New-Item -ItemType Directory -Path $LeaseDir -Force | Out-Null
    }
    $path = Join-Path -Path $LeaseDir -ChildPath "$Id.lease"
    $payload = [ordered]@{
        id         = $Id
        createdUtc = [DateTime]::UtcNow.ToString('o')
        host       = [Environment]::MachineName
        user       = [Environment]::UserName
        pid        = $PID
        worktree   = (Get-Location).Path
        file       = $File
    }
    if ($env:COPILOT_SESSION_ID) { $payload['session'] = $env:COPILOT_SESSION_ID }
    $json = ($payload | ConvertTo-Json -Compress)
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $fs.Write($bytes, 0, $bytes.Length)
        }
        finally { $fs.Dispose() }
        return $true
    }
    catch [System.IO.IOException] {
        return $false    # someone else holds this id
    }
}

function Get-IssueIdUsage {
    # Canonical scan of the id space - mirrors issue-tree.ps1: active NNNN-*.md
    # in the store dir plus NNNN-*.md in the archive. Also reports duplicates so
    # the allocator refuses to hand out ids from an already-corrupt store.
    param(
        [string]$IssuesDir,
        [string]$ArchiveDir
    )
    $entries = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $IssuesDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $IssuesDir -File -Filter '*.md' | Where-Object { $_.Name -match '^\d{4}-' })) {
            $entries.Add([pscustomobject]@{ Prefix = $f.Name.Substring(0, 4); Source = $f.Name })
        }
    }
    if (Test-Path -LiteralPath $ArchiveDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $ArchiveDir -File -Filter '*.md' | Where-Object { $_.Name -match '^\d{4}-' })) {
            $entries.Add([pscustomobject]@{ Prefix = $f.Name.Substring(0, 4); Source = "archived/$($f.Name)" })
        }
    }
    $used = @{}
    $dupes = New-Object System.Collections.Generic.List[string]
    $maxId = 0
    foreach ($e in $entries) {
        if ($used.ContainsKey($e.Prefix)) {
            $dupes.Add("id $($e.Prefix) used twice: $($used[$e.Prefix]) and $($e.Source)")
        }
        else {
            $used[$e.Prefix] = $e.Source
        }
        $parsed = 0
        if ([int]::TryParse($e.Prefix, [ref]$parsed) -and $parsed -gt $maxId) { $maxId = $parsed }
    }
    return @{ Used = $used; Duplicates = $dupes; MaxId = $maxId }
}
