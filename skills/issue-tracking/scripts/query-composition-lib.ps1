# Pure query-composition helpers for the issue-tracking skill's GitHub
# `issueQuery` (dot-sourceable library: no params, no side effects on load,
# no `gh` calls, no network, no manifest reads - the CONSUMER supplies every
# input).
#
# Spec source (authoritative): sketch v6 section 1.1 (-Apply validation
# reject list) + section 1.5 step 2 (tokenizer, class composition table,
# temporal broadening, sort semantics); supporting proofs: critique section G
# (a.1-a.6, G-R).
#
# Frozen public contract (other scripts dot-source these exact names):
#   Split-GithubIssueQuery       -> ordered tokens via the pipeline; capture
#                                   with @(...). Each token is an object with
#                                   Text    = verbatim token (quotes/parens kept)
#                                   Core    = Text with leading '(' '+' '-'
#                                             stripped and trailing ')' stripped
#                                   InQuote = $true when the token consumed any
#                                             double-quoted span (provenance)
#   Get-GithubIssueQueryClasses  -> object of booleans: HasType, HasState,
#                                   HasTemporal, HasSort, HasRepoOrOrg,
#                                   HasViewer, HasOrder
#   Test-GithubIssueQuery        -> object { IsValid; Errors[] } (section 1.1)
#   ComposedGithubIssueQuery     -> object { Query; SkippedKnobs[] }
#
# Tokenizer rules (sketch 1.5 step 2): left-to-right scan with double-quote
# state; a token boundary is whitespace OUTSIDE quotes only; quote characters
# stay inside Text. Quoted spans never yield classes - `label:"is:open"` is a
# label *value* (critique a.2: a raw-string regex false-positives here and
# suppresses the lookback knob, leaking closed rows). Class prefixes match
# case-SENSITIVELY (critique a.5: `IS:` silently degrades to free text in gh,
# so an case-insensitive detector would skip our knob while gh filters
# nothing). `-created:`/`+created:`/`(created:` count as the class after Core
# normalization (critique a.3: negated windows are honored by gh search).
# Presence in ANY OR branch = class present - presence-based, not
# coverage-based; no branch merging/reconciliation (a.1). A contradictory AND
# (`is:open is:closed`) records state-present and is otherwise left to gh,
# which returns [] with exit 0 (a.4) - we do not arbitrate for gh.
#
# Class table (sketch 1.5 step 2):
#   type      is:issue           -> append `is:issue` iff absent
#   state     is:open/is:closed  -> append `is:open` iff state absent AND
#                                   !IncludeClosed (is:issue alone does NOT
#                                   constrain state - W3)
#   temporal  created:/updated:/closed: -> append `created:>=<date>` iff no
#                                   temporal qualifier (temporal broadening:
#                                   a user window via another qualifier must
#                                   not be over-constrained by our lookback)
#   sort      sort:              -> pass through (supported: selects which rows
#                                   survive the cap; tree row order is ours)
#   order:    rejected by Test   -> not a valid gh qualifier (likely typo)
#   repo:/org: rejected by Test  -> the manifest's `repo` field owns the
#                                   target; gh appends its own repo: after
#                                   `( ... )`, so a duplicate silently
#                                   intersects (empty or wrong set, exit 0)
#   @me/@team -> NOT rejected    -> consumer policy is detect-and-resolve;
#                                   detection is exposed via HasViewer
#
# Deliberate simplifications (spec silent -> simplest behavior):
#   - InQuote flags a token that consumed any quoted span, not only a token
#     that began inside one; class detection skips those tokens outright.
#   - Test validates every token on its Core: a leading '"' is never stripped,
#     so wholly-quoted tokens fall through the prefix checks naturally, while
#     `Milestone:"Sprint 42"` (quoted VALUE, unquoted qualifier) still gets
#     its case-variant check.
#   - HasViewer matches @me/@team only when attached to a qualifier
#     (`qualifier:[<non-space junk>]@me|@team`, case-sensitive); a bare "@me"
#     free-text token is not a qualifier value and does not count.
#   - Date validation is pragmatic: the value must merely contain a 4-digit
#     year (`\d{4}`); no full date grammar (section 1.1's "parseable date
#     token" hardened against the cheat-sheet corpus, not over-engineered).
#   - Balanced double quotes = an even count of `"` (no escape syntax).
#   - ComposedGithubIssueQuery trims surrounding whitespace of the user query
#     and joins the user text with appended segments using ` AND `; the
#     lookback date derives ONLY from LookbackAnchorEpoch (UTC yyyy-MM-dd
#     minus LookbackDays) - never Get-Date, no wall clock anywhere.
#   - SkippedKnobs records exactly the append segments suppressed by a
#     present class, in order: 'is:issue', 'is:open', 'created:>=yyyy-MM-dd'.
#     An append the knobs would not have made anyway (state when
#     -IncludeClosed is true) is not recorded - nothing was skipped.

