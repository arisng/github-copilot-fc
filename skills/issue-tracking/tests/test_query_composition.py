"""Tests for the pure issueQuery composition library.

skills/issue-tracking/scripts/query-composition-lib.ps1 is a dot-sourceable,
side-effect-free PowerShell library (no gh, no network, no manifest, no wall
clock) implementing sketch v6 section 1.1 (-Apply validation) and section
1.5 step 2 (tokenizer + class composition). These tests exercise it the way
the consumers do: dot-source it in a fresh pwsh and call the frozen contract
functions, asserting on JSON-serialized results.

Style follows test_tree_template_versioning.py (pwsh subprocess against skill
files); a pure library needs no temp-repo install, so the script is
dot-sourced directly from the skill tree.

Origin: FLEET TASK F2 (2026-11-21), hardened against the cheat-sheet corpus
quoted in critique section G (a.1-a.6).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]
LIB = SKILL_DIR / "scripts" / "query-composition-lib.ps1"

# Fixed caller-supplied asOf anchor (2025-11-21T00:00:00Z). The library reads
# no wall clock: this epoch is the only time input, so expected dates below
# are fully deterministic.
ANCHOR_EPOCH = 1763683200


@pytest.fixture(scope="session")
def pwsh_exe() -> str:
    exe = shutil.which("pwsh")
    if not exe:
        pytest.skip("pwsh not on PATH (skill scripts are PowerShell)")
    return exe


def _ps_quote(query: str) -> str:
    """Escape a string for use inside a PowerShell single-quoted literal."""
    return query.replace("'", "''")


def run_ps(pwsh: str, command: str) -> subprocess.CompletedProcess:
    full = f". '{LIB}'; {command}"
    return subprocess.run(
        [pwsh, "-NoProfile", "-Command", full],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )


def ps_json(pwsh: str, command: str):
    out = run_ps(pwsh, command)
    assert out.returncode == 0, f"command failed: {command}\n{out.stdout}\n{out.stderr}"
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError as exc:  # pragma: no cover - diagnostics path
        raise AssertionError(f"non-JSON output for: {command}\n{out.stdout!r}") from exc


def split(pwsh: str, query: str) -> list[dict]:
    return ps_json(
        pwsh,
        f"ConvertTo-Json -InputObject @(Split-GithubIssueQuery -Query '{_ps_quote(query)}')"
        " -Compress -Depth 5",
    )


def classes(pwsh: str, query: str) -> dict:
    return ps_json(
        pwsh,
        f"Get-GithubIssueQueryClasses -Query '{_ps_quote(query)}' | ConvertTo-Json -Compress -Depth 5",
    )


def validate(pwsh: str, query: str) -> dict:
    return ps_json(
        pwsh,
        f"Test-GithubIssueQuery -Query '{_ps_quote(query)}' | ConvertTo-Json -Compress -Depth 5",
    )


def compose(
    pwsh: str,
    query: str,
    include_closed: bool,
    epoch: int = ANCHOR_EPOCH,
    days: int = 365,
) -> dict:
    flag = "$true" if include_closed else "$false"
    return ps_json(
        pwsh,
        f"ComposedGithubIssueQuery -Query '{_ps_quote(query)}' -IncludeClosed:{flag}"
        f" -LookbackAnchorEpoch {epoch} -LookbackDays {days}"
        " | ConvertTo-Json -Compress -Depth 5",
    )


def lookback_date(epoch: int = ANCHOR_EPOCH, days: int = 365) -> str:
    """Mirror of the library's rule: UTC date of the anchor minus LookbackDays."""
    return (datetime.fromtimestamp(epoch, timezone.utc) - timedelta(days=days)).strftime(
        "%Y-%m-%d"
    )


# --------------------------------------------------------------------------
# Split-GithubIssueQuery - tokenizer with metadata
# --------------------------------------------------------------------------


def test_split_normalizes_negation_parens_and_plus(pwsh_exe: str) -> None:
    tokens = split(pwsh_exe, "-created:>=2020-01-01 (is:open) +label:bug is:closed)")
    assert tokens == [
        {
            "Text": "-created:>=2020-01-01",
            "Core": "created:>=2020-01-01",
            "InQuote": False,
        },
        {"Text": "(is:open)", "Core": "is:open", "InQuote": False},
        {"Text": "+label:bug", "Core": "label:bug", "InQuote": False},
        {"Text": "is:closed)", "Core": "is:closed", "InQuote": False},
    ]


