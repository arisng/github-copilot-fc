"""The tracker capability matrix must match what the scripts actually do.

references/tracker-matrix.md states which rules and behaviors are available for
each `tracker` value. That kind of document rots silently: someone widens a
guard clause and the table keeps claiming a refusal that no longer happens.
These tests turn the table's executable claims into assertions by probing every
script under all three trackers, the same way the matrix was built.

Scope is deliberately the *dispatch* behaviour (does the script run, refuse, or
no-op for this tracker). Rules that live inside the local store - template
conformance, theme relations - are covered where they are implemented:
test_issue_templates.py and test_theme_completion.py.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

TREE = (
    "SUMMARY|themes=1|issues=1|total=1\n"
    "\n"
    "## THEME|T-x|none|open|X\n"
    "\n"
    "- 0001|T-x|-|none|open|One\n"
)

MANIFESTS = {
    "local-markdown": {
        "schemaVersion": 1,
        "tracker": "local-markdown",
        "issuesDir": ".issues",
        "treeFile": ".issues/tree.md",
    },
    "github": {
        "schemaVersion": 1,
        "tracker": "github",
        "treeSource": "github",
        "repo": "acme/widgets",
        "treeFile": ".issues/tree.md",
    },
    "azure-devops": {
        "schemaVersion": 1,
        "tracker": "azure-devops",
        "org": "org",
        "project": "project",
    },
}


@pytest.fixture(scope="session")
def pwsh_exe() -> str:
    exe = shutil.which("pwsh")
    if not exe:
        pytest.skip("pwsh not on PATH (skill scripts are PowerShell)")
    return exe


@pytest.fixture(scope="session")
def skill(tmp_path_factory: pytest.TempPathFactory) -> Path:
    dst = tmp_path_factory.mktemp("skill") / "issue-tracking"
    shutil.copytree(SKILL_DIR, dst)
    return dst


def make_repo(tmp_path: Path, tracker: str) -> Path:
    repo = tmp_path / tracker
    (repo / ".github").mkdir(parents=True)
    (repo / ".issues").mkdir()
    (repo / ".github" / "issue-tracker.json").write_text(
        json.dumps(MANIFESTS[tracker]), encoding="utf-8"
    )
    (repo / ".issues" / "tree.md").write_text(TREE, encoding="utf-8")
    if tracker == "local-markdown":
        # A real store: local mode regenerates the tree from files, so without
        # a conforming issue the fixture tree would be replaced by an empty one.
        # A theme needs a child, hence both files.
        (repo / ".issues" / "0001-one.md").write_text(
            "---\n"
            'id: "0001"\n'
            'title: "One"\n'
            "status: open\n"
            "priority: P2\n"
            "type: theme\n"
            "created: 2026-01-01\n"
            "---\n"
            "\n"
            "## Summary\n"
            "\n"
            "Body.\n"
            "\n"
            "## Notes\n"
            "\n"
            "Notes.\n",
            encoding="utf-8",
        )
        (repo / ".issues" / "0002-two.md").write_text(
            "---\n"
            'id: "0002"\n'
            'title: "Two"\n'
            "status: open\n"
            "priority: P2\n"
            "type: task\n"
            "theme: 0001\n"
            "created: 2026-01-01\n"
            "---\n"
            "\n"
            "## Summary\n"
            "\n"
            "Body.\n"
            "\n"
            "## Notes\n"
            "\n"
            "Notes.\n",
            encoding="utf-8",
        )
    return repo


def probe(pwsh: str, skill: Path, repo: Path, script: str, *args: str):
    out = subprocess.run(
        [pwsh, "-NoProfile", "-File", str(skill / "scripts" / script), *args],
        cwd=str(repo),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )
    first = out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    return out.returncode, first


def test_table_document_exists() -> None:
    doc = (SKILL_DIR / "references" / "tracker-matrix.md").read_text(encoding="utf-8")
    # One row per tracker in the rules table, and the legend must explain the
    # marks actually used there.
    for mark in ("**yes**", "**derive**", "**n/a**", "**route**", "**refused**"):
        assert mark in doc, mark


@pytest.mark.parametrize("tracker", ["local-markdown"])
def test_local_markdown_runs_every_local_script(
    tmp_path: Path, pwsh_exe: str, skill: Path, tracker: str
) -> None:
    repo = make_repo(tmp_path, tracker)
    assert probe(pwsh_exe, skill, repo, "issue-tree.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")[0] == 0
    assert probe(pwsh_exe, skill, repo, "issue-tree.ps1", "-Inventory")[0] == 0
    assert probe(pwsh_exe, skill, repo, "render-issue-tree.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")[0] == 0
    assert probe(pwsh_exe, skill, repo, "issue-new-id.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "issue-template.ps1", "-Validate")[0] == 0


def test_local_markdown_refuses_the_remote_sync(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, "local-markdown")
    # Plain run hits the tracker guard; -Check short-circuits to the
    # offline-deferred pointer before the guard is evaluated. Both exit 1, but
    # the matrix table must not imply the guard message appears in -Check.
    code, first = probe(pwsh_exe, skill, repo, "sync-github-tree.ps1")
    assert code == 1
    assert "is not github" in first, first
    code_check, first_check = probe(pwsh_exe, skill, repo, "sync-github-tree.ps1", "-Check")
    assert code_check == 1
    assert "offline-deferred" in first_check, first_check


def test_github_plain_tree_run_is_a_noop_pointer(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # The matrix says "no-op pointer - never writes; run the sync". Exit 0 +
    # that exact advice is load-bearing: a gate wired to a plain run would
    # otherwise look green while checking nothing.
    repo = make_repo(tmp_path, "github")
    code, first = probe(pwsh_exe, skill, repo, "issue-tree.ps1")
    assert code == 0
    assert "run sync-github-tree.ps1 to regenerate" in first, first


def test_github_check_is_structural_and_render_works(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, "github")
    code, first = probe(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert code == 0, first
    assert "structurally consistent" in first, first
    assert probe(pwsh_exe, skill, repo, "issue-tree.ps1", "-Inventory")[0] == 0
    assert probe(pwsh_exe, skill, repo, "render-issue-tree.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")[0] == 0


def test_github_refuses_local_store_scripts(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, "github")
    for script, args in (
        ("issue-new-id.ps1", ()),
        ("issue-template.ps1", ("-Validate",)),
    ):
        code, first = probe(pwsh_exe, skill, repo, script, *args)
        assert code == 1, f"{script} should refuse github: {first}"
        assert "is not local-markdown" in first, first


def test_azure_devops_is_bootstrap_and_route_only(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # Every tree/store script refuses with the tracker named, and the manifest
    # writer is the one thing that supports azure-devops.
    repo = make_repo(tmp_path, "azure-devops")
    for script, args in (
        ("issue-tree.ps1", ()),
        ("issue-tree.ps1", ("-Check",)),
        ("issue-tree.ps1", ("-Inventory",)),
        ("render-issue-tree.ps1", ()),
        ("render-issue-tree.ps1", ("-Check",)),
        ("issue-new-id.ps1", ()),
        ("issue-template.ps1", ("-Validate",)),
    ):
        code, first = probe(pwsh_exe, skill, repo, script, *args)
        assert code == 1, f"{script} {' '.join(args)} should refuse azure-devops: {first}"
        assert "azure-devops" in first, first
    # The sync refuses too, but only on a real run: -Check is a static pointer
    # that never reads the manifest, so it reports offline-deferred instead.
    code, first = probe(pwsh_exe, skill, repo, "sync-github-tree.ps1")
    assert code == 1
    assert "is not github" in first, first


def test_manifest_writer_is_the_only_azure_capable_entry_point(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = tmp_path / "bootstrap"
    repo.mkdir()
    out = subprocess.run(
        [
            pwsh_exe, "-NoProfile", "-File",
            str(skill / "scripts" / "issue-tracker-init.ps1"),
            "-Apply", "-Tracker", "azure-devops", "-Org", "o", "-Project", "p",
        ],
        cwd=str(repo),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )
    assert out.returncode == 0, out.stdout + out.stderr
    written = json.loads((repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert written["tracker"] == "azure-devops"
    # Store-only and github-only keys must not leak into an azure manifest.
    for key in ("issuesDir", "issueTemplatesDir", "treeFile", "treeMaxIssues", "treeSource"):
        assert key not in written, key
