"""Github guard + renderer hardening tests (sketch v6 F1 wave).

Covers the compound manifest guard (issue-tree.ps1 and render-issue-tree.ps1
run for local-markdown OR github+treeSource:github; azure-devops and old
github manifests without treeSource stay refused; issue-new-id.ps1 stays
local-only), github-mode issue-tree semantics (plain run is a no-op pointer,
-Inventory/-Check parse the committed treeFile with no store dir required),
and the renderer hardening: SUMMARY key validation, embedded-JSON parse
assert, duplicate row ids, parent references, total/asOfEpoch validation,
and the dataJson {source, summary, next, filter, themes} contract.

Origin: F1 implementation wave (2026-11-21), per
github-tree-adaptation-sketch.md sections 1.2 / 1.3 / 2 / 3. Pattern reused
from test_tree_template_versioning.py: copy the skill into tmp_path, shell
out to pwsh -File from a throwaway repo.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

# Github-shaped manifest: treeFile is the source of truth and issuesDir
# points at a directory that never exists - any run requiring the local
# store fails, proving github mode does not need it.
GITHUB_MANIFEST = {
    "schemaVersion": 1,
    "tracker": "github",
    "treeSource": "github",
    "repo": "owner/name",
    "treeFile": ".issues/tree.md",
    "issuesDir": ".issues-store-absent",
}

# Committed github tree: total/asOfEpoch keys, one nested row, one NEXT.
GITHUB_TREE = """SUMMARY|themes=1|issues=3|total=5|asOfEpoch=1763630400|P0=0|P1=2|P2=1|P3=0|blocked=0
NEXT|0002|T-alpha|P1|open|Second github issue

## THEME|T-alpha|P1|open|Alpha theme

- 0001|T-alpha|-|P1|open|First github issue
   - 0002|T-alpha|0001|P1|open|Second github issue
