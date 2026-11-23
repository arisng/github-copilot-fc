"""Issue-template enforcement and the manifest template registry.

The skill now gates every store file against a per-type issue template
(references/issue-templates.md): skill defaults in assets/issue-templates,
replaced per type by consumer templates registered in
.github/issue-tracker.json (issueTemplatesDir + issueTemplateOverrides).

These tests exercise the contract the way a consumer repo does: copy the skill
into a temp dir, run the scripts from a throwaway repo, assert exit codes,
messages, and the written manifest. Every test here fails without the
enforcement/registry change (the gate used to accept any frontmatter shape).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

THEME_FILE = """---
id: "0001"
title: "Sample theme"
status: open
priority: P1
type: theme
created: 2026-01-01
---

## Summary

Theme body.

## Notes

Fixture notes.
"""

TASK_FILE = """---
id: "0002"
title: "Sample task"
status: open
priority: P2
type: task
theme: 0001
created: 2026-01-02
---

## Summary

Task body.

## Notes

Fixture notes.
"""

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
def env(tmp_path: Path, pwsh_exe: str) -> SimpleNamespace:
    """A consumer-style install: the skill copied beside a repo with a store."""
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)
    repo = tmp_path / "repo"
    (repo / ".issues").mkdir(parents=True)
    (repo / ".github").mkdir()
    (repo / ".github" / "issue-tracker.json").write_text(
        json.dumps(LOCAL_MANIFEST), encoding="utf-8"
    )
    (repo / ".issues" / "0001-sample-theme.md").write_text(THEME_FILE, encoding="utf-8")
    (repo / ".issues" / "0002-sample-task.md").write_text(TASK_FILE, encoding="utf-8")

    ns = SimpleNamespace(repo=repo, skill=skill, templates=repo / ".github" / "ISSUE_TEMPLATE")

    def run(script: str, *args: str) -> subprocess.CompletedProcess:
        return run_script(pwsh_exe, skill / "scripts" / script, args, repo)

    def manifest(**extra) -> None:
        data = dict(LOCAL_MANIFEST)
        data.update(extra)
        (repo / ".github" / "issue-tracker.json").write_text(json.dumps(data), encoding="utf-8")

    def write_template(name: str, text: str) -> Path:
        ns.templates.mkdir(parents=True, exist_ok=True)
        path = ns.templates / name
        path.write_text(text, encoding="utf-8")
        return path

    ns.run = run
    ns.manifest = manifest
    ns.write_template = write_template
    return ns


CONSUMER_TASK = """---
name: Custom task
about: Consumer-shaped task template
title: "[Task] "
labels: []
assignees: []
type: task
status: open
priority: P1
requiredFields: severity
optionalFields: component
---

## Impact

