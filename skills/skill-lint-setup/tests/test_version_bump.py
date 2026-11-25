"""Tests for assets/check_skill_version_bump.py (the version-bump gate).

Covers: semver precedence, version extraction (incl. legacy key), staged /
worktree / base modes against real git repos, exemptions (new, deleted,
non-skill paths), the partial-stage hint, config errors, and the installed
hook blocking a real commit that forgets to bump.
Run with: python3 -m pytest skills -q
"""

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parents[1]
BUMP = SKILL_DIR / "assets" / "check_skill_version_bump.py"
VALIDATOR = SKILL_DIR / "assets" / "validate_frontmatter.py"
INSTALLER = SKILL_DIR / "scripts" / "setup_skill_lint.py"

DESC = "A demo skill for gate tests. USE FOR: testing. DO NOT USE FOR: prod."
# The strict parser rejects ': ' in plain scalars; quoted, as the schema
# battery writes it too.
QDESC = json.dumps(DESC)


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


B = _load(BUMP, "bump_asset")
V = _load(VALIDATOR, "validator_asset")


# --- unit: semver precedence ------------------------------------------------

@pytest.mark.parametrize(
    "new,old,expected",
    [
        ("1.0.1", "1.0.0", 1),
        ("2.0.0", "1.9.9", 1),
        ("1.0.0", "1.0.1", -1),
        ("1.0.0", "1.0.0", 0),
        ("1.0.0", "1.0.0-rc1", 1),     # release outranks its prerelease
        ("1.0.0-rc1", "1.0.0", -1),    # ... and the reverse is a downgrade
        ("1.0.0-rc2", "1.0.0-rc1", 1),
        ("1.0.0-alpha", "1.0.0-alpha.1", -1),  # fewer fields lower
        ("1.0.0-alpha.1", "1.0.0-alpha.2", -1),
        ("1.0.0-1", "1.0.0-alpha", -1),        # numeric below alphanumeric
        ("1.0.0+a", "1.0.0+b", 0),             # build metadata ignored
        ("1.0.0+build.1", "1.0.0", 0),
        ("1.0", "1.0.0", None),                # non-semver -> caller decides
        ("v1.0.0", "1.0.0", None),
    ],
)
def test_semver_cmp(new: str, old: str, expected: int | None) -> None:
    assert B._semver_cmp(new, old) == expected


@pytest.mark.parametrize(
    "old,expected",
    [("1.0.0", "1.0.1"), ("0.9.9", "0.9.10"), ("2.3.4-rc1", "2.3.5"),
     ("not-semver", None)],
)
def test_suggest(old: str, expected: str | None) -> None:
    assert B._suggest(old) == expected


# --- unit: version extraction (reuses the validator's parser) ---------------

def test_version_of_metadata_key() -> None:
    v, err = B._version_of(V, "---\nname: x\nmetadata:\n  version: 1.2.3\n---\n")
    assert (v, err) == ("1.2.3", None)


def test_version_of_quoted_value() -> None:
    v, err = B._version_of(V, "---\nmetadata:\n  version: \"1.2.3-rc1\"\n---\n")
    assert (v, err) == ("1.2.3-rc1", None)


def test_version_of_legacy_top_level_key() -> None:
    # Pre-adoption baselines declared version at the top level; the gate must
    # still order against them instead of skipping.
    v, err = B._version_of(V, "---\nname: x\nversion: 9.9.9\n---\n")
    assert (v, err) == ("9.9.9", None)


def test_version_of_missing_key_reports_reason() -> None:
    v, err = B._version_of(V, "---\nname: x\n---\n")
    assert v is None
    assert "metadata.version missing" in err


def test_version_of_unparseable_frontmatter_reports_reason() -> None:
    v, err = B._version_of(V, "no frontmatter at all")
    assert v is None
    assert err  # non-empty reason, never a bare None


# --- integration helpers ----------------------------------------------------

def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, encoding="utf-8",
    )
    if check:
        assert result.returncode == 0, result.stderr
    return result


def run_bump(repo: Path, *flags: str) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(BUMP), "--root", str(repo), *flags],
        capture_output=True, text=True, encoding="utf-8",
    )
    return result.returncode, result.stdout + result.stderr


def skill_text(version: str = "1.0.0", body: str = "v1") -> str:
    return (
        "---\n"
        "name: demo-skill\n"
        f"description: {QDESC}\n"
        "metadata:\n"
        f"  version: {version}\n"
        "---\n"
        f"# demo-skill\n\n{body}\n"
    )


