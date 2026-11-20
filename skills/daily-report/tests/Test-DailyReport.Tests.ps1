Describe 'Test-DailyReport.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $tester = Join-Path $scriptDir 'Test-DailyReport.ps1'
        $merge = Join-Path $scriptDir 'Merge-Glossary.ps1'

        function New-Fixture([string]$stamp) {
            $root = Join-Path $TestDrive ('r' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
            $dir = Join-Path $root 'reports/daily/alice'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            & $merge -GlossaryPath (Join-Path $dir 'glossary.md') -Owner 'alice' -TermsJson '[{"term":"git proof","meaning":"Author-filtered window commits as proof rows.","op":"insert"}]' | Out-Null
            $report = Join-Path $dir '261110.md'
            $body = @"
---
created: $stamp
updated: $stamp
---

# Daily Report

## 🏆 Completed Today

### 1. Verified sync
- **Why:** Untested sync leaves conflicting history.
- **Result:** Fetched and rebased the branch.
- **Refs:** session ``16f5c5b5`` · sync check -> PASS.

## 👀 Under Review
| Item | Awaiting | Where |
| :--- | :--- | :--- |
| x | y | z |

## 🚀 Active Work
| Task Item | Why it matters | Current State |
| :--- | :--- | :--- |
| t | w | s |

## ⚠️ Blockers & Risks
| What is stuck | Impact | Who holds it |
| :--- | :--- | :--- |
| b | i | o |

## 📋 Next Up
1. Keep going.

## Glossary
| Term | Status | Meaning |
| :--- | :--- | :--- |
| git proof | known | Author-filtered window commits as proof rows. |
"@
            [IO.File]::WriteAllText($report, $body)
            # The report cites session 16f5c5b5; enforcement requires its export.
            $sessDir = Join-Path $dir 'sessions'
            New-Item -ItemType Directory -Force -Path $sessDir | Out-Null
            [IO.File]::WriteAllText((Join-Path $sessDir '16f5c5b5.html'), "<!doctype html><html><body>transcript 16f5c5b5</body></html>")
            return $report
        }
    }

    It 'passes a report that satisfies every guardrail' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 0
        "$out" | Should -Match 'PASS'
    }

    It 'breaks a word-budget failure down by section' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $filler = ('signal outcome decision proof session report glossary refs active review blocker priority evidence anchor ladder pointer cache load ' * 40).Trim()
        $c = [IO.File]::ReadAllText($r) -replace '## Glossary', "1. $filler`n`n## Glossary"
        [IO.File]::WriteAllText($r, $c)
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'budget: \d+ words \(max 600\)'
        "$out" | Should -Match 'words by section'
        "$out" | Should -Match 'Next Up=\d+'
    }

    It 'fails on a covers field or Covers line' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $c = [IO.File]::ReadAllText($r) -replace 'created:', 'covers: x`ncreated:'
        [IO.File]::WriteAllText($r, $c)
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
    }

    It 'fails on a clock time in the body' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        Add-Content $r '- note at 14:30 about the run.'
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'timeless body'
    }

    It 'fails on a commit hash or turn number in refs' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $c = [IO.File]::ReadAllText($r) -replace 'sync check -> PASS\.', 'commit ``0123456789abcdef`` · turn 3.'
        [IO.File]::WriteAllText($r, $c)
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
    }

    It 'fails when a known glossary row diverges from canonical' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $c = [IO.File]::ReadAllText($r) -replace 'Author-filtered window commits as proof rows\.', 'Different meaning.'
        [IO.File]::WriteAllText($r, $c)
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'canonical'
    }

    It 'fails on a wrong path or name' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $bad = Join-Path (Split-Path $r -Parent) 'Daily Report - 2026-11-10.md'
        Move-Item $r $bad
        $out = & $tester -ReportPath $bad -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
    }

    It 'fails when an exported transcript for a cited session is missing' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        Remove-Item (Join-Path (Split-Path $r -Parent) 'sessions/16f5c5b5.html')
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'sessions:'
        "$out" | Should -Match '16f5c5b5'
    }

    It 'does not demand an export for grill session mentions' {
        $r = New-Fixture '2026-11-10 13:57 +07:00'
        $c = [IO.File]::ReadAllText($r) -replace 'session `16f5c5b5`', 'grill session `20261105-120133`'
        [IO.File]::WriteAllText($r, $c)
        Remove-Item (Join-Path (Split-Path $r -Parent) 'sessions/16f5c5b5.html')
        $out = & $tester -ReportPath $r -GitUser 'alice' -Date '2026-11-10' 2>&1
        $LASTEXITCODE | Should -Be 0
        "$out" | Should -Match 'PASS'
    }
}
