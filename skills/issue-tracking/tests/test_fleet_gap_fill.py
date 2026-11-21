"""Section-5 coverage gap-fill tests for the github tree pipeline.

Method (FLEET TASK F7): every checklist item in
github-tree-adaptation-sketch.md section 5 was first mapped to the six
existing test files; this file adds ONLY the items with no covering test:

 - C1 half of the cross-theme pair: a NESTED foreign-theme row fails render
   and issue-tree -Check (C2's promoted half is already covered by
   test_github_guard_and_hardening.py);
 - sync -Check offline-deferred pointer (github-mode -Check semantics);
 - hostile titles end-to-end through sync -> tree.md -> -Check -> render ->
   render -Check (newline/CR, pipes, </script>, spoofed SUMMARY| second
   line) with full title text preserved in the embedded JSON;
 - asOf anchoring: the FILTER window derives from the stored asOfEpoch, and
   the committed HTML is byte-stable across re-renders (no wall clock);
 - post-filter truncation (section 1.5 step 5c): fetch hits cap+1 but
   treeMinPriority drops rows -> shown < cap -> truncated=false;
 - banner/chip state machine at cap with zero closed rows: rendered banner
   carries no closed clause while the template's hide-closed control and
   the data-driven chip filter are present;
 - open child of closed parent visible AFTER the cap binds (F.4.1);
 - cheat-sheet E2E pairs with no dedicated test: sort:created-asc selection
   (oldest rows survive the cap, row order = gh's order) and the backlog-rot
   scenario (temporal query suppresses the created: append AND a 2-year-old
   issue still renders);
 - section 5 G regressions, offline via a hermetic `gh` shim prepended to
   PATH (no network, no real gh): --state all in both treeIncludeClosed
   modes, the W3 type-vs-state split (is:issue + treeIncludeClosed=false ->
   zero closed rows), and count parity (GraphQL type:ISSUE_ADVANCED only,
   never plain type:ISSUE, q == "( <list search> ) repo:... type:issue").

Pattern reused from test_github_guard_and_hardening.py: copy the skill into
tmp_path, shell out to pwsh -File from a throwaway repo; sync fixtures via
-fromJson per test_sync_github_tree.py. Covered items are deliberately NOT
duplicated here.

Origin: FLEET TASK F7 (2026-11-21), per github-tree-adaptation-sketch.md
section 5 (decision-driven, cheat-sheet and G-regression bullets).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]
REPO = "acme/widgets"

# The gh shim: records every argv line to GH_SHIM_LOG, serves canned JSON
# from GH_SHIM_ISSUES, and applies exactly one honest gh semantic so the W3
# split is observable offline: `is:open` in the search string keeps OPEN
# rows only. `is:issue` alone does NOT constrain state (the W3 leak).
SHIM_PY = r'''
import json, os, sys


def _load(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _select(query):
    issues = _load(os.environ.get("GH_SHIM_ISSUES"))
    if "is:open" in query:
        return [x for x in issues if str(x.get("state", "")).upper() == "OPEN"]
    return issues


def main():
    args = sys.argv[1:]
    log = os.environ.get("GH_SHIM_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(args) + "\n")
    if len(args) >= 2 and args[0] == "api" and args[1] == "graphql":
        # Exact-count stand-in: same population rule as the list fetch.
        q = ""
        for a in args:
            if a.startswith("q="):
                q = a[2:]
        sys.stdout.write(str(len(_select(q))))
        return
    if len(args) >= 2 and args[0] == "issue" and args[1] == "list":
        search = ""
        for i, a in enumerate(args):
            if a == "--search" and i + 1 < len(args):
                search = args[i + 1]
        sys.stdout.write(json.dumps(_select(search)))
        return
    sys.stdout.write("[]")


main()
'''


@pytest.fixture(scope="session")
def pwsh_exe() -> str:
    exe = shutil.which("pwsh")
    if not exe:
        pytest.skip("pwsh not on PATH (skill scripts are PowerShell)")
    return exe


def run_script(
    pwsh: str,
    script: Path,
    args: tuple,
    cwd: Path,
    env: dict | None = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [pwsh, "-NoProfile", "-File", str(script), *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        env=env,
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


def make_repo(tmp_path: Path, m: dict, tree: str | None = None, name: str = "repo") -> Path:
    repo = tmp_path / name
    (repo / ".github").mkdir(parents=True)
    (repo / ".github" / "issue-tracker.json").write_text(json.dumps(m), encoding="utf-8")
    if tree is not None:
        (repo / ".issues").mkdir()
        (repo / ".issues" / "tree.md").write_text(tree, encoding="utf-8")
    return repo


def gh_issue(
    number: int,
    title: str = "Issue",
    state: str = "OPEN",
    state_reason: str | None = None,
    labels: tuple[str, ...] = (),
    parent: int | None = None,
    created: str = "2026-11-01T00:00:00Z",
) -> dict:
    """One row in gh issue list --json shape (see test_sync_github_tree.py)."""
    return {
        "number": number,
        "title": title,
        "state": state,
        "stateReason": state_reason,
        "labels": [
            {"id": "L_x", "name": n, "description": None, "color": "cccccc"} for n in labels
        ],
        "milestone": None,
        "parent": None if parent is None else {"number": parent, "title": "parent"},
        "subIssues": {"nodes": [], "totalCount": 0},
        "subIssuesSummary": {"completed": 0, "percentCompleted": 0, "total": 0},
        "createdAt": created,
        "updatedAt": created,
        "closedAt": "2026-11-02T00:00:00Z" if state == "CLOSED" else None,
    }


def run(pwsh: str, skill: Path, repo: Path, script: str, *args: str) -> subprocess.CompletedProcess:
    return run_script(pwsh, skill / "scripts" / script, args, repo)


def sync(
    pwsh: str,
    skill: Path,
    repo: Path,
    issues: list,
    exact_count=None,
) -> subprocess.CompletedProcess:
    payload: dict = {"issues": issues}
    if exact_count is not None:
        payload["exactCount"] = exact_count
    fixture = repo / "fixture.json"
    fixture.write_text(json.dumps(payload), encoding="utf-8")
    return run(pwsh, skill, repo, "sync-github-tree.ps1", "-FromJson", str(fixture))


def read_tree(repo: Path) -> str:
    return (repo / ".issues" / "tree.md").read_text(encoding="utf-8")


def parse_tree(text: str) -> dict:
    """Minimal grammar reader: filter, summary, rows (with section + depth)."""
    out: dict = {"filter": None, "summary": {}, "rows": []}
    section = None
    for line in text.split("\n"):
        if line.startswith("FILTER|"):
            out["filter"] = line[len("FILTER|") :]
        elif line.startswith("SUMMARY|"):
            for seg in line.split("|")[1:]:
                k, v = seg.split("=")
                out["summary"][k] = int(v)
        elif line.startswith("## THEME|"):
            section = line.split("|", 4)[1]
        elif re.match(r"^ *- ", line):
            prefix = line.split("- ", 1)[0]
            fields = line.split("- ", 1)[1].split("|", 5)
            assert len(fields) == 6, f"malformed row: {line!r}"
            out["rows"].append(
                {
                    "section": section,
                    "depth": len(prefix) // 3,
                    "id": fields[0],
                    "theme": fields[1],
                    "parent": fields[2],
                    "priority": fields[3],
                    "status": fields[4],
                    "title": fields[5],
                }
            )
    return out


def data_json(html: str) -> dict:
    m = re.search(
        r'<script id="issue-tree-data" type="application/json">(.*?)</script>', html, re.S
    )
    assert m, "embedded data script tag missing"
    data_json.payload = m.group(1)
    return json.loads(m.group(1))


def row_titles(data: dict) -> list[str]:
    titles: list[str] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            if "title" in node and "status" in node:
                titles.append(node["title"])
            for child in node.get("children") or []:
                walk(child)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data.get("themes") or [])
    walk(data.get("next"))
    return titles


def make_gh_shim(tmp_path: Path) -> tuple[dict, Path]:
    """Hermetic `gh` on PATH: argv recorder + canned JSON, zero network."""
    shim_dir = tmp_path / "gh-shim"
    shim_dir.mkdir(parents=True, exist_ok=True)
    shim_py = shim_dir / "gh_shim.py"
    shim_py.write_text(SHIM_PY, encoding="utf-8")
    exe = sys.executable.replace("%", "%%")
    # Windows resolves gh via PATHEXT -> gh.cmd; POSIX uses the sh script.
    (shim_dir / "gh.cmd").write_text(
        f'@echo off\r\n"{exe}" "{shim_py}" %*\r\n', encoding="utf-8"
    )
    sh = shim_dir / "gh"
    sh.write_text(f'#!/bin/sh\nexec "{exe}" "{shim_py}" "$@"\n', encoding="utf-8")
    os.chmod(sh, 0o755)
    env = dict(os.environ)
    env["PATH"] = str(shim_dir) + os.pathsep + env.get("PATH", "")
    return env, shim_dir


def shim_calls(log: Path) -> list[list[str]]:
    assert log.exists(), "gh shim never ran - the real gh would have been used"
    return [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines() if line]


# --------------------------------------------------------------------------
# 1. C1: nested cross-theme row fails render and -Check (C2 promoted half is
#    covered by test_github_guard_and_hardening.py - not duplicated here)
# --------------------------------------------------------------------------

CROSS_THEME_NESTED = (
    "SUMMARY|themes=1|issues=2|total=2|asOfEpoch=1763630400"
    "|P0=0|P1=2|P2=0|P3=0|blocked=0\n"
    "\n"
    "## THEME|T-alpha|P1|open|Alpha theme\n"
    "\n"
    "- 0001|T-alpha|-|P1|open|Parent in alpha\n"
    "   - 0002|T-beta|0001|P1|open|Foreign nested child\n"
)


def test_cross_theme_nested_row_fails_render_and_check(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # Sketch 5, C1/C2 pair: nesting a cross-theme child hard-fails the
    # theme == section grammar (exit 1); promotion is the legal alternative.
    repo = make_repo(tmp_path, manifest(), tree=CROSS_THEME_NESTED)
    needle = "theme 'T-beta' != section 'T-alpha'"
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 1, rnd.stdout + rnd.stderr
    assert needle in rnd.stdout, rnd.stdout
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 1, chk.stdout + chk.stderr
    assert needle in chk.stdout, chk.stdout


# --------------------------------------------------------------------------
# 2. github-mode -Check semantics: sync's own -Check never validates offline,
#    it points at the two real gates and writes nothing
# --------------------------------------------------------------------------

def test_sync_check_is_offline_deferred(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    repo = make_repo(tmp_path, manifest())
    out = run(pwsh_exe, skill, repo, "sync-github-tree.ps1", "-Check")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "offline-deferred" in out.stdout, out.stdout
    assert "issue-tree.ps1 -Check" in out.stdout, out.stdout
    assert "render-issue-tree.ps1 -Check" in out.stdout, out.stdout
    assert not (repo / ".issues" / "tree.md").exists(), "a check must never write the tree"


# --------------------------------------------------------------------------
# 3. Hostile titles end-to-end: sync -> tree.md -> -Check -> render ->
#    render -Check, full title text preserved in the embedded JSON
# --------------------------------------------------------------------------

def test_hostile_titles_survive_sync_to_html(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(701, "Line1\r\nLine2"),  # newline/CR: must stay ONE row
        gh_issue(702, "Pipe | d | elims"),  # pipes ride the title field
        gh_issue(703, '</script> "quoted" C:\\dir'),  # JSON breakout attempt
        gh_issue(704, "real\nSUMMARY|issues=999|evil=1"),  # spoofed 2nd line
    ]
    # Hostile filter too, so the final render -Check byte-compares the full
    # hostile payload (section 5: "banner filter echo ... byte-compare green").
    query = 'label:"tech debt" </script>'
    repo = make_repo(tmp_path, manifest(issueQuery=query))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr

    text = read_tree(repo)
    # The spoofed SUMMARY never becomes a grammar line: exactly one, on line 2.
    summary_lines = [ln for ln in text.split("\n") if ln.startswith("SUMMARY|")]
    assert len(summary_lines) == 1, summary_lines
    tree = parse_tree(text)
    assert tree["summary"]["issues"] == 4, tree["summary"]
    assert tree["summary"]["total"] == 4, tree["summary"]
    rows = {r["id"]: r for r in tree["rows"]}
    assert set(rows) == {"0701", "0702", "0703", "0704"}
    assert rows["0701"]["title"] == "Line1Line2", rows["0701"]
    assert rows["0702"]["title"] == "Pipe | d | elims", rows["0702"]
    assert rows["0703"]["title"] == '</script> "quoted" C:\\dir', rows["0703"]
    assert rows["0704"]["title"] == "realSUMMARY|issues=999|evil=1", rows["0704"]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr

    html = (repo / ".issues" / "tree.html").read_text(encoding="utf-8")
    data = data_json(html)  # sets data_json.payload = the raw embedded JSON
    payload = data_json.payload
    assert json.loads(payload) == data
    # No raw breakout fragment survives into the script tag...
    assert "</script" not in payload
    # ... but parsing the payload yields the full title text, unaltered.
    titles = set(row_titles(data))
    for expected in (
        "Line1Line2",
        "Pipe | d | elims",
        '</script> "quoted" C:\\dir',
        "realSUMMARY|issues=999|evil=1",
    ):
        assert expected in titles, f"{expected!r} missing from {titles}"
    assert data["summary"]["issues"] == 4, data["summary"]

    # Byte-compare stays green over the hostile filter + hostile titles.
    chk2 = run(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")
    assert chk2.returncode == 0, chk2.stdout + chk2.stderr
    assert "fresh" in chk2.stdout, chk2.stdout


# --------------------------------------------------------------------------
# 4. asOf anchoring: window derives from the stored epoch; the committed
#    HTML is a frozen snapshot (byte-stable re-render, no wall clock)
# --------------------------------------------------------------------------

def test_asof_anchor_is_frozen_across_re_renders(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [gh_issue(1101, "Anchor one"), gh_issue(1102, "Anchor two")]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr

    text = read_tree(repo)
    summary_line = text.split("\n")[1]
    m = re.search(r"asOfEpoch=(\d+)", summary_line)
    assert m, summary_line
    as_of = int(m.group(1))
    filter_line = text.split("\n")[0]
    assert filter_line.startswith("FILTER|"), filter_line
    # The lookback window is anchored to the STORED asOf, not wall clock:
    # date(asOf - treeLookbackDays) is the only created:> value allowed.
    expected_date = (
        datetime.fromtimestamp(as_of, timezone.utc) - timedelta(days=365)
    ).strftime("%Y-%m-%d")
    assert f"created:>={expected_date}" in filter_line, filter_line

    # Frozen snapshot: re-rendering later yields byte-identical HTML, and
    # -Check proves it against the committed tree - no clock can move it.
    rnd1 = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd1.returncode == 0, rnd1.stdout + rnd1.stderr
    html1 = (repo / ".issues" / "tree.html").read_bytes()
    rnd2 = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd2.returncode == 0, rnd2.stdout + rnd2.stderr
    html2 = (repo / ".issues" / "tree.html").read_bytes()
    assert html1 == html2, "render output must not depend on wall clock"
    chk = run(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    assert "fresh" in chk.stdout, chk.stdout

    html = html1.decode("utf-8")
    assert f'"asOfEpoch":{as_of}' in html, "stored epoch must ride dataJson.summary"
    assert "Date.now" not in html, "no wall-clock read may reach the artifact"
    assert "new Date(t * 1000)" in html, "the as-of date formats the stored epoch only"


# --------------------------------------------------------------------------
# 5. Post-filter truncation rule (section 1.5 step 5c): fetch hits cap+1 but
#    treeMinPriority drops rows -> shown < cap -> truncated=false
# --------------------------------------------------------------------------

def test_post_filter_truncation_false_when_floor_drops_rows(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(931, "p1 passes", labels=("priority:P1",)),
        gh_issue(932, "p2 dropped by floor", labels=("priority:P2",)),
        gh_issue(933, "p0 passes", labels=("priority:P0",)),
        gh_issue(934, "unlabeled dropped by floor"),
    ]
    # cap=3, fetch limit = cap+1 = 4 (fixture sliced like gh --limit), floor
    # P1 drops 2 rows -> shown=2 < cap -> the flag must stay FALSE even
    # though the raw fetch hit its limit (v2's fetched==cap misfire, F.1.3).
    repo = make_repo(tmp_path, manifest(treeMaxIssues=3, treeMinPriority="P1"))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "treeMinPriority P1 dropped 2 fetched issue(s)" in out.stdout, out.stdout
    assert "fetched=4 shown=2 truncated=false total=4 (floor)" in out.stdout, out.stdout

    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["issues"] == 2, tree["summary"]
    assert tree["summary"]["total"] == 4, tree["summary"]  # floor = raw fetch
    assert {r["id"] for r in tree["rows"]} == {"0931", "0933"}

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr


# --------------------------------------------------------------------------
# 6. Banner/chip state machine at cap with ZERO closed rows (section 5,
#    section 1.6): banner has no closed clause; hide-closed control present
# --------------------------------------------------------------------------

def test_banner_omits_closed_clause_at_cap_with_zero_closed_rows(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # The literal section-5 shape: >=300 open issues, cap 300 binds, zero
    # closed rows survive -> the banner may not promise a closed control.
    issues = [gh_issue(n, f"Open issue {n}") for n in range(1201, 1201 + 301)]
    repo = make_repo(tmp_path, manifest())
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr

    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["issues"] == 300, tree["summary"]  # at cap
    assert tree["summary"]["total"] == 301, tree["summary"]  # cap+1 floor
    assert {r["status"] for r in tree["rows"]} == {"open"}, "zero closed rows"

    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    html = (repo / ".issues" / "tree.html").read_text(encoding="utf-8")

    # Static assertion on the rendered banner builder: with zero closed rows
    # it must carry no closed clause at all (section 1.6's conditional
    # "closed: K shown" must stay absent), while its snapshot inputs exist.
    m = re.search(r"\(function renderBanner\(\) \{(.*?)\}\)\(\);", html, re.S)
    assert m, "renderBanner builder missing from rendered HTML"
    banner_js = m.group(1)
    assert "closed" not in banner_js.lower(), banner_js
    assert '"total" in summary' in banner_js, banner_js
    assert '"asOfEpoch" in summary' in banner_js, banner_js

    # The dedicated exclusive control still ships in the rendered artifact,
    # and the status chips are data-driven (no done/dropped rows -> those
    # chips never render at runtime).
    assert 'id="hide-closed"' in html, "hide-closed control missing"
    assert "presentStatuses = STATUSES.filter" in html, "chips must be data-driven"
    data = data_json(html)
    assert data["summary"]["issues"] == 300, data["summary"]
    statuses = {r["status"] for r in tree["rows"]}
    assert statuses.isdisjoint({"done", "dropped"})


# --------------------------------------------------------------------------
# 7. F.4.1: open child of a closed parent is promoted AND visible after the
#    cap binds (promotion alone is covered; the cap interaction is not)
# --------------------------------------------------------------------------

def test_open_child_of_closed_parent_survives_the_cap(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(
            951,
            "Closed parent",
            state="CLOSED",
            state_reason="COMPLETED",
            labels=("theme:alpha",),
        ),
        gh_issue(952, "Open child", labels=("theme:alpha",), parent=951),
        gh_issue(953, "Other open", labels=("theme:alpha",)),
    ]
    # cap=2: open region (promoted 952 + 953) fills the cap; the closed
    # parent 951 falls off the end - the open child must remain visible.
    repo = make_repo(tmp_path, manifest(treeMaxIssues=2))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr
    assert "issue #0952 is open under closed parent #0951" in out.stdout, out.stdout

    tree = parse_tree(read_tree(repo))
    rows = {r["id"]: r for r in tree["rows"]}
    assert set(rows) == {"0952", "0953"}, rows
    assert rows["0952"]["depth"] == 0 and rows["0952"]["parent"] == "0951"
    assert rows["0952"]["status"] == "open"
    assert tree["summary"]["issues"] == 2, tree["summary"]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr


# --------------------------------------------------------------------------
# 8. G regression: --state all construction in both treeIncludeClosed modes
#    (gh never arbitrates state - it lives only in the composed query)
# --------------------------------------------------------------------------

def test_gh_state_all_in_both_include_closed_modes(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    env, _ = make_gh_shim(tmp_path)
    canned = write_canned(tmp_path, [gh_issue(961, "Open"), gh_issue(962, "Closed old",
                                                                  state="CLOSED",
                                                                  state_reason="COMPLETED")])
    for label, include_closed in (("closed-true", True), ("closed-false", False)):
        env = dict(env)
        env["GH_SHIM_LOG"] = str(tmp_path / f"gh-{label}.log")
        env["GH_SHIM_ISSUES"] = str(canned)
        repo = make_repo(tmp_path, manifest(treeIncludeClosed=include_closed),
                         name=f"state-{label}")
        out = run_script(
            pwsh_exe, skill / "scripts" / "sync-github-tree.ps1", (), repo, env=env
        )
        assert out.returncode == 0, out.stdout + out.stderr

        calls = shim_calls(tmp_path / f"gh-{label}.log")
        list_args = next(c for c in calls if c[:2] == ["issue", "list"])
        # The injected-state forms are what G-R.2 forbids: gh arbitrates
        # asymmetrically for anything but --state all.
        i = list_args.index("--state")
        assert list_args[i + 1] == "all", list_args
        search = list_args[list_args.index("--search") + 1]
        # State lives only in the composed query: is:open appears iff
        # treeIncludeClosed is false (and gh is told nothing either way).
        if include_closed:
            assert "is:open" not in search, search
        else:
            assert "is:open" in search, search


def write_canned(tmp_path: Path, issues: list) -> Path:
    path = tmp_path / "canned-issues.json"
    path.write_text(json.dumps(issues), encoding="utf-8")
    return path


# --------------------------------------------------------------------------
# 9. G regression: type-vs-state split (W3) end-to-end - is:issue present +
#    treeIncludeClosed=false must yield ZERO closed rows
# --------------------------------------------------------------------------

def test_gh_type_state_split_yields_zero_closed_rows(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    env, _ = make_gh_shim(tmp_path)
    env["GH_SHIM_LOG"] = str(tmp_path / "gh-w3.log")
    env["GH_SHIM_ISSUES"] = str(
        write_canned(
            tmp_path,
            [
                gh_issue(971, "Stays open"),
                gh_issue(972, "Must not leak", state="CLOSED", state_reason="COMPLETED"),
            ],
        )
    )
    # W3 premise: the membership query carries the TYPE class only; the
    # sync must append the STATE class (is:open) because includeClosed is
    # false. The shim filters on is:open exactly like gh would - if the
    # append ever regresses, the closed row leaks into the tree and fails
    # the zero-closed assertion below.
    repo = make_repo(tmp_path, manifest(issueQuery="is:issue", treeIncludeClosed=False))
    out = run_script(pwsh_exe, skill / "scripts" / "sync-github-tree.ps1", (), repo, env=env)
    assert out.returncode == 0, out.stdout + out.stderr

    calls = shim_calls(tmp_path / "gh-w3.log")
    list_args = next(c for c in calls if c[:2] == ["issue", "list"])
    search = list_args[list_args.index("--search") + 1]
    assert "is:issue" in search, search  # type class from the query
    assert "is:open" in search, search  # state class appended by the sync

    tree = parse_tree(read_tree(repo))
    assert tree["filter"] is not None and "is:open" in tree["filter"], tree["filter"]
    assert {r["id"] for r in tree["rows"]} == {"0971"}, tree["rows"]
    assert {r["status"] for r in tree["rows"]} == {"open"}, tree["rows"]
    assert tree["summary"]["issues"] == 1, tree["summary"]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 10. G regression: exact-count parity - GraphQL ISSUE_ADVANCED only (never
#     plain type:ISSUE) and q == "( <list search> ) repo:<owner/name> type:issue"
# --------------------------------------------------------------------------

def test_gh_count_parity_uses_issue_advanced_only(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    env, _ = make_gh_shim(tmp_path)
    env["GH_SHIM_LOG"] = str(tmp_path / "gh-count.log")
    env["GH_SHIM_ISSUES"] = str(
        write_canned(
            tmp_path,
            [
                gh_issue(981, "One"),
                gh_issue(982, "Two"),
                gh_issue(983, "Three", state="CLOSED", state_reason="NOT_PLANNED"),
            ],
        )
    )
    repo = make_repo(tmp_path, manifest(issueQuery="label:x"))
    out = run_script(pwsh_exe, skill / "scripts" / "sync-github-tree.ps1", (), repo, env=env)
    assert out.returncode == 0, out.stdout + out.stderr

    calls = shim_calls(tmp_path / "gh-count.log")
    assert [c[:2] for c in calls] == [["issue", "list"], ["api", "graphql"]], calls
    list_args = calls[0]
    search = list_args[list_args.index("--search") + 1]
    gql = calls[1]
    doc = next(a[len("query=") :] for a in gql if a.startswith("query="))
    q_value = next(a[len("q=") :] for a in gql if a.startswith("q="))

    # ISSUE_ADVANCED is the only search type that survives qualifier-OR;
    # a plain type:ISSUE enum silently returns 0 (the silent-zero trap).
    assert "type:ISSUE_ADVANCED" in doc, doc
    assert re.search(r"type:ISSUE(?!_ADVANCED)", doc) is None, doc
    # Count parity: the count measures the exact population the list fetch
    # queries - same composed string, only the documented wrapper differs
    # (lowercase type:issue in the SEARCH string is that wrapper, required).
    assert q_value == f"( {search} ) repo:{REPO} type:issue", (q_value, search)

    # Shim count == fetched population -> exact total, structural gates green.
    tree = parse_tree(read_tree(repo))
    assert tree["summary"]["total"] == 3, tree["summary"]
    assert tree["summary"]["issues"] == 3, tree["summary"]
    assert "total=3 (exact)" in out.stdout, out.stdout
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


# --------------------------------------------------------------------------
# 11. Cheat-sheet: sort:created-asc is SELECTION semantics - the oldest rows
#     (fixture order = gh's sorted response) survive the cap and the tree
#     row order stays that response order, never re-sorted by number
# --------------------------------------------------------------------------

def test_sort_created_asc_selects_survivors_and_keeps_row_order(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    issues = [
        gh_issue(942, "oldest", labels=("priority:P1",), created="2024-01-01T00:00:00Z"),
        gh_issue(941, "second oldest", labels=("priority:P1",), created="2024-06-01T00:00:00Z"),
        gh_issue(944, "third", labels=("priority:P1",), created="2025-01-01T00:00:00Z"),
        gh_issue(943, "newest", labels=("priority:P1",), created="2026-01-01T00:00:00Z"),
    ]
    # cap=2 -> fetch slice keeps the first three of gh's created-asc
    # response; identical priority makes FetchIndex (fetch order) the
    # tie-break, so the two oldest survive and row order equals gh's order
    # (0942 first - a number sort would put 0941 there). sort: never
    # re-orders rows (section 7 decision 5).
    repo = make_repo(tmp_path, manifest(issueQuery="sort:created-asc", treeMaxIssues=2))
    out = sync(pwsh_exe, skill, repo, issues)
    assert out.returncode == 0, out.stdout + out.stderr

    tree = parse_tree(read_tree(repo))
    assert tree["filter"] is not None and tree["filter"].startswith(
        "sort:created-asc"
    ), tree["filter"]
    assert [r["id"] for r in tree["rows"]] == ["0942", "0941"], tree["rows"]
    assert tree["summary"]["issues"] == 2, tree["summary"]
    assert tree["summary"]["P1"] == 2, tree["summary"]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr


# --------------------------------------------------------------------------
# 12. Cheat-sheet backlog-rot: a temporal qualifier in issueQuery suppresses
#     the created: append AND the 2-year-old untouched issue still renders
# --------------------------------------------------------------------------

def test_temporal_query_keeps_ancient_issue_rendering(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    old = gh_issue(991, "Two year old untouched", created="2024-06-01T00:00:00Z")
    repo = make_repo(tmp_path, manifest(issueQuery="updated:<2026-01-01"))
    out = sync(pwsh_exe, skill, repo, [old])
    assert out.returncode == 0, out.stdout + out.stderr

    tree = parse_tree(read_tree(repo))
    # The query's own window wins: no created:>=(asOf-365d) may be ANDed on
    # top (it would exclude the very issue the user asked for) ...
    assert tree["filter"] is not None
    assert tree["filter"].startswith("updated:<2026-01-01"), tree["filter"]
    assert "created:>" not in tree["filter"], tree["filter"]
    assert "is:issue" in tree["filter"], tree["filter"]  # count-parity type class
    # ... and the sync applies no client-side window of its own: the ancient
    # row survives mapping, the cap and the render.
    assert [r["id"] for r in tree["rows"]] == ["0991"], tree["rows"]
    assert tree["summary"]["issues"] == 1, tree["summary"]

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    html = (repo / ".issues" / "tree.html").read_text(encoding="utf-8")
    assert "Two year old untouched" in row_titles(data_json(html))
