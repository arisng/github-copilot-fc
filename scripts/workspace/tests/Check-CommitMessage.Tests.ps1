# Pester tests for scripts/workspace/check-commit-message.ps1 (retro 2026-11-23).
# The script exits with a code, so every invocation runs as a subprocess -
# dot-sourcing it would take the Pester host down with it.

BeforeAll {
    $script:checker = (Resolve-Path (Join-Path $PSScriptRoot '..' 'check-commit-message.ps1')).Path
    $script:pwsh = (Get-Process -Id $PID).Path
    $script:fixtures = [System.Collections.Generic.List[string]]::new()

    function Invoke-Check {
        param(
            [Parameter(Mandatory)][string]$Subject,
            [string]$Constitution,
            [switch]$MissingConstitution
        )

        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('commitmsg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $script:fixtures.Add($dir)
        $msg = Join-Path $dir 'COMMIT_EDITMSG'
        Set-Content -Path $msg -Value $Subject -Encoding UTF8

        $arguments = @('-NoProfile', '-File', $script:checker, '-MessagePath', $msg)
        if ($MissingConstitution) {
            $arguments += @('-ConstitutionPath', (Join-Path $dir 'absent-constitution.md'))
        }
        elseif ($Constitution) {
            $constitutionPath = Join-Path $dir 'constitution.md'
            Set-Content -Path $constitutionPath -Value $Constitution -Encoding UTF8
            $arguments += @('-ConstitutionPath', $constitutionPath)
        }

        $out = @(& $script:pwsh @arguments 2>&1 | ForEach-Object { "$_" })
        return [pscustomobject]@{
            Code   = $LASTEXITCODE
            Output = ($out -join "`n")
        }
    }

    # Minimal constitution fixture: one approved type with two scopes, one
    # deprecated type that still lists scopes.
    $script:Constitution = @'
## Approved Scopes by Commit Type

### `agent`

- `skill`: AI instruction content within skills folders
- `instruction`: AI behavioral changes

### `docs`

- `readme`: Root or directory-level README files

### `ai`

> **Deprecated type.** Use `agent` instead.

- `skill`: legacy
'@
}

AfterAll {
    foreach ($dir in $script:fixtures) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'check-commit-message.ps1' {
    It 'passes an approved type-and-scope pair' {
        $r = Invoke-Check -Subject 'agent(skill): add a skill' -Constitution $script:Constitution
        $r.Code | Should -Be 0
        $r.Output | Should -Match '\[PASS\] agent\(skill\)'
    }

    It 'refuses a type the constitution does not list' {
        $r = Invoke-Check -Subject 'fix(skill): repair the gate' -Constitution $script:Constitution
        $r.Code | Should -Be 1
        $r.Output | Should -Match "type 'fix' is not approved"
        $r.Output | Should -Match 'approved types:'
    }

    It 'refuses a scope not listed for the given type' {
        $r = Invoke-Check -Subject 'docs(skill): wrong scope for docs' -Constitution $script:Constitution
        $r.Code | Should -Be 1
        $r.Output | Should -Match "scope 'skill' is not approved for type 'docs'"
        $r.Output | Should -Match 'approved docs scopes: readme'
    }

    It 'refuses a deprecated type even though it lists scopes' {
        $r = Invoke-Check -Subject 'ai(skill): legacy spelling' -Constitution $script:Constitution
        $r.Code | Should -Be 1
        $r.Output | Should -Match "type 'ai' is not approved"
    }

    It 'refuses a subject with no conventional shape' {
        $r = Invoke-Check -Subject 'just some words' -Constitution $script:Constitution
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'expected "<type>\(<scope>\): <summary>"'
    }

    It 'passes git-generated messages through' -ForEach @(
        @{ Subject = 'Merge branch feature/x into main' }
        @{ Subject = 'Revert "agent(skill): something"' }
        @{ Subject = 'fixup! agent(skill): something' }
    ) {
        $r = Invoke-Check -Subject $Subject -Constitution $script:Constitution
        $r.Code | Should -Be 0
        $r.Output | Should -Match '\[PASS\] generated message'
    }

    It 'skips when the constitution is absent' {
        $r = Invoke-Check -Subject 'anything at all' -MissingConstitution
        $r.Code | Should -Be 0
        $r.Output | Should -Match '\[SKIP\]'
    }

    It 'refuses an empty message' {
        $r = Invoke-Check -Subject '   ' -Constitution $script:Constitution
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'empty commit message'
    }
}
