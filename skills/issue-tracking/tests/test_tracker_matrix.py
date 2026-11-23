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
    for mark in (
        "**yes**",
        "**partial**",
        "**derive**",
        "**n/a**",
        "**route**",
        "**refused**",
        "**ignored**",
    ):
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

# --------------------------------------------------------------------------
# Corrected claims: each of these guards a statement the matrix makes that a
# plausible implementation would get wrong (and that an audit caught).
# --------------------------------------------------------------------------


def test_github_without_tree_source_is_refused_like_azure(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # The matrix's github column is `github (+ treeSource: github)`; a github
    # manifest WITHOUT treeSource behaves like azure-devops, not like github.
    repo = tmp_path / "github-no-tree"
    (repo / ".github").mkdir(parents=True)
    (repo / ".issues").mkdir()
    (repo / ".issues" / "tree.md").write_text(TREE, encoding="utf-8")
    (repo / ".github" / "issue-tracker.json").write_text(
        json.dumps({"schemaVersion": 1, "tracker": "github", "repo": "acme/widgets"}),
        encoding="utf-8",
    )
    for script, args in (
        ("issue-tree.ps1", ()),
        ("issue-tree.ps1", ("-Check",)),
        ("render-issue-tree.ps1", ()),
        ("render-issue-tree.ps1", ("-Check",)),
    ):
        code, first = probe(pwsh_exe, skill, repo, script, *args)
        assert code == 1, f"{script} {' '.join(args)}: {first}"
        # The message must name both supported modes, not claim local-only:
        # both scripts DO handle github when treeSource is set.
        assert "is not supported by this script" in first, first


def test_check_and_inventory_are_mutually_exclusive_in_both_modes(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # A gate invoking both checks nothing; the matrix states this explicitly.
    for tracker in ("local-markdown", "github"):
        repo = make_repo(tmp_path, tracker)
        code, first = probe(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check", "-Inventory")
        assert code == 1, f"{tracker}: {first}"
        assert "not both" in first, first


def test_epic_containment_is_convention_not_a_gate(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # The matrix marks epic containment `partial` because the gate checks only
    # the theme root. This pins that: an epic parented by a task passes.
    repo = make_repo(tmp_path, "local-markdown")
    (repo / ".issues" / "0003-task.md").write_text(
        "---\nid: \"0003\"\ntitle: \"Task\"\nstatus: open\npriority: P2\n"
        "type: task\ntheme: 0001\ncreated: 2026-01-01\n---\n\n## Summary\n\nB.\n\n## Notes\n\nN.\n",
        encoding="utf-8",
    )
    (repo / ".issues" / "0004-epic.md").write_text(
        "---\nid: \"0004\"\ntitle: \"Epic\"\nstatus: open\npriority: P2\n"
        "type: epic\ntheme: 0001\nparent: 0003\ncreated: 2026-01-01\n---\n\n"
        "## Summary\n\nB.\n\n## Notes\n\nN.\n",
        encoding="utf-8",
    )
    code, first = probe(pwsh_exe, skill, repo, "issue-tree.ps1")
    assert code == 0, first


def test_missing_manifest_falls_back_for_tree_but_not_for_id_or_sync(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # A never-bootstrapped repo gets green tree gates; only the allocator and
    # the sync refuse. The matrix states this explicitly.
    repo = tmp_path / "no-manifest"
    (repo / ".issues").mkdir(parents=True)
    (repo / ".issues" / "0001-one.md").write_text(
        "---\nid: \"0001\"\ntitle: \"One\"\nstatus: open\npriority: P2\n"
        "type: theme\ncreated: 2026-01-01\n---\n\n## Summary\n\nB.\n\n## Notes\n\nN.\n",
        encoding="utf-8",
    )
    (repo / ".issues" / "0002-two.md").write_text(
        "---\nid: \"0002\"\ntitle: \"Two\"\nstatus: open\npriority: P2\n"
        "type: task\ntheme: 0001\ncreated: 2026-01-01\n---\n\n## Summary\n\nB.\n\n## Notes\n\nN.\n",
        encoding="utf-8",
    )
    assert probe(pwsh_exe, skill, repo, "issue-tree.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "render-issue-tree.ps1")[0] == 0
    assert probe(pwsh_exe, skill, repo, "issue-template.ps1", "-Validate")[0] == 0
    code, first = probe(pwsh_exe, skill, repo, "issue-new-id.ps1")
    assert code == 1
    assert "bootstrap the manifest first" in first, first
    assert probe(pwsh_exe, skill, repo, "sync-github-tree.ps1")[0] == 1


def test_tree_min_priority_is_validated_only_at_sync(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # -Apply accepts any string; the sync is the guard. The matrix calls this
    # out because a bootstrap can commit an unusable manifest.
    repo = tmp_path / "minpri"
    repo.mkdir()
    out = subprocess.run(
        [
            pwsh_exe, "-NoProfile", "-File",
            str(skill / "scripts" / "issue-tracker-init.ps1"),
            "-Apply", "-Tracker", "github", "-Repo", "acme/widgets",
            "-TreeMinPriority", "P9",
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
    assert written["treeMinPriority"] == "P9"


def test_template_show_is_refused_for_non_local_trackers(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    for tracker in ("github", "azure-devops"):
        repo = make_repo(tmp_path, tracker)
        code, first = probe(pwsh_exe, skill, repo, "issue-template.ps1", "-Show", "task")
        assert code == 1, f"{tracker}: {first}"
        assert "is not local-markdown" in first, first


def test_github_plain_tree_run_never_writes_the_tree(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # The no-op pointer must not rewrite the committed snapshot: a gate wired to
    # a plain run would otherwise look like it regenerated.
    repo = make_repo(tmp_path, "github")
    tree = repo / ".issues" / "tree.md"
    before = tree.read_bytes()
    code, _ = probe(pwsh_exe, skill, repo, "issue-tree.ps1")
    assert code == 0
    assert tree.read_bytes() == before, "github plain run must not touch tree.md"


def test_github_mode_renders_the_full_html_view(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # github mode is NOT html-less: the same renderer produces the same page
    # from the synced snapshot. A user reading the refusal wording must not
    # conclude otherwise. Verified end to end: render + render -Check both pass.
    repo = make_repo(tmp_path, "github")
    html = repo / ".issues" / "tree.html"
    assert not html.exists()
    code, first = probe(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert code == 0, first
    assert html.exists() and html.stat().st_size > 5000, "github mode must write a real page"
    # Same template machinery as local mode: the version marker is embedded.
    text = html.read_text(encoding="utf-8")
    assert "tree-template-version" in text
    assert "sync-github-tree.ps1" in text, "github footer hint distinguishes the pipeline"
    code, first = probe(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")
    assert code == 0, first
    assert "fresh" in first, first
