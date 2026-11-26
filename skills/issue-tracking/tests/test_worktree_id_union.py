"""Worktree-aware id allocation, collision warnings, and the -Brief inventory.

An id filed (even committed) on an unmerged worktree branch exists only in that
worktree's `.issues` checkout: the local store scan cannot see it, and its lease
may already be released or expired - which is how ids 0007/0012/0014/0034/0035
got filed twice historically (`.issues/README.md`, WebApi). These tests pin:

- the allocator counting ids filed only in a sibling worktree checkout
  (red against the old local-only `max()` scan);
- the WARNING when one id is filed under two different filenames across
  worktrees (two racing files - renumber the later one);
- `-Inventory`'s `NEXT_ID` agreeing with that union;
- `-Inventory -Brief` printing `SUMMARY` + `NEXT_ID` only, and `-Brief`
  without `-Inventory` being refused instead of regenerating the tree.
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


def issue_file(*, id: str, title: str, type_: str = "task", theme: str | None = None,
               labels: str | None = None) -> str:
    lines = ["---", f'id: "{id}"', f'title: "{title}"', "status: open",
             "priority: P2", f"type: {type_}"]
    if labels is not None:
        lines.append(f"labels: [{labels}]")
    if theme is not None:
        lines.append(f"theme: {theme}")
    lines += ["created: 2026-01-01", "---", "", "## Summary", "", "B.", "",
              "## Notes", "", "N.", ""]
    return "\n".join(lines)


@pytest.fixture
def env(tmp_path: Path, pwsh_exe: str) -> SimpleNamespace:
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)
    repo = tmp_path / "repo"
    (repo / ".issues").mkdir(parents=True)
    (repo / ".github").mkdir()
    (repo / ".github" / "issue-tracker.json").write_text(
        json.dumps(LOCAL_MANIFEST), encoding="utf-8"
    )

    def write(name: str, text: str) -> None:
        (repo / ".issues" / name).write_text(text, encoding="utf-8")

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

    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", str(repo), "-c", "user.email=retro@example.test",
             "-c", "user.name=retro", *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=180,
        )

    def git_commit_all() -> None:
        assert git("init").returncode == 0
        assert git("add", "-A").returncode == 0
        assert git("commit", "-m", "seed").returncode == 0

    def worktree_add(name: str) -> Path:
        wt = tmp_path / name
        assert git("worktree", "add", str(wt), "-b", f"feature/{name}").returncode == 0
        return wt

    def seed_two_issue_store() -> None:
        write("0001-root.md", issue_file(id="0001", title="Root", labels="theme"))
        write("0002-a.md", issue_file(id="0002", title="A", theme="0001"))

    ns = SimpleNamespace(
        repo=repo, skill=skill, tmp=tmp_path, write=write, run=run, git=git,
        git_commit_all=git_commit_all, worktree_add=worktree_add,
        seed=seed_two_issue_store,
    )
    return ns


def test_allocator_counts_ids_filed_only_in_a_sibling_worktree(env: SimpleNamespace) -> None:
    # Red against the old local-only scan: without the worktree union this
    # allocates ID|0003 while id 0005 is already filed in the sibling checkout.
    env.seed()
    env.git_commit_all()
    wt = env.worktree_add("wt-filed-0005")
    (wt / ".issues").mkdir(exist_ok=True)
    (wt / ".issues" / "0005-worktree-only.md").write_text(
        issue_file(id="0005", title="Worktree only"), encoding="utf-8"
    )
    out = env.run("issue-new-id.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "ID|0006" in out.stdout, out.stdout


def test_allocator_warns_when_one_id_is_filed_under_two_names(env: SimpleNamespace) -> None:
    # Two racing files with the same id in different checkouts: the allocator
    # still hands out the next free id, but the collision is surfaced loudly
    # (the repo's duplicate-id lint refuses it at merge time).
    env.seed()
    env.write("0003-shared.md", issue_file(id="0003", title="Shared"))
    env.git_commit_all()
    wt = env.worktree_add("wt-racing-0003")
    (wt / ".issues").mkdir(exist_ok=True)
    (wt / ".issues" / "0003-other.md").write_text(
        issue_file(id="0003", title="Other"), encoding="utf-8"
    )
    out = env.run("issue-new-id.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "WARNING" in out.stdout and "id 0003" in out.stdout, out.stdout
    assert "ID|0004" in out.stdout, out.stdout


def test_inventory_next_id_agrees_with_the_sibling_worktree(env: SimpleNamespace) -> None:
    # NEXT_ID is documented as the advisory view of the allocator - it must
    # union worktree checkouts too, or it advises an id that is already taken.
    env.seed()
    env.git_commit_all()
    wt = env.worktree_add("wt-inventory-0007")
    (wt / ".issues").mkdir(exist_ok=True)
    (wt / ".issues" / "0007-worktree-only.md").write_text(
        issue_file(id="0007", title="Worktree only"), encoding="utf-8"
    )
    out = env.run("issue-tree.ps1", "-Inventory", "-Brief")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "NEXT_ID|0008" in out.stdout, out.stdout


def test_brief_inventory_prints_summary_and_next_id_only(env: SimpleNamespace) -> None:
    env.seed()
    out = env.run("issue-tree.ps1", "-Inventory", "-Brief")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "SUMMARY|themes=1|issues=1" in out.stdout, out.stdout
    assert "NEXT_ID|0003" in out.stdout, out.stdout
    assert "id|type|status|priority" not in out.stdout, out.stdout


def test_brief_without_inventory_is_refused(env: SimpleNamespace) -> None:
    # Bare -Brief must not fall through to the default tree-regeneration mode.
    env.seed()
    out = env.run("issue-tree.ps1", "-Brief")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "-Brief applies to -Inventory only" in out.stdout, out.stdout
    assert not (env.repo / ".issues" / "tree.md").exists(), "tree must not be generated"
