"""End-to-end tests for the tree-template versioning contract.

The generated view (.issues/tree.html) embeds the template version so consumer
repos can detect version drift, and assets/tree-template.version.json
fingerprints assets/tree-template.html so an edit without a version bump fails
every render. These tests exercise the contract the way a consumer repo does:
copy the skill into a temp dir, run its scripts from a throwaway repo, assert
exit codes and messages.

Origin: throwaway script from the 2026-11-20 versioning session, persisted so
the suite wired into workspace-check (pre-push) keeps render/bump/drift covered.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

TREE_MD = """SUMMARY|themes=1|issues=2|open=2
NEXT|0002|0001|P1|open|Second sample issue

## THEME|0001|P1|open|Sample theme

   - 0001|0001||P1|open|First sample issue
   - 0002|0001||P2|open|Second sample issue
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
def view(tmp_path: Path, pwsh_exe: str) -> SimpleNamespace:
    """A consumer-style install: the skill copied beside a repo holding a tree."""
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)
    repo = tmp_path / "repo"
    (repo / ".issues").mkdir(parents=True)
    (repo / ".issues" / "tree.md").write_text(TREE_MD, encoding="utf-8")

    def run(script: Path, *args: str) -> subprocess.CompletedProcess:
        return run_script(pwsh_exe, script, args, repo)

    ns = SimpleNamespace(
        run=run,
        repo=repo,
        render=skill / "scripts" / "render-issue-tree.ps1",
        bump=skill / "scripts" / "bump-tree-template-version.ps1",
        template=skill / "assets" / "tree-template.html",
        version_file=skill / "assets" / "tree-template.version.json",
        html=repo / ".issues" / "tree.html",
    )
    ns.recorded_version = json.loads(ns.version_file.read_text(encoding="utf-8"))["version"]
    return ns


def next_major(version: str) -> str:
    """A version guaranteed above the current one (bump refuses downgrades)."""
    major = int(version.split("-", 1)[0].split("+", 1)[0].split(".")[0])
    return f"{major + 1}.0.0"


def test_render_embeds_recorded_version(view: SimpleNamespace) -> None:
    out = view.run(view.render)
    assert out.returncode == 0, out.stdout + out.stderr
    version = view.recorded_version
    assert f"template v{version}" in out.stdout
    html = view.html.read_text(encoding="utf-8")
    assert f'name="tree-template-version" content="{version}"' in html
    assert f"template v<code>{version}</code>" in html
    assert "__TREE_TEMPLATE_VERSION__" not in html
    check = view.run(view.render, "-Check")
    assert check.returncode == 0, check.stdout + check.stderr


def test_line_ending_conversion_never_trips_the_fingerprint(view: SimpleNamespace) -> None:
    # The fingerprint normalizes CRLF/CR to LF, so checkout or publishing line
    # endings cannot cause a false drift.
    assert view.run(view.render).returncode == 0
    text = view.template.read_text(encoding="utf-8")  # universal newlines -> \n
    with view.template.open("w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    check = view.run(view.render, "-Check")
    assert check.returncode == 0, check.stdout + check.stderr


def test_unbumped_template_edit_refuses_render_and_check(view: SimpleNamespace) -> None:
    with view.template.open("a", encoding="utf-8", newline="") as fh:
        fh.write("<!-- version-bump probe -->\n")
    for args in ((), ("-Check",)):
        out = view.run(view.render, *args)
        assert out.returncode == 1, out.stdout + out.stderr
        assert "changed without a version bump" in out.stdout
        assert "bump-tree-template-version.ps1" in out.stdout


def test_version_drift_detected_then_patched_by_rerender(view: SimpleNamespace) -> None:
    old = view.recorded_version
    new = next_major(old)
    assert view.run(view.render).returncode == 0

    bump = view.run(view.bump, "-Version", new)
    assert bump.returncode == 0, bump.stdout + bump.stderr
    assert f"v{old} -> v{new}" in bump.stdout

    check = view.run(view.render, "-Check")
    assert check.returncode == 1, check.stdout
    assert f"version drift: generated with template v{old}, current template is v{new}" in check.stdout
    assert "patch it (re-render embeds the new version)" in check.stdout

    out = view.run(view.render)
    assert out.returncode == 0, out.stdout + out.stderr
    assert f"template v{new}" in out.stdout
    assert f'name="tree-template-version" content="{new}"' in view.html.read_text(encoding="utf-8")
    assert view.run(view.render, "-Check").returncode == 0


def test_data_staleness_reported_distinctly_from_drift(view: SimpleNamespace) -> None:
    assert view.run(view.render).returncode == 0
    tree = view.repo / ".issues" / "tree.md"
    tree.write_text(
        tree.read_text(encoding="utf-8").replace("First sample issue", "Renamed sample issue"),
        encoding="utf-8",
    )
    check = view.run(view.render, "-Check")
    assert check.returncode == 1, check.stdout
    assert "stale (tree data changed)" in check.stdout
    assert "version drift" not in check.stdout
    assert view.run(view.render).returncode == 0


def test_bump_guardrails(view: SimpleNamespace) -> None:
    current = view.recorded_version
    core = current.split("-", 1)[0].split("+", 1)[0]

    invalid = view.run(view.bump, "-Version", "vNext")
    assert invalid.returncode == 1 and "not a MAJOR.MINOR.PATCH" in invalid.stdout

    noop = view.run(view.bump, "-Version", current)
    assert noop.returncode == 1 and f"already at v{current}" in noop.stdout

    # 0.0.0 is below any real recorded version (monotonic from 1.0.0).
    downgrade = view.run(view.bump, "-Version", "0.0.0")
    assert downgrade.returncode == 1 and "refusing downgrade" in downgrade.stdout

    same_core = view.run(view.bump, "-Version", f"{core}-retrotest")
    assert same_core.returncode == 1 and "core version unchanged" in same_core.stdout


def test_corrupt_or_missing_version_file_fails_then_repairs(view: SimpleNamespace) -> None:
    view.version_file.write_text('{ "version": "1.2.3", "sha256": "not-a-digest" }\n', encoding="utf-8")
    out = view.run(view.render)
    assert out.returncode == 1 and "'sha256' must be" in out.stdout

    repaired_to = next_major(view.recorded_version)
    repair = view.run(view.bump, "-Version", repaired_to)
    assert repair.returncode == 0, repair.stdout + repair.stderr
    assert "existing version file has issues" in repair.stdout
    assert view.run(view.render).returncode == 0

    view.version_file.unlink()
    missing = view.run(view.render, "-Check")
    assert missing.returncode == 1 and "not found" in missing.stdout

    bootstrapped_to = next_major(repaired_to)
    bootstrap = view.run(view.bump, "-Version", bootstrapped_to)
    assert bootstrap.returncode == 0, bootstrap.stdout + bootstrap.stderr
    assert f"recorded v{bootstrapped_to}" in bootstrap.stdout


def test_legacy_output_without_version_marker_detected(view: SimpleNamespace) -> None:
    assert view.run(view.render).returncode == 0
    html = view.html.read_text(encoding="utf-8")
    html = re.sub(r'<meta name="tree-template-version"[^>]*>', "", html)
    html = re.sub(r" — template v<code>[^<]*</code>", "", html)
    view.html.write_text(html, encoding="utf-8")
    check = view.run(view.render, "-Check")
    assert check.returncode == 1, check.stdout
    assert "no template version marker" in check.stdout
