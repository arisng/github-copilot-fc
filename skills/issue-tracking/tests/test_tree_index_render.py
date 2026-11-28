"""Render-time index filter: a tree row must never dangle.

issue-tree.ps1 renders from the git INDEX (tracked or staged files), not the
working directory, so a committed tree.md cannot reference an issue file the
commit does not carry. A 2026-11-28 commit in rea-web-api shipped rows for
seven untracked issues exactly that way: the pre-commit gate regenerated from
the working dir and staged the result.

Covered here:
  * untracked issue files are held out of the rendered tree (with a notice)
  * staging them brings their rows back
  * validation and -Inventory still see untracked files (NEXT_ID must reserve
    ids that exist only on disk, or the next filing collides)
  * outside a git repo (and in a store with zero index entries) the renderer
    falls back to the historical include-everything behaviour, so plain
    directory fixtures and brand-new stores keep working
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]
LOCAL_MANIFEST = {
    "tracker": "local-markdown",
    "treeSource": "local-markdown",
    "issuesDir": ".issues",
    "treeFile": ".issues/tree.md",
    "archiveDir": ".issues/archived",
}


@pytest.fixture
def pwsh_exe() -> str:
    exe = shutil.which("pwsh")
    if not exe:
        pytest.skip("pwsh not on PATH (skill scripts are PowerShell)")
    return exe


def issue_file(*, id: str, title: str, theme: str | None = None, labels: str | None = None) -> str:
    lines = [
        "---",
        f'id: "{id}"',
        f'title: "{title}"',
        "status: open",
        "priority: P2",
        "type: task",
    ]
    if labels is not None:
        lines.append(f"labels: [{labels}]")
    if theme is not None:
        lines.append(f"theme: {theme}")
    lines += ["created: 2026-01-01", "---", "", "## Summary", "", "B.", "", "## Notes", "", "N.", ""]
    return "\n".join(lines)


@pytest.fixture
def env(tmp_path: Path, pwsh_exe: str) -> SimpleNamespace:
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)
    repo = tmp_path / "repo"
    (repo / ".issues").mkdir(parents=True)
    (repo / ".github").mkdir()
    (repo / ".github" / "issue-tracker.json").write_text(json.dumps(LOCAL_MANIFEST), encoding="utf-8")

    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", str(repo), "-c", "user.email=gate@test", "-c", "user.name=gate", *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def run(script: str, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [pwsh_exe, "-NoProfile", "-File", str(skill / "scripts" / script), *args],
            cwd=str(repo),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=180,
        )

    def write(name: str, text: str) -> None:
        (repo / ".issues" / name).write_text(text, encoding="utf-8")

    ns = SimpleNamespace(repo=repo, skill=skill, run=run, write=write, git=git)
    return ns


def test_untracked_issue_is_held_out_of_tree_but_kept_in_inventory(env: SimpleNamespace) -> None:
    assert env.git("init").returncode == 0
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    env.write("0002-tracked.md", issue_file(id="0002", title="Tracked child", theme="0001"))
    env.write("0003-untracked.md", issue_file(id="0003", title="Untracked child", theme="0001"))
    assert env.git("add", ".issues/0001-root.md", ".issues/0002-tracked.md").returncode == 0

    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "- 0002|" in tree, tree
    assert "0003" not in tree, tree
    assert "SUMMARY|themes=1|issues=1" in tree, tree
    # The hold-back is surfaced, never silent.
    assert "untracked issue file(s) kept out of the tree" in gen.stdout, gen.stdout
    assert "0003-untracked.md" in gen.stdout, gen.stdout

    # Freshness gate agrees with the filtered render.
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr

    # NEXT_ID still reserves the untracked file's id: dropping it from the
    # inventory would hand id 0003 to the next filing and double-file it.
    inv = env.run("issue-tree.ps1", "-Inventory")
    assert inv.returncode == 0, inv.stdout + inv.stderr
    assert "0003|task|open" in inv.stdout, inv.stdout
    assert "NEXT_ID|0004" in inv.stdout, inv.stdout


def test_staging_the_file_brings_its_row_back(env: SimpleNamespace) -> None:
    assert env.git("init").returncode == 0
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    env.write("0002-child.md", issue_file(id="0002", title="Child", theme="0001"))
    assert env.git("add", ".issues/0001-root.md").returncode == 0
    gen1 = env.run("issue-tree.ps1")
    assert gen1.returncode == 0, gen1.stdout + gen1.stderr
    assert "0002" not in (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")

    assert env.git("add", ".issues/0002-child.md").returncode == 0
    gen2 = env.run("issue-tree.ps1")
    assert gen2.returncode == 0, gen2.stdout + gen2.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "- 0002|" in tree, tree
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


def test_validation_still_fails_on_an_untracked_broken_file(env: SimpleNamespace) -> None:
    # The filter is render-only: a bad file on disk keeps failing validation
    # exactly as before, so the gate cannot be dodged by not staging.
    assert env.git("init").returncode == 0
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    assert env.git("add", ".issues/0001-root.md").returncode == 0
    env.write("0002-bad.md", issue_file(id="0002", title="Bad", theme="0001").replace("status: open", "status: wat"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "invalid status 'wat'" in out.stdout, out.stdout


def test_child_without_a_staged_theme_is_held_back(env: SimpleNamespace) -> None:
    # A staged child whose theme root is untracked cannot be placed under a
    # header that will not exist: SUMMARY must not count an absent row.
    assert env.git("init").returncode == 0
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    env.write("0002-child.md", issue_file(id="0002", title="Child", theme="0001"))
    assert env.git("add", ".issues/0002-child.md").returncode == 0
    out = env.run("issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "0001" not in tree or "## THEME|0001" not in tree, tree
    assert "0002" not in tree, tree
    assert "held back until their theme root is staged" in out.stdout, out.stdout


def test_store_without_any_index_entry_renders_from_disk(env: SimpleNamespace) -> None:
    # Brand-new store: nothing under .issues is tracked yet (not even tree.md).
    # Filtering would render an empty tree on the skill's first run, so the
    # renderer falls back to include-everything.
    assert env.git("init").returncode == 0
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    env.write("0002-child.md", issue_file(id="0002", title="Child", theme="0001"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "- 0002|" in tree, tree
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


def test_no_git_repo_renders_from_disk(env: SimpleNamespace) -> None:
    # Plain directory fixture, no .git at all - the historical behaviour.
    env.write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
    env.write("0002-child.md", issue_file(id="0002", title="Child", theme="0001"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "- 0002|" in tree, tree
