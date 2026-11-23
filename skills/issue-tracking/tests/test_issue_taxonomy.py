"""Issue `type` taxonomy and label-based theme roots.

GitHub's issue `type` is a first-class single-select field that is NOT a label;
grouping is a label concern. The skill therefore:

- classifies with `type`, defaulting to GitHub's own default vocabulary
  (task, bug, feature) and replacing it wholesale from the manifest's
  `issueTypes` array;
- treats a record as a theme ROOT by the `theme` label (or `theme:<slug>`),
  keeping `type: theme` as a permanently-accepted legacy alias.

These tests pin that split: the default taxonomy rejects non-GitHub types, an
explicit `issueTypes` list admits extensions, and a theme root needs no `type`
value at all. Every test fails against the old hard-coded
theme|epic|task|bug|chore enum that shipped before 2.0.
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


def issue_file(
    *,
    id: str,
    title: str,
    type_: str,
    theme: str | None = None,
    labels: str | None = None,
    status: str = "open",
    priority: str = "P2",
) -> str:
    lines = ["---", f'id: "{id}"', f'title: "{title}"', f"status: {status}", f"priority: {priority}", f"type: {type_}"]
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

    def manifest(**extra) -> None:
        data = dict(LOCAL_MANIFEST)
        data.update(extra)
        (repo / ".github" / "issue-tracker.json").write_text(json.dumps(data), encoding="utf-8")

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

    manifest()
    ns = SimpleNamespace(repo=repo, skill=skill, run=run, manifest=manifest, write=write)
    return ns


def test_default_taxonomy_rejects_epic_and_chore(env: SimpleNamespace) -> None:
    # GitHub ships task/bug/feature; epic and chore are opt-in extensions.
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="epic", theme="0001"))
    env.write("0003-b.md", issue_file(id="0003", title="B", type_="chore", theme="0001"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "invalid type 'epic' (configured types: task, bug, feature)" in out.stdout
    assert "invalid type 'chore' (configured types: task, bug, feature)" in out.stdout


def test_issue_types_override_admits_extension_types(env: SimpleNamespace) -> None:
    env.manifest(issueTypes=["task", "bug", "feature", "epic", "chore"])
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="epic", theme="0001"))
    env.write("0003-b.md", issue_file(id="0003", title="B", type_="chore", theme="0001"))
    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


def test_theme_root_needs_only_the_label(env: SimpleNamespace) -> None:
    # The root is classified as an ordinary task; the `theme` LABEL makes it
    # the grouping root, so no `type` value carries grouping semantics.
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="bug", theme="0001"))
    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    tree = (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")
    assert "## THEME|0001|P2|open|Root" in tree
    assert "SUMMARY|themes=1|issues=1" in tree


def test_theme_slug_label_also_marks_a_root(env: SimpleNamespace) -> None:
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme:payments"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="task", theme="0001"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr


def test_non_root_theme_target_fails_with_the_label_fix(env: SimpleNamespace) -> None:
    # A theme: link pointing at a record that is not a theme root is an error,
    # and the message names the actual fix (label it).
    env.write("0001-plain.md", issue_file(id="0001", title="Plain", type_="task"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="task", theme="0001"))
    out = env.run("issue-tree.ps1")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "is not a theme root (add the 'theme' label to it)" in out.stdout


def test_legacy_type_theme_still_resolves_as_a_root(env: SimpleNamespace) -> None:
    # Grouping moved to labels, but a store filed under the old taxonomy must
    # keep working: `type: theme` remains an accepted alias.
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="theme"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="task", theme="0001"))
    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    assert "## THEME|0001|" in (env.repo / ".issues" / "tree.md").read_text(encoding="utf-8")


def test_inventory_carries_labels(env: SimpleNamespace) -> None:
    # `labels` is a core field, so the machine inventory exposes it.
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme,area:core"))
    env.write("0002-a.md", issue_file(id="0002", title="A", type_="task", theme="0001"))
    out = env.run("issue-tree.ps1", "-Inventory")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "id|type|status|priority|theme|parent|order|file|labels|title" in out.stdout
    assert "0001|task|open|P2|-|-|999|0001-root.md|theme,area:core|Root" in out.stdout
    assert "0002|task|open|P2|0001|-|999|0002-a.md|-|A" in out.stdout


def test_writer_writes_only_a_non_default_taxonomy(env: SimpleNamespace) -> None:
    # A default-taxonomy repo keeps a minimal manifest.
    out = env.run("issue-tracker-init.ps1", "-Apply", "-Tracker", "local-markdown", "-Force")
    assert out.returncode == 0, out.stdout + out.stderr
    m = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert "issueTypes" not in m

    out = env.run(
        "issue-tracker-init.ps1", "-Apply", "-Tracker", "local-markdown",
        "-Force", "-IssueTypes", "task,bug,feature,epic",
    )
    assert out.returncode == 0, out.stdout + out.stderr
    m = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert m["issueTypes"] == ["task", "bug", "feature", "epic"]


def test_force_rewrite_carries_the_taxonomy_over(env: SimpleNamespace) -> None:
    first = env.run(
        "issue-tracker-init.ps1", "-Apply", "-Tracker", "local-markdown",
        "-Force", "-IssueTypes", "task,bug,root",
    )
    assert first.returncode == 0, first.stdout + first.stderr
    # A minimal rewrite must not strip the configured taxonomy.
    second = env.run("issue-tracker-init.ps1", "-Apply", "-Tracker", "local-markdown", "-Force")
    assert second.returncode == 0, second.stdout + second.stderr
    m = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert m["issueTypes"] == ["task", "bug", "root"]


@pytest.mark.parametrize(
    ("values", "needle"),
    [
        ("task,Bad Name", "is not a kebab-case type name"),
        ("task,task", "lists 'task' twice"),
        ("task,bug,feature,epic,chore,theme,bug2,bug3,bug4,bug5,bug6,bug7,bug8,bug9,b10,b11,b12,b13,b14,b15,b16,b17,b18,b19,b20,b21", "GitHub allows at most 25"),
    ],
    ids=["bad-name", "duplicate", "over-cap"],
)
def test_writer_rejects_invalid_taxonomy(
    env: SimpleNamespace, values: str, needle: str
) -> None:
    out = env.run(
        "issue-tracker-init.ps1", "-Apply", "-Tracker", "local-markdown",
        "-Force", "-IssueTypes", values,
    )
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout


def test_configured_type_without_a_template_fails_closed(env: SimpleNamespace) -> None:
    # Every configured type must resolve: `root` ships no template and none is
    # registered, so the gate names the registration it needs.
    env.manifest(issueTypes=["task", "bug", "root"])
    env.write("0001-root.md", issue_file(id="0001", title="Root", type_="task", labels="theme"))
    out = env.run("issue-template.ps1", "-Validate")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "type 'root' ships no skill default template - register one in issueTemplateOverrides" in out.stdout


def test_extension_templates_ship_under_the_extensions_folder(env: SimpleNamespace) -> None:
    env.manifest(issueTypes=["task", "bug", "feature", "theme", "epic", "chore"])
    listing = env.run("issue-template.ps1", "-List")
    assert listing.returncode == 0, listing.stdout + listing.stderr
    assert "TEMPLATE|theme|default|skill assets/issue-templates/extensions/theme.md|Theme" in listing.stdout
    assert "TEMPLATE|epic|default|skill assets/issue-templates/extensions/epic.md|Epic" in listing.stdout
    assert "TEMPLATE|feature|default|skill assets/issue-templates/feature.md|Feature" in listing.stdout


def test_show_reports_the_configured_types(env: SimpleNamespace) -> None:
    out = env.run("issue-template.ps1", "-Show", "theme")
    assert out.returncode == 1, out.stdout + out.stderr
    # `theme` is the legacy value: the message redirects to the label axis.
    assert "'theme' is a legacy type value, not a configured type" in out.stdout
    assert "grouping belongs on the 'theme' label" in out.stdout

    unknown = env.run("issue-template.ps1", "-Show", "widget")
    assert unknown.returncode == 1, unknown.stdout + unknown.stderr
    assert "unknown issue type 'widget' (configured types: task, bug, feature)" in unknown.stdout
