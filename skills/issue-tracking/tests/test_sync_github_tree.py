"""Offline tests for skills/issue-tracking/scripts/sync-github-tree.ps1.

Network strategy (the chosen one of the two the spec allows): the sync takes
a ``-FromJson <file>`` fixture parameter, so every test runs the full script
flow - manifest guard, query composition, mapping, promotion, cap, emission,
FILTER line - with zero gh calls. The fixture mirrors the exact shape
``gh issue list --json ...`` prints and adds two stand-ins for the two other
network calls:

    {
      "issues":      [ <gh issue list --json row>, ... ],
      "exactCount":  <int>,     # optional; what the GraphQL issueCount call
                                # would return (only consulted when
                                # issueQuery is set); absent -> floor path
      "viewerLogin": "<login>"  # optional; required when the query carries
                                # @me/@team (gh api graphql viewer lookup)
    }

The fixture is sliced to treeMaxIssues+1 exactly like gh --limit, so cap+1
truncation probes behave identically offline. Output is asserted by piping
the written tree through issue-tree.ps1 -Check (github mode) and, where the
banner matters, render-issue-tree.ps1 + the embedded HTML JSON.

Origin: FLEET TASK F5 (2026-11-21), per github-tree-adaptation-sketch.md
sections 1.4 / 1.5 / 1.6 and critique sections F/G. Pattern reused from
test_github_guard_and_hardening.py: copy the skill into tmp_path, shell out
to pwsh -File from a throwaway repo.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]
REPO = "acme/widgets"


@pytest.fixture(scope="session")
def pwsh_exe() -> str:
    exe = shutil.which("pwsh")
    if not exe:
        pytest.skip("pwsh not on PATH (skill scripts are PowerShell)")
    return exe


def run_script(pwsh: str, script: Path, args: tuple, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [pwsh, "-NoProfile", "-File", str(script), *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )


@pytest.fixture
def skill(tmp_path: Path) -> Path:
    """A consumer-style install: the skill copied into the temp dir."""
    dst = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, dst)
    return dst


def manifest(**overrides) -> dict:
    base = {
        "schemaVersion": 1,
        "tracker": "github",
        "treeSource": "github",
        "repo": REPO,
        "treeFile": ".issues/tree.md",
        "treeMaxIssues": 300,
        "treeLookbackDays": 365,
        "treeIncludeClosed": True,
    }
    base.update(overrides)
    return base


def make_repo(tmp_path: Path, m: dict, name: str = "repo") -> Path:
    repo = tmp_path / name
    (repo / ".github").mkdir(parents=True)
    (repo / ".github" / "issue-tracker.json").write_text(json.dumps(m), encoding="utf-8")
    return repo


def gh_issue(
    number: int,
    title: str = "Issue",
    state: str = "OPEN",
    state_reason: str | None = None,
    labels: tuple[str, ...] = (),
    milestone: tuple[int, str] | None = None,
    parent: int | None = None,
    sub_issues: list | None = None,
    sub_summary_total: int = 0,
) -> dict:
    """One row in gh issue list --json shape (verified against gh 2.102.0)."""
    return {
        "number": number,
        "title": title,
        "state": state,
        "stateReason": state_reason,
        "labels": [
            {"id": "L_x", "name": n, "description": None, "color": "cccccc"} for n in labels
        ],
        "milestone": (
            None
            if milestone is None
            else {"title": milestone[1], "number": milestone[0], "state": "open"}
        ),
        "parent": None if parent is None else {"number": parent, "title": "parent"},
        "subIssues": {"nodes": [], "totalCount": 0}
        if sub_issues is None
        else {"nodes": sub_issues, "totalCount": len(sub_issues)},
        "subIssuesSummary": {
            "completed": 0,
            "percentCompleted": 0,
            "total": sub_summary_total,
        },
        "createdAt": "2026-11-01T00:00:00Z",
        "updatedAt": "2026-11-01T00:00:00Z",
        "closedAt": "2026-11-02T00:00:00Z" if state == "CLOSED" else None,
    }


def write_fixture(repo: Path, issues: list, exact_count=None, viewer=None) -> Path:
    payload: dict = {"issues": issues}
    if exact_count is not None:
        payload["exactCount"] = exact_count
    if viewer is not None:
        payload["viewerLogin"] = viewer
    path = repo / "fixture.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def run(pwsh: str, skill: Path, repo: Path, script: str, *args: str) -> subprocess.CompletedProcess:
    return run_script(pwsh, skill / "scripts" / script, args, repo)


def sync(
    pwsh: str,
    skill: Path,
    repo: Path,
    issues: list,
    exact_count=None,
    viewer=None,
) -> subprocess.CompletedProcess:
    fixture = write_fixture(repo, issues, exact_count=exact_count, viewer=viewer)
    return run(pwsh, skill, repo, "sync-github-tree.ps1", "-FromJson", str(fixture))


def read_tree(repo: Path) -> str:
    return (repo / ".issues" / "tree.md").read_text(encoding="utf-8")


def parse_tree(text: str) -> dict:
    """Tiny grammar reader: filter/summary/next + sections with rows."""
    out: dict = {"filter": None, "summary": {}, "next": None, "sections": []}
    current = None
    for line in text.split("\n"):
        if line.startswith("FILTER|"):
            out["filter"] = line[len("FILTER|") :]
        elif line.startswith("SUMMARY|"):
            for seg in line.split("|")[1:]:
                k, v = seg.split("=")
                out["summary"][k] = int(v)
        elif line.startswith("NEXT|"):
            out["next"] = line.split("|", 5)[1:]
        elif line.startswith("## THEME|"):
            f = line.split("|", 4)
            current = {"id": f[1], "priority": f[2], "status": f[3], "title": f[4], "rows": []}
            out["sections"].append(current)
        elif re.match(r"^ *- ", line):
            m = re.match(r"^( *)- (.*)$", line)
            assert m and current is not None, f"row outside a section: {line!r}"
            fields = m.group(2).split("|", 5)
            assert len(fields) == 6, f"malformed row: {line!r}"
            current["rows"].append(
                {
                    "depth": len(m.group(1)) // 3,
                    "id": fields[0],
                    "theme": fields[1],
                    "parent": fields[2],
                    "priority": fields[3],
                    "status": fields[4],
                    "title": fields[5],
                }
            )
    return out


def section(tree: dict, section_id: str) -> dict:
    for s in tree["sections"]:
        if s["id"] == section_id:
            return s
    raise AssertionError(f"section {section_id!r} missing in {tree['sections']}")


# --------------------------------------------------------------------------
# 1. Happy path: fixture -> tree.md -> issue-tree -Check -> render
# --------------------------------------------------------------------------

HAPPY_ISSUES = [
    gh_issue(101, "Alpha main", labels=("theme:Core", "priority:P0")),
    gh_issue(102, "Alpha child", labels=("theme:Core",), parent=101),
    gh_issue(103, "Beta milestone", milestone=(2, "v2.0")),
    gh_issue(104, "Unlabeled"),
    gh_issue(105, "Closed done", state="CLOSED", state_reason="COMPLETED", labels=("theme:Core",)),
    gh_issue(106, "Closed dropped", state="CLOSED", state_reason="NOT_PLANNED"),
]


def test_happy_path_structure_gates_and_next(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, HAPPY_ISSUES)
    assert out.returncode == 0, out.stdout + out.stderr

    text = read_tree(repo)
    tree = parse_tree(text)

    # FILTER rides first (before summaries), single line, knob-composed.
    first = text.split("\n")[0]
    assert re.match(r"^FILTER\|is:issue AND created:>=\d{4}-\d{2}-\d{2}$", first)
    # SUMMARY key set and order, digits only, floor total = fetched.
    summary_line = text.split("\n")[1]
    assert summary_line.startswith(
        "SUMMARY|themes=3|issues=6|total=6|asOfEpoch="
    )
    assert re.search(
        r"\|asOfEpoch=\d{10}\|P0=1\|P1=0\|P2=0\|P3=0\|blocked=0\|cap=300\|lookback=365$",
        summary_line,
    )
    assert tree["summary"]["themes"] == 3 and tree["summary"]["issues"] == 6
    # §1.6 banner inputs: cap always; lookback only when the knob applied
    # (no temporal qualifier in this manifest's query).
    assert tree["summary"]["cap"] == 300
    assert tree["summary"]["lookback"] == 365

    # Section order is theme-id ordinal: M2 < T-core < acme/widgets issues.
    assert [s["id"] for s in tree["sections"]] == ["M2", "T-core", "acme/widgets issues"]

    # Nested child stays under its parent; closed rows sit after open rows.
    alpha = section(tree, "T-core")
    assert [(r["id"], r["depth"]) for r in alpha["rows"]] == [
        ("0101", 0),
        ("0102", 1),
        ("0105", 0),
    ]
    assert alpha["rows"][1]["parent"] == "0101"
    assert alpha["rows"][0]["parent"] == "-" and alpha["rows"][0]["priority"] == "P0"
    # Unlabeled rows carry the literal "none" priority field.
    fallback = section(tree, "acme/widgets issues")
    assert [r["id"] for r in fallback["rows"]] == ["0104", "0106"]
    assert fallback["rows"][0]["priority"] == "none"
    assert fallback["rows"][1]["status"] == "dropped"

    # NEXT = highest-priority actionable shown row.
    assert tree["next"] == ["0101", "T-core", "P0", "open", "Alpha main"]

    # Pipe both offline gates (github mode, per sketch 1.3).
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    assert "structurally consistent" in chk.stdout
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    assert "wrote .issues/tree.html" in rnd.stdout
    assert "fetched=6 shown=6 truncated=false total=6 (floor)" in out.stdout


# --------------------------------------------------------------------------
# 2. Promotion pairs (critique F.3 cross-theme, F.4.1 open-under-closed)
# --------------------------------------------------------------------------

def test_promotion_cross_theme_and_open_under_closed(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(201, "Closed parent", state="CLOSED", state_reason="COMPLETED",
                 labels=("theme:alpha",)),
        gh_issue(202, "Open child same theme", labels=("theme:alpha",), parent=201),
        gh_issue(203, "Open child other theme", labels=("theme:beta",), parent=201),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    # Both promotions warn (sync-log warnings).
    assert "issue #0202 is open under closed parent #0201" in out.stdout
    assert "issue #0203 (theme 'T-beta') is a sub-issue of #0201 (theme 'T-alpha')" in out.stdout
    assert "promoted to a root row of its own section" in out.stdout

    tree = parse_tree(read_tree(repo))
    assert [s["id"] for s in tree["sections"]] == ["T-alpha", "T-beta"]
    # Same-theme open child: root row of its section, parent kept as a hint,
    # sitting in the open region (before the closed parent).
    alpha = section(tree, "T-alpha")
    assert [(r["id"], r["depth"]) for r in alpha["rows"]] == [("0202", 0), ("0201", 0)]
    assert alpha["rows"][0]["parent"] == "0201"  # retained hint, depth 0
    # Cross-theme child: root row of ITS OWN section (grammar: theme ==
    # section id), not nested under the foreign parent.
    beta = section(tree, "T-beta")
    assert [(r["id"], r["depth"], r["parent"]) for r in beta["rows"]] == [
        ("0203", 0, "0201")
    ]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr


# --------------------------------------------------------------------------
# 3. cap+1 truncation flag (post-filter rule, F.1.3)
# --------------------------------------------------------------------------

def test_cap_plus_one_truncation_flag(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    five = [gh_issue(n, f"Issue {n}") for n in range(10, 15)]

    # Cap binds: fetch = cap+1 = 4, shown = cap = 3 -> truncated, floor total.
    repo = make_repo(tmp_path, manifest(treeMaxIssues=3), name="capped")
    out = sync(pwsh_exe, skill, repo, five)
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["issues"] == 3
    assert tree["summary"]["total"] == 4  # floor = fetched count
    assert "fetched=4 shown=3 truncated=true total=4 (floor)" in out.stdout
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr

    # Cap does not bind: no truncation flag, total = full fetch.
    repo2 = make_repo(tmp_path, manifest(treeMaxIssues=10), name="uncapped")
    out2 = sync(pwsh_exe, skill, repo2, five)
    assert out2.returncode == 0, out2.stdout + out2.stderr
    tree2 = parse_tree(read_tree(repo2))
    assert tree2["summary"]["issues"] == 5 and tree2["summary"]["total"] == 5
    assert "fetched=5 shown=5 truncated=false" in out2.stdout


# --------------------------------------------------------------------------
# 4. stateReason status mapping table + NEXT absent when nothing actionable
# --------------------------------------------------------------------------

def test_status_mapping_table_and_next_absent(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    issues = [
        gh_issue(301, "plain open"),
        gh_issue(302, "labelled progress", labels=("status:in-progress",)),
        gh_issue(303, "completed", state="CLOSED", state_reason="COMPLETED"),
        gh_issue(304, "not planned", state="CLOSED", state_reason="NOT_PLANNED"),
        # closed + completed: the status: label override applies to OPEN only.
        gh_issue(305, "closed but labelled", state="CLOSED", state_reason="COMPLETED",
                 labels=("status:dropped",)),
        gh_issue(306, "bogus label", labels=("status:bogus",)),
        gh_issue(307, "closed no reason", state="CLOSED", state_reason=None),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "status label 'status:bogus' is not one of open/in-progress/blocked/done/dropped" in out.stdout

    tree = parse_tree(read_tree(repo))
    rows = {r["id"]: r for s in tree["sections"] for r in s["rows"]}
    assert rows["0301"]["status"] == "open"
    assert rows["0302"]["status"] == "in-progress"
    assert rows["0303"]["status"] == "done"
    assert rows["0304"]["status"] == "dropped"
    assert rows["0305"]["status"] == "done", "override must not apply to closed issues"
    assert rows["0306"]["status"] == "open", "invalid label falls back to open"
    assert rows["0307"]["status"] == "done", "null stateReason defaults to done"
    assert tree["next"] is not None  # open rows exist here

    # All-closed repo -> no NEXT line at all.
    repo2 = make_repo(
        tmp_path,
        manifest(),
        name="closed-only",
    )
    closed = [
        gh_issue(311, "only done", state="CLOSED", state_reason="COMPLETED"),
        gh_issue(312, "only dropped", state="CLOSED", state_reason="NOT_PLANNED"),
    ]
    out2 = sync(pwsh_exe, skill, repo2, closed)
    assert out2.returncode == 0, out2.stdout + out2.stderr
    text2 = read_tree(repo2)
    assert not any(line.startswith("NEXT|") for line in text2.split("\n"))
    chk2 = run(pwsh_exe, skill, repo2, "issue-tree.ps1", "-Check")
    assert chk2.returncode == 0, chk2.stdout + chk2.stderr


# --------------------------------------------------------------------------
# 5. theme slug normalization + multiple theme: labels ordinal-first
# --------------------------------------------------------------------------

def test_theme_slug_normalization_and_ordinal_first(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(401, "upper spaced", labels=("theme:Foo Bar",)),
        gh_issue(402, "lower dashed", labels=("theme:foo-bar",)),
        gh_issue(403, "multi label", labels=("theme:zzz", "theme:aaa")),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    # theme:Foo Bar and theme:foo-bar are the SAME theme after normalization.
    assert "using 'theme:aaa' (ordinal-first)" in out.stdout

    tree = parse_tree(read_tree(repo))
    assert [s["id"] for s in tree["sections"]] == ["T-aaa", "T-foo-bar"]
    merged = section(tree, "T-foo-bar")
    assert [r["id"] for r in merged["rows"]] == ["0401", "0402"]
    assert tree["summary"]["themes"] == 2 and tree["summary"]["issues"] == 3

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 6. FILTER line -> dataJson.filter -> HTML (renderer extension E)
# --------------------------------------------------------------------------

def test_filter_line_roundtrip_into_html(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    # Contains quotes, spaces and a </script> attempt: escaping must be the
    # renderer's ConvertTo-JsString path, never raw interpolation.
    query = 'is:issue label:"tech debt" </script>'
    issues = [gh_issue(501, "Filtered issue")]
    repo = make_repo(tmp_path, manifest(issueQuery=query))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    # Type class present in the user query -> knob suppressed and logged.
    assert "skipped knobs: is:issue" in out.stdout

    text = read_tree(repo)
    tree = parse_tree(text)
    expected = re.compile(r'^is:issue label:"tech debt" </script> AND created:>=\d{4}-\d{2}-\d{2}$')
    assert tree["filter"] is not None and expected.match(tree["filter"]), tree["filter"]
    assert text.split("\n")[0].startswith("FILTER|")

    # The FILTER line is not data for issue-tree's parser (still green) ...
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr

    # ... but the renderer picks it up into dataJson.filter, escaped.
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    html = (repo / ".issues" / "tree.html").read_text(encoding="utf-8")
    m = re.search(
        r'<script id="issue-tree-data" type="application/json">(.*?)</script>', html, re.S
    )
    assert m, "embedded data script tag missing"
    payload = m.group(1)
    data = json.loads(payload)
    assert data["filter"] == tree["filter"]
    # No raw '<' in the payload: ConvertTo-JsString neutralized </script>.
    assert "</script" not in payload
    assert "<" not in payload.replace("\\u003c", "").replace("\\u003e", "")
    assert r"</script>" in html, "the real closing tags of the template remain"


# --------------------------------------------------------------------------
# 7. @me -> login marker (disclosure in FILTER only) + resolution failure
# --------------------------------------------------------------------------

def test_me_marker_resolution_and_failure(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    issues = [gh_issue(601, "Assigned to me")]
    repo = make_repo(tmp_path, manifest(issueQuery="assignee:@me"))
    out = sync(pwsh_exe, skill, repo, issues, viewer="arisng")
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    assert tree["filter"].startswith("assignee:@me AND is:issue AND created:>=")
    assert tree["filter"].endswith(" @me→arisng"), tree["filter"]

    # Resolution failure fails loud and writes nothing.
    repo2 = make_repo(tmp_path, manifest(issueQuery="assignee:@me"), name="no-viewer")
    out2 = sync(pwsh_exe, skill, repo2, issues)  # fixture has no viewerLogin
    assert out2.returncode == 1, out2.stdout + out2.stderr
    assert "viewer login could not be resolved" in out2.stdout
    assert not (repo2 / ".issues" / "tree.md").exists()


# --------------------------------------------------------------------------
# 8. CRLF/control-char sanitization (audit C3 - silent truncation)
# --------------------------------------------------------------------------

def test_control_chars_sanitized(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    issues = [
        gh_issue(701, "Line1\r\nLine2\x07End"),
        gh_issue(702, "label control", labels=("priority:P1\x02",)),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr

    text = read_tree(repo)
    assert "\r" not in text and "\x07" not in text and "\x02" not in text
    assert "Line1Line2End" in text, "control chars are stripped, not line-breaked"
    # The sanitized label is still recognized as priority:P1.
    assert "P1=1" in text.split("\n")[1]
    # Title stayed on ONE line: tree line count matches the grammar shape.
    tree = parse_tree(text)
    assert tree["summary"]["issues"] == 2

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 9. subIssuesSummary shortfall + node shape warnings (F.0.2)
# --------------------------------------------------------------------------

def test_subissuessummary_shortfall_and_shape_warnings(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        # Declares 3 sub-issues; only 2 node entries, 0 children fetched.
        gh_issue(801, "Epic", sub_issues=[{"number": 802}, {"number": 803}],
                 sub_summary_total=3),
        gh_issue(804, "shape drift", sub_issues=[{"title": "no number here"}],
                 sub_summary_total=1),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert (
        "issue #0801: subIssuesSummary.total=3 but only 0 child issue(s) in the fetched set"
        in out.stdout
    )
    assert "sub-issue node without a 'number' field (gh shape drift)" in out.stdout
    # Warnings never break the artifact.
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 10. parent:<NNNN> labels warn + native hierarchy still nests
# --------------------------------------------------------------------------

def test_parent_label_warns_native_hierarchy_works(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(901, "labelled parent", labels=("parent:0009",)),
        gh_issue(902, "native child", parent=901),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "label 'parent:0009' is unsupported (native gh sub-issues only) - ignored" in out.stdout

    tree = parse_tree(read_tree(repo))
    fallback = section(tree, "acme/widgets issues")
    # Label convention ignored (row is a root with '-'); native parent nests.
    assert [(r["id"], r["depth"], r["parent"]) for r in fallback["rows"]] == [
        ("0901", 0, "-"),
        ("0902", 1, "0901"),
    ]
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 11. Compound guard refusals (sketch 1.2, message style of the siblings)
# --------------------------------------------------------------------------

def test_guard_refusals(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    cases = (
        (
            {"schemaVersion": 1, "tracker": "local-markdown", "issuesDir": ".issues"},
            "sync-github-tree: tracker 'local-markdown' is not github",
        ),
        (
            {"schemaVersion": 1, "tracker": "github", "treeSource": "local-markdown",
             "repo": REPO},
            "sync-github-tree: treeSource is 'local-markdown' - set treeSource: 'github'",
        ),
        (
            {"schemaVersion": 1, "tracker": "azure-devops", "org": "o", "project": "p"},
            "sync-github-tree: tracker 'azure-devops' is not github",
        ),
    )
    for i, (m, needle) in enumerate(cases):
        repo = make_repo(tmp_path, m, name=f"guard-{i}")
        out = run(pwsh_exe, skill, repo, "sync-github-tree.ps1")
        assert out.returncode == 1, out.stdout + out.stderr
        assert needle in out.stdout, out.stdout
        assert not (repo / ".issues" / "tree.md").exists(), "refusal must write nothing"

    # Missing manifest fails closed with a pointer to the writer.
    repo = tmp_path / "no-manifest"
    repo.mkdir()
    out = run(pwsh_exe, skill, repo, "sync-github-tree.ps1")
    assert out.returncode == 1
    assert "issue-tracker.json not found" in out.stdout


# --------------------------------------------------------------------------
# 12. Exact count (issueQuery only) + floor fallback with warning
# --------------------------------------------------------------------------

def test_exact_count_and_floor_fallback(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    issues = [gh_issue(1001, "One"), gh_issue(1002, "Two")]

    # exactCount stands in for the GraphQL call -> SUMMARY total is exact.
    repo = make_repo(tmp_path, manifest(issueQuery="label:x"), name="exact")
    out = sync(pwsh_exe, skill, repo, issues, exact_count=42)
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["total"] == 42
    assert "total=42 (exact)" in out.stdout

    # Count unavailable -> fetched floor + flagged warning.
    repo2 = make_repo(tmp_path, manifest(issueQuery="label:x"), name="floor")
    out2 = sync(pwsh_exe, skill, repo2, issues)
    assert out2.returncode == 0, out2.stdout + out2.stderr
    tree2 = parse_tree(read_tree(repo2))
    assert tree2["summary"]["total"] == 2
    assert "exact count unavailable (fixture.exactCount absent) - using fetched floor" in out2.stdout
    assert "total=2 (floor)" in out2.stdout

    # Without issueQuery the count call is never consulted (documented
    # policy): exactCount in the fixture is ignored, floor wins.
    repo3 = make_repo(tmp_path, manifest(), name="no-query")
    out3 = sync(pwsh_exe, skill, repo3, issues, exact_count=99)
    assert out3.returncode == 0, out3.stdout + out3.stderr
    assert parse_tree(read_tree(repo3))["summary"]["total"] == 2


# --------------------------------------------------------------------------
# 13. Priority ordering: labeled first (rank), then unlabeled by number
# --------------------------------------------------------------------------

def test_priority_ordering_and_none_field(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    issues = [
        gh_issue(801, "unlabeled"),
        gh_issue(802, "labeled p3", labels=("priority:P3",)),
        gh_issue(803, "labeled p0", labels=("priority:P0",)),
        gh_issue(804, "labeled p1", labels=("priority:P1",)),
    ]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    rows = tree["sections"][0]["rows"]
    # priority -> order -> number; unlabeled after every labeled row, by number.
    assert [r["id"] for r in rows] == ["0803", "0804", "0802", "0801"]
    assert rows[-1]["priority"] == "none"
    # P buckets count labeled rows only.
    assert tree["summary"]["P0"] == 1
    assert tree["summary"]["P1"] == 1
    assert tree["summary"]["P2"] == 0
    assert tree["summary"]["P3"] == 1


# --------------------------------------------------------------------------
# 14. treeMinPriority floor (post-fetch client filter)
# --------------------------------------------------------------------------

def test_min_priority_floor_filters_client_side(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(911, "p0", labels=("priority:P0",)),
        gh_issue(912, "p1", labels=("priority:P1",)),
        gh_issue(913, "p2", labels=("priority:P2",)),
        gh_issue(914, "unlabeled"),
    ]
    repo = make_repo(tmp_path, manifest(treeMinPriority="P1"))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "treeMinPriority P1 dropped 2 fetched issue(s)" in out.stdout
    assert "fetched=4 shown=2 truncated=false" in out.stdout

    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["issues"] == 2
    assert tree["summary"]["total"] == 4  # floor = fetched, before the filter
    rows = {r["id"] for s in tree["sections"] for r in s["rows"]}
    assert rows == {"0911", "0912"}
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 15. -Repo override (regression: PS variables are case-insensitive, so a
#     local $repo once clobbered the -Repo param - caught by the live smoke)
# --------------------------------------------------------------------------

def test_repo_override_param(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    repo = make_repo(tmp_path, manifest())
    fixture = write_fixture(repo, [gh_issue(1234, "Override issue")])
    out = run(
        pwsh_exe,
        skill,
        repo,
        "sync-github-tree.ps1",
        "-FromJson",
        str(fixture),
        "-Repo",
        "other/repo",
    )
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    # The override owns both the fetch target and the fallback bucket id.
    assert [s["id"] for s in tree["sections"]] == ["other/repo issues"]
    assert tree["sections"][0]["rows"][0]["id"] == "1234"
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 16. Empty fetch still emits a renderable fallback section
# --------------------------------------------------------------------------

def test_empty_fetch_emits_fallback_section(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, [])
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["themes"] == 1
    assert tree["summary"]["issues"] == 0
    assert tree["summary"]["total"] == 0
    assert tree["next"] is None
    assert [s["id"] for s in tree["sections"]] == [f"{REPO} issues"]
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr


# --------------------------------------------------------------------------
# 17. SUMMARY cap/lookback keys (banner inputs): cap always; lookback only
#     when the knob applied - a temporal issueQuery suppresses the append
# --------------------------------------------------------------------------

def test_summary_cap_and_lookback_keys(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    # No issueQuery -> the lookback knob applies and both keys ship.
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, [gh_issue(1301, "Plain")])
    assert out.returncode == 0, out.stdout + out.stderr
    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["cap"] == 300
    assert tree["summary"]["lookback"] == 365

    # Temporal qualifier in issueQuery -> created: knob suppressed (the lib
    # records the skipped append) -> lookback key omitted, cap still ships.
    repo2 = make_repo(
        tmp_path, manifest(issueQuery="updated:<2026-01-01 label:x"), name="temporal"
    )
    out2 = sync(pwsh_exe, skill, repo2, [gh_issue(1302, "Windowed")])
    assert out2.returncode == 0, out2.stdout + out2.stderr
    tree2 = parse_tree(read_tree(repo2))
    assert tree2["summary"]["cap"] == 300
    assert "lookback" not in tree2["summary"], "suppressed knob must not emit lookback"
    assert "created:>" not in tree2["filter"], tree2["filter"]

    # Both shapes stay digits-only grammar (single SUMMARY line, cap last).
    summary_lines = [
        ln for ln in read_tree(repo2).split("\n") if ln.startswith("SUMMARY|")
    ]
    assert len(summary_lines) == 1
    assert re.search(r"\|cap=300$", summary_lines[0]), summary_lines[0]
    chk = run(pwsh_exe, skill, repo2, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
