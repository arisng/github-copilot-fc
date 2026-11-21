"""End-to-end tests for issue-tracker-init.ps1's GitHub tree fields.

The manifest writer must know every key the schema documents (sketch v6
section 1.1): -Apply -Force used to silently strip keys it did not emit
(proven in critique section A5), and it actively refused -TreeFile for
tracker github. These tests exercise the contract the way a consumer repo
does: copy the skill into a temp dir, run issue-tracker-init.ps1 from a
throwaway repo, assert exit codes, messages, and the written JSON.

issueQuery validation is delegated to scripts/query-composition-lib.ps1
(dot-sourced by the writer) - these tests pin the integration, not the
library's full reject list (covered by test_query_composition.py).

Origin: FLEET TASK F4 (2026-11-21), sketch v6 sections 1.1/1.2/7 and
critique section A5.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]

GITHUB_BASE = ("-Apply", "-Tracker", "github", "-Repo", "owner/name")
VALID_QUERY = "label:area/* milestone:v2 -label:spam sort:updated-desc"
FULL_ARGS = GITHUB_BASE + (
    "-TreeFile",
    ".issues/gh-tree.md",
    "-TreeMaxIssues",
    "500",
    "-TreeLookbackDays",
    "90",
    "-TreeIncludeClosed:$false",
    "-TreeMinPriority",
    "P2",
    "-TreeFreshnessHours",
    "12",
    "-IssueQuery",
    VALID_QUERY,
)
NEW_KEYS = {
    "treeSource",
    "treeFile",
    "treeMaxIssues",
    "treeLookbackDays",
    "treeIncludeClosed",
    "treeMinPriority",
    "treeFreshnessHours",
    "issueQuery",
}
# treeFile predates this change (local-markdown default) - only these are new.
GITHUB_ONLY_KEYS = NEW_KEYS - {"treeFile"}


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
    """A consumer-style install: the skill copied beside an empty repo."""
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_DIR, skill)
    repo = tmp_path / "repo"
    repo.mkdir()

    def run(*args: str) -> subprocess.CompletedProcess:
        return run_script(pwsh_exe, skill / "scripts" / "issue-tracker-init.ps1", args, repo)

    ns = SimpleNamespace(run=run, repo=repo, manifest=repo / ".github" / "issue-tracker.json")

    def read() -> dict:
        return json.loads(ns.manifest.read_text(encoding="utf-8"))

    ns.read = read
    return ns


def test_github_apply_writes_all_new_keys(env: SimpleNamespace) -> None:
    out = env.run(*FULL_ARGS)
    assert out.returncode == 0, out.stdout + out.stderr
    m = env.read()
    assert m["tracker"] == "github"
    assert m["repo"] == "owner/name"
    assert m["treeSource"] == "github"
    assert m["treeFile"] == ".issues/gh-tree.md"
    assert m["treeMaxIssues"] == 500
    assert m["treeLookbackDays"] == 90
    assert m["treeIncludeClosed"] is False  # JSON boolean, not "false"
    assert m["treeMinPriority"] == "P2"
    assert m["treeFreshnessHours"] == 12
    assert m["issueQuery"] == VALID_QUERY
    # Canonical order starts: identity, then tree config.
    assert list(m)[:4] == ["schemaVersion", "tracker", "treeSource", "treeFile"]


def test_force_rewrite_preserves_new_keys(env: SimpleNamespace) -> None:
    # The A5 regression: a -Force rewrite must not strip keys the writer now
    # knows - same arguments in, byte-identical manifest out.
    first = env.run(*FULL_ARGS)
    assert first.returncode == 0, first.stdout + first.stderr
    before = env.read()
    second = env.run(*FULL_ARGS, "-Force")
    assert second.returncode == 0, second.stdout + second.stderr
    after = env.read()
    assert after == before
    for key in NEW_KEYS:
        assert key in after, f"-Force stripped {key}"
    assert after["treeMaxIssues"] == 500
    assert after["issueQuery"] == VALID_QUERY


def test_minimal_force_rewrite_keeps_a5_keys(env: SimpleNamespace) -> None:
    # Critique A5's literal BEFORE manifest, rewritten with minimal arguments:
    # treeSource and the defaulted limits must survive (the writer emits them
    # even when the flags are absent).
    env.manifest.parent.mkdir(parents=True)
    env.manifest.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "tracker": "github",
                "repo": "owner/name",
                "treeSource": "github",
                "treeMaxIssues": 300,
                "treeLookbackDays": 365,
            }
        ),
        encoding="utf-8",
    )
    out = env.run(*GITHUB_BASE, "-Force")
    assert out.returncode == 0, out.stdout + out.stderr
    m = env.read()
    assert m["treeSource"] == "github"
    assert m["treeMaxIssues"] == 300
    assert m["treeLookbackDays"] == 365
    assert m["treeIncludeClosed"] is True
    assert m["repo"] == "owner/name"


@pytest.mark.parametrize(
    ("query", "needle"),
    [
        ('label:"unbalanced', "unbalanced double quotes"),
        ("is:pr", "is:pr cannot be used"),
        ("repo:x/y", "repo: is not allowed"),
        ("", "issueQuery must not be empty"),
    ],
    ids=["unbalanced-quote", "is-pr", "repo", "empty"],
)
def test_invalid_issue_query_rejected(env: SimpleNamespace, query: str, needle: str) -> None:
    out = env.run(*GITHUB_BASE, "-IssueQuery", query)
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout
    assert not env.manifest.exists(), "a rejected query must not write a manifest"


def test_sort_qualifier_accepted(env: SimpleNamespace) -> None:
    # sort: is a supported qualifier (lib contract) - selection semantics.
    out = env.run(*GITHUB_BASE, "-IssueQuery", "sort:updated-desc")
    assert out.returncode == 0, out.stdout + out.stderr
    assert env.read()["issueQuery"] == "sort:updated-desc"


def test_azure_devops_rejects_tree_file_and_issue_query(env: SimpleNamespace) -> None:
    out = env.run(
        "-Apply",
        "-Tracker",
        "azure-devops",
        "-Org",
        "org",
        "-Project",
        "project",
        "-TreeFile",
        ".issues/t.md",
        "-IssueQuery",
        "label:bug",
    )
    assert out.returncode == 1, out.stdout + out.stderr
    assert "treeFile" in out.stdout and "only applies" in out.stdout, out.stdout
    assert "issueQuery" in out.stdout and "only applies" in out.stdout, out.stdout
    assert not env.manifest.exists()


def test_local_markdown_path_unchanged(env: SimpleNamespace) -> None:
    out = env.run("-Apply", "-Tracker", "local-markdown")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "wrote .github/issue-tracker.json (tracker=local-markdown, store=.issues)" in out.stdout
    m = env.read()
    assert m["tracker"] == "local-markdown"
    assert m["issuesDir"] == ".issues"
    assert m["archiveDir"] == ".issues/archived"
    assert m["treeFile"] == ".issues/tree.md"
    assert GITHUB_ONLY_KEYS.isdisjoint(m), "local-markdown gained github-only keys"


@pytest.mark.parametrize(
    ("flag", "value", "needle"),
    [
        ("-TreeSource", "gitlab", "treeSource"),
        ("-TreeMaxIssues", "0", "positive integer"),
        ("-TreeLookbackDays", "0", "positive integer"),
        ("-TreeFreshnessHours", "0", "positive integer"),
    ],
    ids=["tree-source-enum", "max-issues", "lookback", "freshness"],
)
def test_option_value_validation(
    env: SimpleNamespace, flag: str, value: str, needle: str
) -> None:
    out = env.run(*GITHUB_BASE, flag, value)
    assert out.returncode == 1, out.stdout + out.stderr
    assert needle in out.stdout, out.stdout
    assert not env.manifest.exists()


def test_no_tree_omits_tree_source(env: SimpleNamespace) -> None:
    out = env.run(*GITHUB_BASE, "-NoTree")
    assert out.returncode == 0, out.stdout + out.stderr
    m = env.read()
    assert "treeSource" not in m
    # The rest of the github shape is unaffected by the opt-out.
    assert m["treeMaxIssues"] == 300
    assert m["treeLookbackDays"] == 365
    assert m["treeIncludeClosed"] is True


def test_no_tree_conflicts_with_explicit_tree_source(env: SimpleNamespace) -> None:
    out = env.run(*GITHUB_BASE, "-NoTree", "-TreeSource", "github")
    assert out.returncode == 1, out.stdout + out.stderr
    assert "-NoTree" in out.stdout and "-TreeSource" in out.stdout, out.stdout
    assert not env.manifest.exists()