## Notes
"""


def test_default_templates_are_valid(env: SimpleNamespace) -> None:
    out = env.run("issue-template.ps1", "-Validate")
    assert out.returncode == 0, out.stdout + out.stderr
    # The shipped taxonomy is GitHub's own default type vocabulary.
    assert "issue-template: OK (3 templates, 0 override(s))" in out.stdout


def test_conforming_store_passes_the_gate(env: SimpleNamespace) -> None:
    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    assert "wrote .issues/tree.md" in gen.stdout
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


@pytest.mark.parametrize(
    ("body", "prefix", "needle"),
    [
        (
            TASK_FILE.replace("## Notes\n\nFixture notes.\n", ""),
            "TEMPLATE",
            "missing required section 'Notes' (template 'task')",
        ),
        (
            TASK_FILE.replace("created: 2026-01-02", "created: 2026-01-02\nseverity: high"),
            "TEMPLATE",
            "unknown frontmatter field 'severity' (template 'task' does not declare it)",
        ),
        (
            TASK_FILE.replace("created: 2026-01-02", "created: 02/01/2026"),
            "THEME",
            "created '02/01/2026' is not a YYYY-MM-DD date",
        ),
        (
            TASK_FILE.replace("created: 2026-01-02", "created: 2026-01-02\nnotes: x").replace(
                "## Notes\n\nFixture notes.", "## Notes\n\nFixture notes.\n\n### Sub"
            ),
            "TEMPLATE",
            "unknown frontmatter field 'notes'",
        ),
    ],
    ids=["missing-section", "unknown-field", "bad-created", "undeclared-field"],
)
def test_gate_rejects_nonconforming_issues(
    env: SimpleNamespace, body: str, prefix: str, needle: str
) -> None:
    (env.repo / ".issues" / "0002-sample-task.md").write_text(body, encoding="utf-8")
    for args in ((), ("-Check",)):
        out = env.run("issue-tree.ps1", *args)
        assert out.returncode == 1, out.stdout + out.stderr
        assert f"{prefix}   .issues/0002-sample-task.md: {needle}" in out.stdout, out.stdout
    assert not (env.repo / ".issues" / "tree.md").exists(), "a refused store must not write"


def test_registered_override_replaces_the_default_for_its_type(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    env.manifest(
        issueTemplatesDir=".github/ISSUE_TEMPLATE",
        issueTemplateOverrides={"task": "custom-task.md"},
    )

    # The default shape is now wrong for type task (severity is required).
    out = env.run("issue-tree.ps1", "-Check")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "missing required frontmatter field 'severity' (template 'task')" in out.stdout
    assert "missing required section 'Impact' (template 'task')" in out.stdout

    # The consumer shape passes, and theme keeps the skill default.
    conforming = TASK_FILE.replace(
        "created: 2026-01-02", "created: 2026-01-02\nseverity: high"
    ).replace("## Summary", "## Impact")
    (env.repo / ".issues" / "0002-sample-task.md").write_text(conforming, encoding="utf-8")
    gen = env.run("issue-tree.ps1")
    assert gen.returncode == 0, gen.stdout + gen.stderr
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


def test_list_and_show_expose_the_resolved_registry(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    env.manifest(
        issueTemplatesDir=".github/ISSUE_TEMPLATE",
        issueTemplateOverrides={"task": "custom-task.md"},
    )
    listing = env.run("issue-template.ps1", "-List")
    assert listing.returncode == 0, listing.stdout + listing.stderr
    assert "TEMPLATE|task|override|.github/ISSUE_TEMPLATE/custom-task.md|Custom task" in listing.stdout
    # bug keeps the skill default; the shipped set is the GitHub-aligned trio.
    assert "TEMPLATE|bug|default|skill assets/issue-templates/bug.md|Bug" in listing.stdout
    assert "TEMPLATE|feature|default|skill assets/issue-templates/feature.md|Feature" in listing.stdout
    assert "TEMPLATE|theme|" not in listing.stdout, "theme is a label concept, not a default type"

    shown = env.run("issue-template.ps1", "-Show", "task")
    assert shown.returncode == 0, shown.stdout + shown.stderr
    assert "name: Custom task" in shown.stdout and "## Impact" in shown.stdout

    unknown = env.run("issue-template.ps1", "-Show", "nope")
    assert unknown.returncode == 1, unknown.stdout + unknown.stderr
    assert "unknown issue type 'nope'" in unknown.stdout


def test_unregistered_template_file_is_ignored(env: SimpleNamespace) -> None:
    # A native GitHub.com template in the dir must not become the task shape.
    env.write_template("github-native.md", CONSUMER_TASK)
    env.manifest(issueTemplatesDir=".github/ISSUE_TEMPLATE")
    out = env.run("issue-tree.ps1")
    assert out.returncode == 0, out.stdout + out.stderr
    chk = env.run("issue-tree.ps1", "-Check")
    assert chk.returncode == 0, chk.stdout + chk.stderr


@pytest.mark.parametrize(
    ("overrides", "needle"),
    [
        ({"bug": "absent.md"}, "registered template not found"),
        ({"widget": "custom-task.md"}, "registers unknown type 'widget'"),
        ({"task": "nested/custom-task.md"}, "is not a plain .md filename"),
        ({"bug": "custom-task.md"}, "template declares type 'task' but is registered for 'bug'"),
    ],
    ids=["missing-file", "unknown-type", "path-separator", "type-mismatch"],
)
def test_broken_registration_fails_the_gate(
    env: SimpleNamespace, overrides: dict, needle: str
) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    env.manifest(issueTemplatesDir=".github/ISSUE_TEMPLATE", issueTemplateOverrides=overrides)
    out = env.run("issue-tree.ps1", "-Check")
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout


@pytest.mark.parametrize(
    ("template", "needle"),
    [
        (CONSUMER_TASK.replace("name: Custom task\n", ""), "'name' is required"),
        (CONSUMER_TASK.replace("about: Consumer-shaped task template\n", ""), "'about' is required"),
        (CONSUMER_TASK.replace("type: task", "type: widget"), "template type 'widget' is not one of"),
        (CONSUMER_TASK.replace("type: task", "type: task\nbogus: 1"), "unknown template frontmatter field 'bogus'"),
        (CONSUMER_TASK.replace("requiredFields: severity", "requiredFields: title"), "part of the core issue contract"),
        (CONSUMER_TASK.replace("requiredFields: severity", "requiredFields: theme"), "reserved link field"),
        (CONSUMER_TASK.replace("requiredFields: severity", "requiredFields: severity, severity"), "declared twice"),
        (CONSUMER_TASK.split("## Impact")[0], "at least one required section"),
        ("---\nname: X\n", "missing or malformed YAML frontmatter"),
    ],
    ids=[
        "no-name",
        "no-about",
        "bad-type",
        "unknown-key",
        "core-redeclare",
        "link-redeclare",
        "duplicate-declare",
        "no-sections",
        "no-frontmatter",
    ],
)
def test_template_self_validation(
    env: SimpleNamespace, template: str, needle: str
) -> None:
    env.write_template("custom-task.md", template)
    env.manifest(
        issueTemplatesDir=".github/ISSUE_TEMPLATE",
        issueTemplateOverrides={"task": "custom-task.md"},
    )
    out = env.run("issue-template.ps1", "-Validate")
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout


def test_template_cli_refuses_non_local_trackers(env: SimpleNamespace) -> None:
    env.manifest(tracker="github", repo="owner/name")
    out = env.run("issue-template.ps1", "-List")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "tracker 'github' is not local-markdown" in out.stdout


def test_comments_quotes_and_fences_do_not_break_parsing(env: SimpleNamespace) -> None:
    # Quoted title with ' #', inline comment on another field, and a fenced
    # '## Notes' example that must NOT satisfy the section requirement.
    body = """---