def test_split_quoted_spans_keep_text_and_flag_provenance(pwsh_exe: str) -> None:
    tokens = split(pwsh_exe, 'label:"tech debt" "is:open" plain')
    assert tokens == [
        {
            "Text": 'label:"tech debt"',
            "Core": 'label:"tech debt"',
            "InQuote": True,
        },
        {"Text": '"is:open"', "Core": '"is:open"', "InQuote": True},
        {"Text": "plain", "Core": "plain", "InQuote": False},
    ]


def test_split_boundary_is_whitespace_only_outside_quotes(pwsh_exe: str) -> None:
    two = split(pwsh_exe, "label:bug\tmilestone:v2")
    assert [t["Text"] for t in two] == ["label:bug", "milestone:v2"]
    one = split(pwsh_exe, 'milestone:"Sprint 42"')
    assert [t["Text"] for t in one] == ['milestone:"Sprint 42"']
    assert split(pwsh_exe, "") == []


# --------------------------------------------------------------------------
# Get-GithubIssueQueryClasses - qualifier classes
# --------------------------------------------------------------------------


def test_quoted_is_open_is_not_a_state_class(pwsh_exe: str) -> None:
    # Cheat-sheet rule: label:"is:open" is a label VALUE, never a class
    # (critique a.2 - a regex false-positive here suppresses the lookback
    # knob and leaks closed rows).
    c = classes(pwsh_exe, 'label:"is:open"')
    assert c["HasState"] is False
    assert c["HasType"] is False
    assert c["HasTemporal"] is False


def test_quoted_window_value_is_not_a_temporal_class(pwsh_exe: str) -> None:
    assert classes(pwsh_exe, 'milestone:"created 2026"')["HasTemporal"] is False


def test_negated_created_counts_as_temporal(pwsh_exe: str) -> None:
    # Critique a.3: -created: is honored by gh search - presence counts.
    assert classes(pwsh_exe, "-created:>=2020-01-01")["HasTemporal"] is True


def test_case_variant_is_is_not_a_class(pwsh_exe: str) -> None:
    # Critique a.5: IS: degrades to free text in gh - not a class.
    c = classes(pwsh_exe, "IS:open")
    assert c["HasType"] is False
    assert c["HasState"] is False
    assert c["HasTemporal"] is False


def test_sort_and_order_are_distinct_classes(pwsh_exe: str) -> None:
    c = classes(pwsh_exe, "sort:created-asc")
    assert c["HasSort"] is True and c["HasOrder"] is False
    c = classes(pwsh_exe, "order:created-desc")
    assert c["HasOrder"] is True and c["HasSort"] is False


def test_repo_org_and_viewer_classes(pwsh_exe: str) -> None:
    assert classes(pwsh_exe, "repo:owner/name")["HasRepoOrOrg"] is True
    assert classes(pwsh_exe, "org:acme")["HasRepoOrOrg"] is True
    assert classes(pwsh_exe, "assignee:@me")["HasViewer"] is True
    assert classes(pwsh_exe, "mentions:@team")["HasViewer"] is True
    assert classes(pwsh_exe, "-author:@me")["HasViewer"] is True
    # Bare "@me" free text is not a qualifier value (documented simplification).
    assert classes(pwsh_exe, "crash @me now")["HasViewer"] is False


def test_type_and_state_are_separate_classes(pwsh_exe: str) -> None:
    # W3 regression: is:issue alone does NOT constrain state.
    c = classes(pwsh_exe, "is:issue")
    assert c["HasType"] is True and c["HasState"] is False
    c = classes(pwsh_exe, "is:closed")
    assert c["HasState"] is True and c["HasType"] is False
    c = classes(pwsh_exe, "is:issue is:open")
    assert c["HasType"] is True and c["HasState"] is True


def test_contradictory_state_records_both_seen(pwsh_exe: str) -> None:
    # is:open is:closed - both seen; the contradiction is left to gh
    # (returns [] with exit 0, critique a.4). No arbitration here.
    assert classes(pwsh_exe, "is:open is:closed")["HasState"] is True


