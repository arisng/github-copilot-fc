"""Theme closure: a theme's status must agree with its completion.

Regression guard for a consuming repo that shipped a theme rendered at 100%
while still carrying `status: open`. `assets/tree-template.html` computes
completion as `done / (children - dropped)` (vacuously 100% when nothing is
countable), and every gate passed in that state because `issue-tree.ps1` only
checked that a theme had *at least one* child.

The rule is **enforced, not derived**: theme `status` stays the authored value
and the gate refuses a state that contradicts it, in both directions
(100% but not closed / closed but not 100%). Derivation was rejected - it would
rewrite every consumer's committed tree.md and silently revert a deliberate
manual status.

Each test builds a scratch local-markdown store with conforming files (the
template gate from step 1 is active), runs the gate, and asserts on stdout.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

MANIFEST = {
    "schemaVersion": 1,
    "tracker": "local-markdown",
    "issuesDir": ".issues",
    "treeFile": ".issues/tree.md",
}


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


def issue_doc(
    number: str,
    *,
    type: str = "task",
    status: str = "open",
    theme: str | None = None,
    parent: str | None = None,
) -> str:
    front = [
        "---",
        f'id: "{number}"',
        f'title: "Issue {number}"',
        f"status: {status}",
        "priority: P2",
        f"type: {type}",
        "created: 2026-01-01",
    ]
    if theme is not None:
        front.append(f"theme: {theme}")
    if parent is not None:
        front.append(f"parent: {parent}")
    front += ["---", "", "## Summary", "", "Body.", "", "## Notes", "", "Notes.", ""]
    return "\n".join(front)


def make_store(tmp_path: Path, theme_status: str, children: list[tuple[str, str]]) -> Path:
    """A local-markdown repo: theme 0001 + (status, child-status) pairs."""
    repo = tmp_path / "repo"
    store = repo / ".issues"
    store.mkdir(parents=True)
    (repo / ".github").mkdir()
    (repo / ".github" / "issue-tracker.json").write_text(json.dumps(MANIFEST), encoding="utf-8")
    (store / "0001-sample-theme.md").write_text(
        issue_doc("0001", type="theme", status=theme_status), encoding="utf-8"
    )
    for offset, (prefix, status) in enumerate(children):
        number = f"{2 + offset:04d}"
        (store / f"{number}-{prefix}.md").write_text(
            issue_doc(number, status=status, theme="0001"), encoding="utf-8"
        )
    return repo


@pytest.fixture
def env(tmp_path: Path, pwsh_exe: str) -> SimpleNamespace:
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)

    def run(repo: Path, *args: str) -> subprocess.CompletedProcess:
        return run_script(pwsh_exe, skill / "scripts" / "issue-tree.ps1", args, repo)

    return SimpleNamespace(build=make_store, run=run)


@pytest.mark.parametrize(
    ("theme_status", "children", "needle"),
    [
        (
            "open",
            [("a", "done"), ("b", "done")],
            "theme is 100% complete (2 of 2 child issues done) but status is 'open' - set 'status: done'",
        ),
        (
            "in-progress",
            [("a", "done"), ("b", "done")],
            "theme is 100% complete (2 of 2 child issues done) but status is 'in-progress'",
        ),
        (
            "open",
            [("a", "dropped"), ("b", "dropped")],
            "theme is 100% complete (every child is dropped) but status is 'open'",
        ),
        (
            "done",
            [("a", "done"), ("b", "open")],
            "theme is marked done but only 50% complete (1 of 2 child issues not done: 1 open)",
        ),
        (
            "done",
            [("a", "in-progress"), ("b", "blocked"), ("c", "done")],
            "theme is marked done but only 33% complete (2 of 3 child issues not done: "
            "1 blocked, 1 in-progress)",
        ),
    ],
    ids=["open-at-100", "in-progress-at-100", "all-dropped", "done-at-50", "done-at-33"],
)
def test_theme_status_must_match_completion(
    env: SimpleNamespace, tmp_path: Path, theme_status: str, children: list, needle: str
) -> None:
    repo = env.build(tmp_path, theme_status, children)
    for args in ((), ("-Check",)):
        out = env.run(repo, *args)
        assert out.returncode == 1, out.stdout + out.stderr
        assert f"THEME   .issues/0001-sample-theme.md: {needle}" in out.stdout, out.stdout
    assert not (repo / ".issues" / "tree.md").exists(), "a refused store must not write"


@pytest.mark.parametrize(
    ("theme_status", "children"),
    [
        # 4 of 5 done: not complete, theme correctly open.
        ("open", [("a", "done"), ("b", "done"), ("c", "done"), ("d", "done"), ("e", "open")]),
        # The observed fixed state: everything finished and the theme closed.
        ("done", [("a", "done"), ("b", "done")]),
        # dropped is excluded from the denominator, so this is 100%.
        ("done", [("a", "done"), ("b", "done"), ("c", "dropped")]),
        # Partial progress with a dropped sibling: 2 of 3 countable done.
        ("open", [("a", "done"), ("b", "done"), ("c", "open"), ("d", "dropped")]),
        # A dropped theme may legitimately stay at 100%.
        ("dropped", [("a", "done"), ("b", "dropped")]),
    ],
    ids=["open-at-80", "done-at-100", "done-with-dropped", "open-at-66-with-dropped", "dropped-at-100"],
)
def test_consistent_themes_pass(
    env: SimpleNamespace, tmp_path: Path, theme_status: str, children: list
) -> None:
    repo = env.build(tmp_path, theme_status, children)
    gen = env.run(repo)
    assert gen.returncode == 0, gen.stdout + gen.stderr
    chk = env.run(repo, "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
