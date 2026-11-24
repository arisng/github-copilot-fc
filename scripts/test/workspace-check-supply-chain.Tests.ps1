Describe 'check-supply-chain.py' {
    BeforeAll {
        $checker = Join-Path (Split-Path $PSScriptRoot -Parent) 'workspace/check-supply-chain.py'
    }

    It 'warns on a prose link but skips the same URL inside inline code' {
        # Split at runtime: this file's own source must stay domain-clean
        # because the checker scans every tracked .ps1, itself included.
        # The fixture is .yml so a leaked copy can never raise markdown debt.
        $fixture = Join-Path $PSScriptRoot 'supply-fixture-tmp.yml'
        $prose = 'Prose link https://' + 'unlisted-fixture-domain.example/x should warn.'
        $code = 'Inline code `credential.' + 'https://github.com' + '.helper=helper` must not.'
        try {
            Set-Content -LiteralPath $fixture -Value @($prose, $code) -Encoding utf8
            $out = (& python3 $checker 2>&1 | Out-String)
            $out | Should -Match 'unlisted-fixture-domain\.example'
            $out | Should -Not -Match 'github\.com\.helper'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
        }
    }
}