def test_temporal_class_in_any_or_branch(pwsh_exe: str) -> None:
    assert classes(pwsh_exe, "created:<2026-01-01 OR created:>=2025-06-01")[
        "HasTemporal"
    ] is True
    assert classes(pwsh_exe, "(is:open OR is:closed)")["HasState"] is True
    assert classes(pwsh_exe, "updated:<2026-01-01 -label:epic")["HasTemporal"] is True
    assert classes(pwsh_exe, "closed:>2025-06-01")["HasTemporal"] is True


# --------------------------------------------------------------------------
# Test-GithubIssueQuery - section 1.1 reject list
# --------------------------------------------------------------------------

VALID_QUERIES = [
    'label:"tech debt"',
    "label:a,b,c",
    "-label:x,y",
    "no:assignee",
    "in:title,body",
    "comments:>10",
    'milestone:"Sprint 42"',
    "sort:created-asc",
    "assignee:@me",
    "-author:@me",
    "is:issue is:open assignee:@me sort:updated-desc",
    "label:area/* milestone:v2 -label:spam",
    "created:<2026-01-01 OR created:>=2025-06-01",
    "updated:<2026-01-01 -label:epic",
    "closed:>2025-06-01",
    # Contradictory AND: both seen, left to gh - the validator does not arbitrate.
    "is:open is:closed",
]