- 0003|T-alpha|-|P2|open|Third github issue
"""

THEME_FILE = """---
id: "0001"
title: "Sample theme"
status: open
priority: P1
type: theme
created: 2026-01-01
---
"""

ISSUE_FILE = """---
id: "0002"
title: "Sample issue"
status: open
priority: P2
type: task
theme: 0001
created: 2026-01-02
---
"""


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


def make_repo(tmp_path: Path, manifest: dict | None, tree: str | None = None) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir(parents=True)
    if manifest is not None:
        (repo / ".github").mkdir()
        (repo / ".github" / "issue-tracker.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
    if tree is not None:
        (repo / ".issues").mkdir()
        (repo / ".issues" / "tree.md").write_text(tree, encoding="utf-8")
    return repo


def run(pwsh: str, skill: Path, repo: Path, script: str, *args: str) -> subprocess.CompletedProcess:
    return run_script(pwsh, skill / "scripts" / script, args, repo)


def make_local_repo(tmp_path: Path) -> Path:
    repo = make_repo(
        tmp_path,
        {"schemaVersion": 1, "tracker": "local-markdown", "issuesDir": ".issues"},
    )
    store = repo / ".issues"
    store.mkdir()
    (store / "0001-sample-theme.md").write_text(THEME_FILE, encoding="utf-8")
    (store / "0002-sample-issue.md").write_text(ISSUE_FILE, encoding="utf-8")
    return repo


def test_guard_trio_refuses_github_manifest_without_tree_source(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # Old github manifests carry no treeSource -> behave as local-markdown
    # and fail closed, with the A1-quoted refusal wording (all three scripts).
    repo = make_repo(tmp_path, {"schemaVersion": 1, "tracker": "github", "repo": "owner/name"})
    checks = (
        ("issue-tree.ps1", (), "issue-tree: tracker 'github' is not local-markdown"),
        ("render-issue-tree.ps1", (), "render-tree: tracker 'github' is not local-markdown"),
        ("issue-new-id.ps1", (), "issue-id: tracker 'github' is not local-markdown"),
    )
    for script, args, needle in checks:
        out = run(pwsh_exe, skill, repo, script, *args)
        assert out.returncode == 1, f"{script}: {out.stdout}{out.stderr}"
        assert needle in out.stdout, out.stdout


def test_guard_refuses_azure_devops(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    # azure-devops is refused by the explicit tracker clause, treeSource or
    # not - the github hint must not appear.
    for label, manifest in (
        ("plain", {"schemaVersion": 1, "tracker": "azure-devops", "org": "o", "project": "p"}),
        ("github-source", {"schemaVersion": 1, "tracker": "azure-devops", "treeSource": "github"}),
    ):
        repo = make_repo(tmp_path / label, manifest)
        for script, needle in (
            ("issue-tree.ps1", "issue-tree: tracker 'azure-devops' is not local-markdown"),
            ("render-issue-tree.ps1", "render-tree: tracker 'azure-devops' is not local-markdown"),
        ):
            out = run(pwsh_exe, skill, repo, script)
            assert out.returncode == 1, f"{script}: {out.stdout}{out.stderr}"
            assert needle in out.stdout, out.stdout
            assert "treeSource" not in out.stdout, out.stdout


def test_github_plain_run_is_noop_and_never_regenerates(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=GITHUB_TREE)
    tree_file = repo / ".issues" / "tree.md"
    before = tree_file.read_bytes()
    out = run(pwsh_exe, skill, repo, "issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "github tree source: run sync-github-tree.ps1 to regenerate" in out.stdout
    assert tree_file.read_bytes() == before, "plain run must never rewrite treeFile"
    assert not (repo / ".issues-store-absent").exists(), "no store dir may be touched"


def test_github_inventory_and_check_need_no_store_dir(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=GITHUB_TREE)
    inv = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Inventory")
    assert inv.returncode == 0, inv.stdout + inv.stderr
    assert "0001|T-alpha|-|P1|open|First github issue" in inv.stdout
    assert "0002|T-alpha|0001|P1|open|Second github issue" in inv.stdout

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    assert "structurally consistent" in chk.stdout

    # The renderer accepts the github tree through the compound guard too.
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    assert not (repo / ".issues-store-absent").exists()


def test_local_happy_path_still_green(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    repo = make_local_repo(tmp_path)
    gen = run(pwsh_exe, skill, repo, "issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    assert "wrote .issues/tree.md" in gen.stdout

    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    assert "wrote .issues/tree.html" in rnd.stdout

    chk1 = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk1.returncode == 0, chk1.stdout + chk1.stderr
    assert "tree.md fresh" in chk1.stdout

    chk2 = run(pwsh_exe, skill, repo, "render-issue-tree.ps1", "-Check")
    assert chk2.returncode == 0, chk2.stdout + chk2.stderr
    assert "fresh" in chk2.stdout


def test_summary_bad_key_rejected_before_hydrating(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # Audit C2/E2: this key interpolates into raw JSON and used to render and
    # -Check green with an unparseable payload.
    bad = (
        'SUMMARY|themes=1|issues=1|x"},"evil":{"y=1\n'
        "\n"
        "## THEME|T-alpha|P1|open|Alpha theme\n"
        "\n"
        "- 0001|T-alpha|-|P1|open|First github issue\n"
    )
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=bad)
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 1, rnd.stdout + rnd.stderr
    assert "SUMMARY key" in rnd.stdout
    assert not (repo / ".issues" / "tree.html").exists(), "must fail before hydrating"

    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 1, chk.stdout + chk.stderr
    assert "SUMMARY key" in chk.stdout


def test_embedded_data_json_parses_and_carries_filter(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    repo = make_local_repo(tmp_path)
    assert run(pwsh_exe, skill, repo, "issue-tree.ps1").returncode == 0
    assert run(pwsh_exe, skill, repo, "render-issue-tree.ps1").returncode == 0
    html = (repo / ".issues" / "tree.html").read_text(encoding="utf-8")
    m = re.search(
        r'<script id="issue-tree-data" type="application/json">(.*?)</script>', html, re.S
    )
    assert m, "embedded data script tag missing"
    # The render-time ConvertFrom-Json assert proves the payload parses; this
    # re-parses it independently and pins the dataJson contract.
    data = json.loads(m.group(1))
    assert set(data) == {"source", "summary", "next", "filter", "themes"}
    assert data["filter"] == ""
    assert '"filter":""' in html
    assert all(isinstance(v, int) for v in data["summary"].values()), "SUMMARY stays digits-only"


def test_duplicate_row_id_rejected(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    dup = (
        "SUMMARY|themes=1|issues=3|P0=0|P1=3|P2=0|P3=0|blocked=0\n"
        "\n"
        "## THEME|T-alpha|P1|open|Alpha theme\n"
        "\n"
        "- 0001|T-alpha|-|P1|open|First github issue\n"
        "   - 0002|T-alpha|0001|P1|open|Second github issue\n"
        "- 0002|T-alpha|-|P1|open|Duplicate id row\n"
    )
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=dup)
    for script, args in (("render-issue-tree.ps1", ()), ("issue-tree.ps1", ("-Check",))):
        out = run(pwsh_exe, skill, repo, script, *args)
        assert out.returncode == 1, f"{script}: {out.stdout}{out.stderr}"
        assert "duplicate row id '0002'" in out.stdout, out.stdout


def test_nested_row_parent_reference_rejected(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    # Non-root = nested row naming a parent; 9999 never appears earlier in
    # the section (audit F.3's dead "no visible parent" branch).
    orphan = (
        "SUMMARY|themes=1|issues=3|P0=0|P1=3|P2=0|P3=0|blocked=0\n"
        "\n"
        "## THEME|T-alpha|P1|open|Alpha theme\n"
        "\n"
        "- 0001|T-alpha|-|P1|open|First github issue\n"
        "   - 0002|T-alpha|9999|P1|open|Orphan nested row\n"
        "- 0003|T-alpha|-|P2|open|Third github issue\n"
    )
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=orphan)
    for script, args in (("render-issue-tree.ps1", ()), ("issue-tree.ps1", ("-Check",))):
        out = run(pwsh_exe, skill, repo, script, *args)
        assert out.returncode == 1, f"{script}: {out.stdout}{out.stderr}"
        assert "parent '9999' does not exist earlier in section 'T-alpha'" in out.stdout, out.stdout


def test_promoted_root_keeps_foreign_parent_green(
    tmp_path: Path, pwsh_exe: str, skill: Path
) -> None:
    # Promoted rows are roots (depth 0) whose parent hint may point outside
    # the section or at a capped-out row - that must stay green (sketch 1.5
    # step 5b / critique C2's promoted child).
    promoted = (
        "SUMMARY|themes=1|issues=2|P0=0|P1=2|P2=0|P3=0|blocked=0\n"
        "\n"
        "## THEME|T-beta|P1|open|Beta theme\n"
        "\n"
        "- 0001|T-beta|-|P1|open|Promoted root row\n"
        "- 0002|T-beta|0099|P2|open|Kept parent hint outside the tree\n"
    )
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=promoted)
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 0, rnd.stdout + rnd.stderr
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr
    assert "structurally consistent" in chk.stdout


def test_summary_total_and_asofepoch_validation(tmp_path: Path, pwsh_exe: str, skill: Path) -> None:
    # total is a floor: below the shown rows it fails both gates.
    short = GITHUB_TREE.replace("total=5", "total=2")
    repo = make_repo(tmp_path, GITHUB_MANIFEST, tree=short)
    rnd = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd.returncode == 1, rnd.stdout + rnd.stderr
    assert "SUMMARY total=2 is below issues=3" in rnd.stdout
    chk = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk.returncode == 1, chk.stdout + chk.stderr
    assert "SUMMARY total=2 is below issues=3" in chk.stdout

    # Epoch-sized values (13 digits) parse as 64-bit - the old int cast
    # crashed the render with an overflow.
    big = GITHUB_TREE.replace("asOfEpoch=1763630400", "asOfEpoch=1763630400123")
    (repo / ".issues" / "tree.md").write_text(big, encoding="utf-8")
    rnd2 = run(pwsh_exe, skill, repo, "render-issue-tree.ps1")
    assert rnd2.returncode == 0, rnd2.stdout + rnd2.stderr
    chk2 = run(pwsh_exe, skill, repo, "issue-tree.ps1", "-Check")
    assert chk2.returncode == 0, chk2.stdout + chk2.stderr