function Split-GithubIssueQuery {
    # Left-to-right, quote-aware tokenizer. Returns tokens via the pipeline;
    # capture with @(...) so empty queries yield an empty array.
    param([string]$Query)
    if ([string]::IsNullOrEmpty($Query)) { return }
    $inQuote = $false
    $sawQuote = $false
    $buf = [System.Text.StringBuilder]::new()
    $raw = [System.Collections.Generic.List[object]]::new()
    foreach ($ch in $Query.ToCharArray()) {
        if ($ch -eq '"') {
            # Quote chars toggle state and stay in the token text.
            $inQuote = -not $inQuote
            $sawQuote = $true
            [void]$buf.Append($ch)
        }
        elseif (-not $inQuote -and [char]::IsWhiteSpace($ch)) {
            # Boundary: whitespace only OUTSIDE quotes.
            if ($buf.Length -gt 0) {
                $text = $buf.ToString()
                $raw.Add([PSCustomObject]@{
                    Text    = $text
                    Core    = $text.TrimStart('(', '+', '-').TrimEnd(')')
                    InQuote = $sawQuote
                })
                [void]$buf.Clear()
                $sawQuote = $false
            }
        }
        else {
            [void]$buf.Append($ch)
        }
    }
    if ($buf.Length -gt 0) {
        $text = $buf.ToString()
        $raw.Add([PSCustomObject]@{
            Text    = $text
            Core    = $text.TrimStart('(', '+', '-').TrimEnd(')')
            InQuote = $sawQuote
        })
    }
    foreach ($t in $raw) { $t }
}

function Get-GithubIssueQueryClasses {
    # Qualifier-class detection. Prefix matches are case-sensitive (ordinal),
    # exactly like gh's own qualifier parsing; quoted spans never yield
    # classes; presence in any OR branch counts.
    param([string]$Query)
    $hasType = $false
    $hasState = $false
    $hasTemporal = $false
    $hasSort = $false
    $hasRepoOrg = $false
    $hasViewer = $false
    $hasOrder = $false
    foreach ($t in @(Split-GithubIssueQuery -Query $Query)) {
        $core = $t.Core
        if (-not $t.InQuote) {
            if ($core -ceq 'is:issue') { $hasType = $true }
            # is:issue alone does not constrain state (W3) - type and state
            # stay split; `is:open is:closed` sets HasState (both seen) and
            # the contradiction is left to gh (empty result, exit 0).
            if ($core -ceq 'is:open' -or $core -ceq 'is:closed') { $hasState = $true }
            # Temporal broadening: any of the three window qualifiers in any
            # OR branch suppresses our lookback append.
            if ($core.StartsWith('created:', [System.StringComparison]::Ordinal) -or
                $core.StartsWith('updated:', [System.StringComparison]::Ordinal) -or
                $core.StartsWith('closed:', [System.StringComparison]::Ordinal)) {
                $hasTemporal = $true
            }
            if ($core.StartsWith('sort:', [System.StringComparison]::Ordinal)) { $hasSort = $true }
            if ($core.StartsWith('repo:', [System.StringComparison]::Ordinal) -or
                $core.StartsWith('org:', [System.StringComparison]::Ordinal)) { $hasRepoOrg = $true }
            if ($core.StartsWith('order:', [System.StringComparison]::Ordinal)) { $hasOrder = $true }
        }
        # Viewer detection (not a class): @me/@team attached to a qualifier
        # value, case-sensitive; quoted values still count (they are values).
        if ($core -cmatch '[A-Za-z][A-Za-z0-9-]*:[^\s]*@(me|team)\b') { $hasViewer = $true }
    }
    [PSCustomObject]@{
        HasType      = $hasType
        HasState     = $hasState
        HasTemporal  = $hasTemporal
        HasSort      = $hasSort
        HasRepoOrOrg = $hasRepoOrg
        HasViewer    = $hasViewer
        HasOrder     = $hasOrder
    }
}