@pytest.mark.parametrize("query", VALID_QUERIES, ids=range(len(VALID_QUERIES)))
def test_valid_queries_pass(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result == {"IsValid": True, "Errors": []}, result


@pytest.mark.parametrize("query", ["", "   "])
def test_rejects_empty_query(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result["IsValid"] is False
    assert any("must not be empty" in e for e in result["Errors"])


def test_rejects_multiline_query(pwsh_exe: str) -> None:
    result = validate(pwsh_exe, "is:open\nis:closed")
    assert result["IsValid"] is False
    assert any("single line" in e for e in result["Errors"])


def test_rejects_unbalanced_double_quotes(pwsh_exe: str) -> None:
    result = validate(pwsh_exe, 'label:"unterminated')
    assert result["IsValid"] is False
    assert any("unbalanced double quotes" in e for e in result["Errors"])


def test_rejects_is_pr_with_better_message(pwsh_exe: str) -> None:
    result = validate(pwsh_exe, "is:pr")
    assert result["IsValid"] is False
    assert any("is:pr" in e and "pull request" in e for e in result["Errors"])


@pytest.mark.parametrize("query", ["is:openn", "is:"])
def test_rejects_bad_is_values(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result["IsValid"] is False
    assert any("one of open, closed, issue" in e for e in result["Errors"])


@pytest.mark.parametrize(
    "query",
    ["created:garbage", "updated:x", "closed:nope", "created:>yesterday"],
)
def test_rejects_unparseable_dates(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result["IsValid"] is False
    assert any("no parseable date" in e for e in result["Errors"])


@pytest.mark.parametrize("query", ["IS:open", "Created:2020-01-01", "LABEL:bug"])
def test_rejects_case_variant_qualifiers(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result["IsValid"] is False
    assert any("qualifier names are case-sensitive" in e for e in result["Errors"])


def test_rejects_order_as_typo(pwsh_exe: str) -> None:
    result = validate(pwsh_exe, "order:created-desc")
    assert result["IsValid"] is False
    assert any("order:" in e and "sort:" in e for e in result["Errors"])


@pytest.mark.parametrize("query", ["repo:owner/name", "org:acme"])
def test_rejects_repo_and_org(pwsh_exe: str, query: str) -> None:
    result = validate(pwsh_exe, query)
    assert result["IsValid"] is False
    assert any("is not allowed in issueQuery" in e for e in result["Errors"])


def test_viewer_is_detected_but_not_rejected(pwsh_exe: str) -> None:
    # @me/@team: consumer policy is detect-and-resolve, not reject.
    result = validate(pwsh_exe, "assignee:@me mentions:@team")
    assert result == {"IsValid": True, "Errors": []}, result
    assert classes(pwsh_exe, "assignee:@me mentions:@team")["HasViewer"] is True


# --------------------------------------------------------------------------
# ComposedGithubIssueQuery - knob composition (no wall clock)
# --------------------------------------------------------------------------


def test_composed_appends_every_missing_knob(pwsh_exe: str) -> None:
    result = compose(pwsh_exe, "label:bug", include_closed=False)
    date = lookback_date()
    assert result == {
        "Query": f"label:bug AND is:issue AND is:open AND created:>={date}",
        "SkippedKnobs": [],
    }


def test_composed_include_closed_neither_appends_nor_records_state(pwsh_exe: str) -> None:
    # IncludeClosed=true means the state knob was never engaged, so nothing
    # is recorded as skipped - only class-present suppressions are recorded.
    result = compose(pwsh_exe, "label:bug", include_closed=True)
    date = lookback_date()
    assert result == {
        "Query": f"label:bug AND is:issue AND created:>={date}",
        "SkippedKnobs": [],
    }


def test_composed_temporal_present_suppresses_lookback(pwsh_exe: str) -> None:
    # Backlog-rot form: the user's own window (updated:<...) must not be
    # over-constrained by our created: lookback append.
    result = compose(pwsh_exe, "updated:<2026-01-01 -label:epic", include_closed=False)
    date = lookback_date()
    assert result == {
        "Query": f"updated:<2026-01-01 -label:epic AND is:issue AND is:open",
        "SkippedKnobs": [f"created:>={date}"],
    }


def test_composed_or_ed_temporal_present(pwsh_exe: str) -> None:
    result = compose(
        pwsh_exe,
        "created:<2026-01-01 OR created:>=2025-06-01",
        include_closed=False,
    )
    date = lookback_date()
    assert result == {
        "Query": f"created:<2026-01-01 OR created:>=2025-06-01 AND is:issue AND is:open",
        "SkippedKnobs": [f"created:>={date}"],
    }


def test_composed_full_query_asserted_exactly(pwsh_exe: str) -> None:
    # Cheat-sheet row: type and state present, viewer + sort pass through;
    # only the temporal knob applies.
    result = compose(
        pwsh_exe,
        "is:issue is:open assignee:@me sort:updated-desc",
        include_closed=False,
    )
    date = lookback_date()
    assert result == {
        "Query": f"is:issue is:open assignee:@me sort:updated-desc AND created:>={date}",
        "SkippedKnobs": ["is:issue", "is:open"],
    }


def test_composed_state_present_records_skip(pwsh_exe: str) -> None:
    # is:closed carries NO type class (type/state split, W3): is:issue is
    # still appended, while the state knob is suppressed and recorded.
    result = compose(pwsh_exe, "is:closed", include_closed=False)
    date = lookback_date()
    assert result == {
        "Query": f"is:closed AND is:issue AND created:>={date}",
        "SkippedKnobs": ["is:open"],
    }


def test_composed_type_present_only_records_type_skip(pwsh_exe: str) -> None:
    result = compose(pwsh_exe, "is:issue", include_closed=False)
    date = lookback_date()
    assert result == {
        "Query": f"is:issue AND is:open AND created:>={date}",
        "SkippedKnobs": ["is:issue"],
    }


def test_composed_empty_query_still_produces_knob_segments(pwsh_exe: str) -> None:
    # Validation (non-empty) belongs to the consumer; composition itself is
    # total and deterministic.
    result = compose(pwsh_exe, "", include_closed=False)
    date = lookback_date()
    assert result == {
        "Query": f"is:issue AND is:open AND created:>={date}",
        "SkippedKnobs": [],
    }


def test_composed_lookback_comes_from_passed_epoch_not_wall_clock(pwsh_exe: str) -> None:
    # Two anchors, exact expected dates - a Get-Date implementation could
    # not produce these deterministically.
    assert lookback_date(1704067200, 10) == "2023-12-22"  # 2024-01-01 - 10d
    result = compose(pwsh_exe, "label:bug", include_closed=False, epoch=1704067200, days=10)
    assert result["Query"] == "label:bug AND is:issue AND is:open AND created:>=2023-12-22"
    assert compose(pwsh_exe, "label:bug", include_closed=False)["Query"].endswith(
        "created:>=2024-11-21"
    )
