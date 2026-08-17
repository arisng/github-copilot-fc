<#
.SYNOPSIS
    Upload a local image or video to GitHub's user-attachments API and return
    the hosted asset URL (https://github.com/user-attachments/assets/<uuid>).

.DESCRIPTION
    Replicates GitHub's drag-and-drop upload flow for Issues, PR descriptions,
    and comments. The flow is:

      1. Resolve the repository database ID from the current git remote.
      2. Determine the MIME type from the file extension.
      3. POST the raw file bytes to uploads.github.com/user-attachments/assets
         with metadata in the query string.
      4. Validate the HTTP status and parse the returned URL.

    Empirically verified (2026-08): the endpoint returns HTTP 201 with a JSON
    body {"url": "https://github.com/user-attachments/assets/<uuid>"} when the
    upload succeeds. Filenames MUST be URL-encoded (curl rejects raw spaces on
    Windows). There is no list/delete API for user attachments.

.PARAMETER FilePath
    Absolute or relative path to the media file. Supported extensions:
    png, jpg, jpeg, gif, webp, svg (images); mov, mp4, webm (videos).

.PARAMETER Repository
    Owner/name of the target repository. Defaults to the current git remote
    origin (owner/name form). Use this when uploading from a worktree whose
    remote is not the target repo.

.EXAMPLE
    ./upload-asset.ps1 -FilePath "Screen Shot 2026-08-17 at 10.30.00 AM.png"

.EXAMPLE
    ./upload-asset.ps1 -FilePath before.png -Repository "acme/widgets"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf }, ErrorMessage = "File not found: {0}")]
    [string]$FilePath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Repository
)

$ErrorActionPreference = 'Stop'

# --- Resolve media type from extension -----------------------------------
$ExtensionMap = @{
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.webp' = 'image/webp'
    '.svg'  = 'image/svg+xml'
    '.mov'  = 'video/quicktime'
    '.mp4'  = 'video/mp4'
    '.webm' = 'video/webm'
}

$Ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
if (-not $ExtensionMap.ContainsKey($Ext)) {
    throw "Unsupported file type '$Ext'. Supported: png, jpg, jpeg, gif, webp, svg, mov, mp4, webm"
}
$MimeType = $ExtensionMap[$Ext]

# --- Enforce GitHub size limits (docs.github.com attaching-files) -------
$SizeBytes = (Get-Item $FilePath).Length
$IsVideo = $MimeType.StartsWith('video/')
if ($IsVideo -and $SizeBytes -gt 100MB) {
    throw "Video exceeds GitHub's 100MB upload limit (paid plan). On free plans the limit is 10MB."
}
elseif (-not $IsVideo -and $SizeBytes -gt 10MB) {
    throw "File exceeds GitHub's 10MB upload limit for images/gifs."
}
elseif ($SizeBytes -gt 25MB) {
    Write-Warning "File exceeds GitHub's 25MB limit for non-image/non-video files; upload may fail."
}

# --- Resolve auth -------------------------------------------------------
$Token = gh auth token 2>$null
if (-not $Token) {
    throw "gh auth token failed. Run 'gh auth login' first."
}

# --- Resolve repository database ID -------------------------------------
if (-not $Repository) {
    $RemoteUrl = git remote get-url origin 2>$null
    if ($RemoteUrl -match '(?:github\.com[:/])([^/]+)/([^/]+?)(?:\.git)?$') {
        $Repository = "$($Matches[1])/$($Matches[2])"
    }
    if (-not $Repository) {
        throw "Could not detect the repository from git remote. Pass -Repository 'owner/name'."
    }
}
$RepoId = gh api "repos/$Repository" --jq '.id' 2>$null
if (-not $RepoId) {
    throw "Could not resolve repository ID for '$Repository'. Verify the repo exists and your token has access."
}

# --- Upload -------------------------------------------------------------
$FileName = [System.IO.Path]::GetFileName($FilePath)
$EncodedName = [uri]::EscapeDataString($FileName)
$EncodedMime = [uri]::EscapeDataString($MimeType)

$Uri = "https://uploads.github.com/user-attachments/assets?name=$EncodedName&content_type=$EncodedMime&repository_id=$RepoId"

$Response = curl -s -w "`n%{http_code}" `
    -X POST $Uri `
    -H "Content-Type: application/octet-stream" `
    -H "Accept: application/json" `
    -H "X-GitHub-Api-Version: 2022-11-28" `
    -H "Authorization: Bearer $Token" `
    --data-binary "@$FilePath"

$Lines = $Response -split "`n"
$HttpCode = $Lines[-1]
$Body = $Lines[0..($Lines.Length - 2)] -join "`n"

if ($HttpCode -ne '201') {
    throw "Upload failed with HTTP $HttpCode. Body: $Body"
}

$Url = ($Body | ConvertFrom-Json).url
if (-not $Url) {
    throw "No 'url' field in response: $Body"
}

Write-Output $Url