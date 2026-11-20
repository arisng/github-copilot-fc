Describe 'Merge-Glossary.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $merge = Join-Path $scriptDir 'Merge-Glossary.ps1'
    }
    BeforeEach {
        $path = Join-Path $TestDrive ('g' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + '/reports/daily/alice/glossary.md')
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    }

    It 'creates the pinned format and sorts terms' {
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"zeta","meaning":"Last letter.","op":"insert"},{"term":"Alpha","meaning":"First letter.","op":"insert"}]' | Out-Null
        $c = [IO.File]::ReadAllText($path)
        $c | Should -Match '(?m)^---$'
        $c | Should -Match '(?m)^owner: alice$'
        $c | Should -Match '(?m)^\| Alpha \| First letter\. \|$'
        $c.IndexOf('| Alpha |') | Should -BeLessThan $c.IndexOf('| zeta |')
    }

    It 'never doubles a case-insensitive duplicate and keeps first-seen casing' {
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"Alpha","meaning":"First.","op":"insert"}]' | Out-Null
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"ALPHA","meaning":"First.","op":"keep"}]' | Out-Null
        ([regex]::Matches([IO.File]::ReadAllText($path), '(?mi)^\| alpha \|')).Count | Should -Be 1
    }

    It 'fails loudly on insert of an existing key' {
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"Alpha","meaning":"First.","op":"insert"}]' | Out-Null
        { & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"Alpha","meaning":"Other.","op":"insert"}]' } | Should -Throw
    }

    It 'round-trips an escaped pipe' {
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"pipe","meaning":"A | B.","op":"insert"}]' | Out-Null
        [IO.File]::ReadAllText($path) | Should -Match 'A \\| B\.'
        & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[]' -Validate | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'fails closed on a malformed file and leaves it unchanged' {
        "---`nowner: alice`nschema: 1`n---`n`n# Glossary`n`n| Term | Meaning |`n| --- | --- |`n| a | b | c |" | Set-Content $path
        $before = [IO.File]::ReadAllText($path)
        { & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"x","meaning":"y.","op":"insert"}]' } | Should -Throw
        [IO.File]::ReadAllText($path) | Should -Be $before
    }

    It 'refuses an owner that does not match the folder' {
        { & $merge -GlossaryPath $path -Owner 'bob' -TermsJson '[]' } | Should -Throw
    }

    It 'refuses an unknown schema' {
        "---`nowner: alice`nschema: 99`n---`n`n# Glossary`n`n| Term | Meaning |`n| --- | --- |" | Set-Content $path
        { & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[]' } | Should -Throw
    }

    It 'is byte-stable on a no-op and reports the receipt' {
        $r1 = & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"Alpha","meaning":"First.","op":"insert"}]' | ConvertFrom-Json
        $before = [IO.File]::ReadAllText($path)
        $r2 = & $merge -GlossaryPath $path -Owner 'alice' -TermsJson '[{"term":"Alpha","meaning":"First.","op":"keep"}]' | ConvertFrom-Json
        [IO.File]::ReadAllText($path) | Should -Be $before
        $r2.changed | Should -BeFalse
        $r2.kept | Should -Be 1
        $r1.added | Should -Be 1
    }
}