def make_repo(tmp_path: Path, *, skill: bool = True,
              version: str = "1.0.0") -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    if skill:
        write_skill(repo, version=version)
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t",
        "commit", "-q", "--allow-empty", "-m", "baseline")
    return repo


def write_skill(repo: Path, *, version: str = "1.0.0", body: str = "v1",
                name: str = "demo-skill") -> Path:
    skill_dir = repo / "skills" / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    path = skill_dir / "SKILL.md"
    if name != "demo-skill":
        text = skill_text(version, body).replace("demo-skill", name)
    else:
        text = skill_text(version, body)
    path.write_text(text, encoding="utf-8")
    return path


# --- integration: staged mode (pre-commit) ----------------------------------

def test_staged_change_without_bump_fails(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_skill(repo, body="v2 changed")  # content edit, same version
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 1, out
    assert "[FAIL]" in out and "still 1.0.0" in out
    assert "(e.g. 1.0.1)" in out  # concrete fix offered


def test_staged_change_with_bump_passes(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_skill(repo, version="1.1.0", body="v2 changed")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "[PASS]" in out and "1.0.0 -> 1.1.0" in out


def test_partial_stage_hint_names_the_unstaged_bump(tmp_path: Path) -> None:
    # Bump exists in the working tree but only the other file is staged:
    # the commit would record a changed skill with an old version.
    repo = make_repo(tmp_path)
    write_skill(repo, version="1.1.0", body="v2 changed")
    extra = repo / "skills" / "demo-skill" / "notes.md"
    extra.write_text("helper file\n", encoding="utf-8")
    git(repo, "add", str(extra))  # stage the helper only
    code, out = run_bump(repo, "--staged")
    assert code == 1, out
    assert "stage it: git add skills/demo-skill/SKILL.md" in out


def test_downgrade_fails(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, version="2.0.0")
    write_skill(repo, version="1.9.0", body="rewound")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 1, out
    assert "went backwards" in out and "2.0.0 -> 1.9.0" in out


def test_prerelease_to_release_passes(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, version="1.0.0-rc1")
    write_skill(repo, version="1.0.0", body="released")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out


def test_release_to_prerelease_fails(tmp_path: Path) -> None:
    # Semver says 1.0.0-rc1 < 1.0.0: a "bump" backwards must not pass.
    repo = make_repo(tmp_path, version="1.0.0")
    write_skill(repo, version="1.0.0-rc1", body="un-released")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 1, out
    assert "went backwards" in out


def test_build_metadata_change_counts_as_changed(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, version="1.0.0+build1")
    write_skill(repo, version="1.0.0+build2", body="rebuilt")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out


def test_non_semver_baseline_uses_string_inequality(tmp_path: Path) -> None:
    # Format validity is the validator's job; the gate only asks "did it move".
    # Quoted, so the parser keeps them strings (bare 1.0 would parse as float
    # and read as an unreadable version, which the gate would FAIL instead).
    repo = make_repo(tmp_path, version='"1.0"')
    write_skill(repo, version='"1.1"', body="moved")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out


def test_missing_current_version_fails_with_validator_pointer(
    tmp_path: Path,
) -> None:
    repo = make_repo(tmp_path)
    path = repo / "skills" / "demo-skill" / "SKILL.md"
    path.write_text("---\nname: demo-skill\ndescription: " + QDESC +
                    "\n---\n# demo-skill\n", encoding="utf-8")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 1, out
    assert "cannot read metadata.version" in out
    assert "validate_skill_frontmatter" in out


# --- integration: exemptions ------------------------------------------------

def test_new_skill_passes_without_bump(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_skill(repo, version="0.1.0", name="second-skill")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "[PASS]" in out and "new skill" in out


def test_deleted_skill_skips(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    shutil.rmtree(repo / "skills" / "demo-skill")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "[SKIP]" in out and "removed" in out


def test_non_skill_paths_are_ignored(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, skill=False)
    (repo / "skills").mkdir(exist_ok=True)
    (repo / "skills" / "README.md").write_text("catalog\n", encoding="utf-8")
    (repo / "docs.md").write_text("root file\n", encoding="utf-8")
    archived = repo / "skills" / ".archived" / "old-skill"
    archived.mkdir(parents=True)
    (archived / "SKILL.md").write_text(skill_text(), encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t",
        "commit", "-q", "-m", "baseline")
    # Now change all three non-live-skill locations.
    (repo / "skills" / "README.md").write_text("catalog v2\n", encoding="utf-8")
    (repo / "docs.md").write_text("root file v2\n", encoding="utf-8")
    (archived / "SKILL.md").write_text(skill_text(body="v2"), encoding="utf-8")
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "no skill files changed" in out


def test_baseline_without_version_skips_explicitly(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, skill=False)
    skill_dir = repo / "skills" / "demo-skill"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "---\nname: demo-skill\ndescription: " + QDESC + "\n---\n# demo\n",
        encoding="utf-8",
    )
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t",
        "commit", "-q", "-m", "pre-adoption baseline")
    write_skill(repo, body="v2 with version now")  # version added
    git(repo, "add", "-A")
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "[SKIP]" in out and "pre-adoption history" in out


# --- integration: worktree (default) and base modes -------------------------

def test_default_mode_counts_untracked_files(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "skills" / "demo-skill" / "new-script.py").write_text(
        "# untracked addition\n", encoding="utf-8",
    )
    code, out = run_bump(repo)
    assert code == 1, out
    assert "still 1.0.0" in out


def test_default_mode_clean_worktree_is_green(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    code, out = run_bump(repo)
    assert code == 0, out
    assert "no skill files changed" in out


def test_base_mode_flags_range_without_bump(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    base = git(repo, "rev-parse", "HEAD").stdout.strip()
    write_skill(repo, body="v2 changed")  # forgot the bump
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t",
        "commit", "-q", "-m", "change without bump")
    code, out = run_bump(repo, "--base", base)
    assert code == 1, out
    assert "still 1.0.0" in out


def test_base_mode_green_when_range_carries_bump(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    base = git(repo, "rev-parse", "HEAD").stdout.strip()
    write_skill(repo, version="1.1.0", body="v2 changed")
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t",
        "commit", "-q", "-m", "change with bump")
    code, out = run_bump(repo, "--base", base)
    assert code == 0, out


def test_base_mode_only_checks_commits_not_worktree(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    base = git(repo, "rev-parse", "HEAD").stdout.strip()
    write_skill(repo, body="uncommitted edit")  # dirty but uncommitted
    code, out = run_bump(repo, "--base", base)
    assert code == 0, out
    assert "no skill files changed" in out


def test_unknown_base_ref_exits_2(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    code, out = run_bump(repo, "--base", "no-such-ref")
    assert code == 2, out
    assert "not a resolvable commit" in out


# --- integration: inert / config states -------------------------------------

def test_non_git_directory_skips(tmp_path: Path) -> None:
    plain = tmp_path / "plain"
    plain.mkdir()
    code, out = run_bump(plain)
    assert code == 0, out
    assert "[SKIP]" in out and "not a git repository" in out


def test_repo_without_commits_skips(tmp_path: Path) -> None:
    repo = tmp_path / "fresh"
    repo.mkdir()
    git(repo, "init", "-q")
    write_skill(repo)
    code, out = run_bump(repo, "--staged")
    assert code == 0, out
    assert "no baseline commit" in out


def test_missing_sibling_validator_exits_2(tmp_path: Path) -> None:
    # Ship-check: the bump gate refuses to invent its own YAML parser.
    lonely = tmp_path / "lonely"
    lonely.mkdir()
    shutil.copyfile(BUMP, lonely / "check_skill_version_bump.py")
    result = subprocess.run(
        [sys.executable, str(lonely / "check_skill_version_bump.py"),
         "--root", str(tmp_path)],
        capture_output=True, text=True, encoding="utf-8",
    )
    assert result.returncode == 2
    assert "sibling validator not found" in result.stdout + result.stderr


# --- integration: installed gate blocks a real commit -----------------------

def _install(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True,
                   capture_output=True)
    result = subprocess.run(
        [sys.executable, str(INSTALLER), "--repo", str(repo)],
        capture_output=True, text=True, encoding="utf-8",
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return repo


def _commit(repo: Path, message: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
         "commit", "-q", "-m", message],
        capture_output=True, text=True, encoding="utf-8",
    )


def test_installed_hook_blocks_real_commit_without_bump(
    tmp_path: Path,
) -> None:
    repo = _install(tmp_path)
    write_skill(repo)
    git(repo, "add", "-A")
    first = _commit(repo, "baseline skill")
    assert first.returncode == 0, first.stdout + first.stderr

    write_skill(repo, body="edited without bumping")
    git(repo, "add", "-A")
    blocked = _commit(repo, "forgot to bump")
    assert blocked.returncode == 1, blocked.stdout + blocked.stderr
    assert "still 1.0.0" in blocked.stdout + blocked.stderr

    write_skill(repo, version="1.0.1", body="edited without bumping")
    git(repo, "add", "-A")
    ok = _commit(repo, "with bump")
    assert ok.returncode == 0, ok.stdout + ok.stderr
