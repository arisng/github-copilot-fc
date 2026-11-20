# Shared tree-template version helpers for the issue-tracking skill
# (dot-sourced, no params, no side effects).
#
# Contract - versioning the generated view (.issues/tree.html):
#   assets/tree-template.version.json = {"version": "MAJOR.MINOR.PATCH", "sha256": "..."}
#     version - bumped on EVERY edit to assets/tree-template.html (see
#               bump-tree-template-version.ps1, which refuses downgrades);
#     sha256  - fingerprint of the template the version was recorded for, so an
#               edit without a bump fails render/-Check instead of shipping.
#   assets/tree-template.html embeds __TREE_TEMPLATE_VERSION__ (head meta
#   tree-template-version + footer); render-issue-tree.ps1 replaces every
#   occurrence, so each generated page states which template built it and a
#   consumer repo can detect version drift at -Check and patch by re-rendering.
#
# Fingerprint: SHA-256 (lowercase hex) over the template text with CR/CRLF
# normalized to LF, encoded UTF-8 without BOM - line-ending conversion during
# checkout/publishing never causes a false drift.

function Test-TreeTemplateVersionFormat {
    # MAJOR.MINOR.PATCH with an optional semver pre-release/build suffix; also
    # guarantees the value is HTML/meta-attribute safe when injected.
    param([string]$Version)
    if ([string]::IsNullOrEmpty($Version)) { return $false }
    return [bool]($Version -match '^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$')
}

function Get-TreeTemplateSha256 {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = [System.BitConverter]::ToString($sha.ComputeHash($bytes))
    }
    finally {
        $sha.Dispose()
    }
    return $digest.Replace('-', '').ToLowerInvariant()
}

function Get-TreeTemplateVersionState {
    # Parses assets/tree-template.version.json into @{ Version; Sha256; Error }.
    # Error is $null when the file is present and valid; Version/Sha256 are set
    # as far as parsing allowed so callers can still report what they found.
    param([string]$Path)
    $state = @{ Version = $null; Sha256 = $null; Error = $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        $state.Error = "template version file '$Path' not found"
        return $state
    }
    $raw = $null
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = ConvertFrom-Json -InputObject $raw
    }
    catch {
        $state.Error = "template version file '$Path' is not valid JSON: $($_.Exception.Message)"
        return $state
    }
    $names = @($obj.PSObject.Properties.Name)
    if ($names -contains 'version') { $state.Version = [string]$obj.version }
    if ($names -contains 'sha256') { $state.Sha256 = ([string]$obj.sha256).ToLowerInvariant() }
    if (-not (Test-TreeTemplateVersionFormat -Version $state.Version)) {
        $state.Error = "template version file '$Path': 'version' must be MAJOR.MINOR.PATCH (got '$($state.Version)')"
        return $state
    }
    if ($state.Sha256 -notmatch '^[0-9a-f]{64}$') {
        $state.Error = "template version file '$Path': 'sha256' must be a 64-char hex digest (got '$($state.Sha256)')"
        $state.Sha256 = $null
        return $state
    }
    return $state
}