id: "0002"   # allocated
title: "Fix widget #42"
status: open
priority: P2
type: task
theme: 0001
created: 2026-01-02
---

## Summary

Task body.

```
## Notes
```

Still no real Notes section.
"""
    (env.repo / ".issues" / "0002-sample-task.md").write_text(body, encoding="utf-8")
    out = env.run("issue-tree.ps1", "-Check")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "missing required section 'Notes' (template 'task')" in out.stdout


# --- Manifest writer: registration, carry-over, and validation ---------------

INIT = "issue-tracker-init.ps1"


def test_writer_registers_override_and_carries_it_over(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    first = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force",
                    "-IssueTemplateOverride", "task=custom-task.md")
    assert first.returncode == 0, first.stdout + first.stderr
    m = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert m["issueTemplatesDir"] == ".github/ISSUE_TEMPLATE"
    assert m["issueTemplateOverrides"] == {"task": "custom-task.md"}

    # A second -Force rewrite with no template flags must not drop it.
    second = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force")
    assert second.returncode == 0, second.stdout + second.stderr
    after = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert after["issueTemplateOverrides"] == {"task": "custom-task.md"}
    assert after["issueTemplatesDir"] == ".github/ISSUE_TEMPLATE"


def test_writer_merges_new_entries_into_the_carried_registry(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    env.write_template(
        "bug-report.md",
        CONSUMER_TASK.replace("type: task", "type: bug").replace("name: Custom task", "name: Bug"),
    )
    env.manifest(issueTemplatesDir="custom/templates",
                 issueTemplateOverrides={"task": "custom-task.md"})
    (env.repo / "custom" / "templates").mkdir(parents=True, exist_ok=True)
    for name in ("custom-task.md", "bug-report.md"):
        shutil.copy(env.templates / name, env.repo / "custom" / "templates" / name)

    out = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force",
                  "-IssueTemplateOverride", "bug=bug-report.md")
    assert out.returncode == 0, out.stdout + out.stderr
    m = json.loads((env.repo / ".github" / "issue-tracker.json").read_text(encoding="utf-8"))
    assert m["issueTemplatesDir"] == "custom/templates"  # carried dir kept
    assert m["issueTemplateOverrides"] == {
        "bug": "bug-report.md",
        "task": "custom-task.md",
    }


@pytest.mark.parametrize(
    ("args", "needle"),
    [
        (("-IssueTemplateOverride", "bug=absent.md"), "registered template not found"),
        (("-IssueTemplateOverride", "widget=custom-task.md"), "is not one of"),
        (("-IssueTemplateOverride", "bug=nested/x.md"), "must be a plain .md filename"),
        (("-IssueTemplateOverride", "bug"), "must look like <type>=<file.md>"),
    ],
    ids=["missing-file", "unknown-type", "path-separator", "malformed"],
)
def test_writer_rejects_bad_registrations(
    env: SimpleNamespace, args: tuple, needle: str
) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    out = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force", *args)
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout


def test_writer_rejects_type_mismatch(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    out = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force",
                  "-IssueTemplateOverride", "bug=custom-task.md")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "template declares type 'task' but is registered for 'bug'" in out.stdout


def test_writer_rejects_registry_for_github(env: SimpleNamespace) -> None:
    env.write_template("custom-task.md", CONSUMER_TASK)
    out = env.run(INIT, "-Apply", "-Tracker", "github", "-Repo", "owner/name",
                  "-Force", "-IssueTemplateOverride", "task=custom-task.md")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "issueTemplateOverrides only applies to tracker local-markdown" in out.stdout


def test_writer_rejects_rooted_templates_dir(env: SimpleNamespace) -> None:
    out = env.run(INIT, "-Apply", "-Tracker", "local-markdown", "-Force",
                  "-IssueTemplatesDir", "../outside")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "issueTemplatesDir '../outside' must be repo-relative" in out.stdout