function Test-GithubIssueQuery {
    # Section 1.1 -Apply reject list. Collects every violation (gh exits 0 on
    # all of this garbage, so this validator is the real defense - critique
    # a.6). `sort:` is supported (no error); `order:` is rejected as a typo;
    # @me/@team are NOT rejected here (consumer resolves and records them).
    param([string]$Query)
    $errors = @()
    if ([string]::IsNullOrWhiteSpace($Query)) {
        $errors += 'issueQuery must not be empty'
    }
    if ($Query.Contains("`r") -or $Query.Contains("`n")) {
        $errors += 'issueQuery must be a single line (found a newline)'
    }
    if (([regex]::Matches($Query, '"')).Count % 2 -ne 0) {
        $errors += 'issueQuery has unbalanced double quotes'
    }
    $knownQualifiers = @(
        'is', 'created', 'updated', 'closed', 'sort', 'order', 'repo', 'org',
        'label', 'milestone', 'assignee', 'author', 'mentions', 'no', 'in',
        'comments'
    )
    foreach ($t in @(Split-GithubIssueQuery -Query $Query)) {
        $core = $t.Core
        # Case-variant qualifier names: gh qualifiers are case-sensitive, so
        # `IS:` silently degrades to free text (a.5) - fail loud instead.
        $colon = $core.IndexOf(':')
        if ($colon -gt 0) {
            $qual = $core.Substring(0, $colon)
            $lower = $qual.ToLowerInvariant()
            if ($lower -in $knownQualifiers -and $qual -cne $lower) {
                $errors += "qualifier names are case-sensitive: '$qual' should be '$lower'"
            }
        }
        if ($core.StartsWith('is:', [System.StringComparison]::Ordinal)) {
            $value = $core.Substring(3)
            if ($value -ceq 'pr') {
                $errors += "is:pr cannot be used in an issue query: gh issue list rejects pull request qualifiers, and this tree tracks issues only"
            }
            elseif ($value -cnotin @('open', 'closed', 'issue')) {
                $errors += "is: value must be one of open, closed, issue (got '$value')"
            }
        }
        $datePrefix = $null
        if ($core.StartsWith('created:', [System.StringComparison]::Ordinal)) { $datePrefix = 'created:' }
        elseif ($core.StartsWith('updated:', [System.StringComparison]::Ordinal)) { $datePrefix = 'updated:' }
        elseif ($core.StartsWith('closed:', [System.StringComparison]::Ordinal)) { $datePrefix = 'closed:' }
        if ($null -ne $datePrefix) {
            $value = $core.Substring($datePrefix.Length)
            if ($value -notmatch '\d{4}') {
                $errors += "${datePrefix} value '$value' has no parseable date (expected a YYYY-MM-DD token)"
            }
        }
        if ($core.StartsWith('order:', [System.StringComparison]::Ordinal)) {
            $errors += 'order: is not a valid GitHub search qualifier - use sort: instead (looks like a typo)'
        }
        if ($core.StartsWith('repo:', [System.StringComparison]::Ordinal)) {
            $errors += "repo: is not allowed in issueQuery - the manifest 'repo' field owns the target (gh appends its own repo:, a duplicate silently intersects)"
        }
        if ($core.StartsWith('org:', [System.StringComparison]::Ordinal)) {
            $errors += 'org: is not allowed in issueQuery - cross-org queries are out of scope for a single-repo manifest'
        }
    }
    [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors
    }
}

function ComposedGithubIssueQuery {
    # Builds the final search query: user text first, then knob segments
    # joined with ' AND ' (gh search treats whitespace as AND; the explicit
    # join keeps appended segments readable and unambiguous). Never appends
    # when the class is present - that suppression is recorded in
    # SkippedKnobs. Deterministic: the lookback anchor is the caller's epoch
    # (stored asOf), never the wall clock.
    param(
        [string]$Query,
        [bool]$IncludeClosed,
        [long]$LookbackAnchorEpoch,
        [int]$LookbackDays
    )
    $classes = Get-GithubIssueQueryClasses -Query $Query
    $anchorUtc = [DateTimeOffset]::FromUnixTimeSeconds($LookbackAnchorEpoch).UtcDateTime
    $lookbackDate = $anchorUtc.AddDays(-$LookbackDays).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $segments = @()
    $skipped = @()
    if ($classes.HasType) { $skipped += 'is:issue' } else { $segments += 'is:issue' }
    if (-not $IncludeClosed) {
        if ($classes.HasState) { $skipped += 'is:open' } else { $segments += 'is:open' }
    }
    if ($classes.HasTemporal) { $skipped += "created:>=$lookbackDate" } else { $segments += "created:>=$lookbackDate" }
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($Query)) { $parts += $Query.Trim() }
    $parts += $segments
    [PSCustomObject]@{
        Query       = ($parts -join ' AND ')
        SkippedKnobs = $skipped
    }
}
