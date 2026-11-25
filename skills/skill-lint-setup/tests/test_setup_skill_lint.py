"""Tests for scripts/setup_skill_lint.py.

Covers fresh install, idempotent re-run, foreign-hook protection, hooksPath
policy (never clobber), opt-in CI, dry-run, and non-git handling.
Run with: python3 -m pytest skills -q
"""

import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "setup_skill_lint.py"


def run_setup(repo: Path, *flags: str) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--repo", str(repo), *flags],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def make_repo(tmp_path: Path, git: bool = True) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    if git:
        subprocess.run(["git", "init", "-q", str(repo)], check=True, capture_output=True)
    return repo


def test_fresh_install_writes_all_local_files(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    code, out = run_setup(repo)
    assert code == 0, out
    assert (repo / "schemas" / "skill.schema.json").is_file()
    assert (repo / "scripts" / "validate_skill_frontmatter.py").is_file()
    assert (repo / "scripts" / "check_skill_version_bump.py").is_file()
    hook = repo / ".githooks" / "pre-commit"
    assert hook.is_file()
    hook_text = hook.read_text(encoding="utf-8")
    assert "skill-lint-setup pre-commit gate" in hook_text
    assert "check_skill_version_bump.py --staged" in hook_text
    # CI must stay opt-in: no workflow without --ci
    assert not (repo / ".github" / "workflows" / "skill-lint.yml").exists()
    # hooksPath wired
    got = subprocess.run(
        ["git", "-C", str(repo), "config", "--get", "core.hooksPath"],
        capture_output=True, text=True, check=True,
    )
    assert got.stdout.strip() == ".githooks"


def test_rerun_is_idempotent(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    run_setup(repo)
    code, out = run_setup(repo)
    assert code == 0, out
    assert "[SKIP]" in out
    assert "already up to date" in out or "already wired" in out


def test_foreign_pre_commit_is_not_clobbered(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    hook_dir = repo / ".githooks"
    hook_dir.mkdir()
    hook = hook_dir / "pre-commit"
    hook.write_text("#!/bin/sh\necho existing hook\n", encoding="utf-8")
    code, out = run_setup(repo)
    assert code == 1, out
    assert "[WARN]" in out and "chain it" in out
    assert "check_skill_version_bump" in out  # both checks named for chaining
    assert hook.read_text(encoding="utf-8") == "#!/bin/sh\necho existing hook\n"


def test_half_wired_hook_warns_instead_of_claiming_done(tmp_path: Path) -> None:
    # An older bundle's hook carries the marker but only runs the validator.
    # Re-running the installer must surface the missing bump line (exit 1),
    # never report "already wired" for a gate that is only half there.
    repo = make_repo(tmp_path)
    run_setup(repo)
    hook = repo / ".githooks" / "pre-commit"
    hook.write_text(
        "#!/bin/sh\n# skill-lint-setup pre-commit gate (older bundle)\n"
        'exec python3 scripts/validate_skill_frontmatter.py\n',
        encoding="utf-8",
    )
    code, out = run_setup(repo)
    assert code == 1, out
    assert "[WARN]" in out and "half-wired" in out
    assert "check_skill_version_bump" in out
    # not overwritten without --force
    assert "older bundle" in hook.read_text(encoding="utf-8")
    # --force upgrades it to both checks, still acknowledged with a WARN
    code2, out2 = run_setup(repo, "--force")
    assert code2 == 1, out2
    upgraded = hook.read_text(encoding="utf-8")
    assert "check_skill_version_bump.py --staged" in upgraded


def test_existing_non_default_hooks_path_not_clobbered(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    subprocess.run(
        ["git", "-C", str(repo), "config", "core.hooksPath", "githooks-legacy"],
        check=True, capture_output=True,
    )
    code, out = run_setup(repo)
    assert code == 1, out
    assert "not changed" in out
    got = subprocess.run(
        ["git", "-C", str(repo), "config", "--get", "core.hooksPath"],
        capture_output=True, text=True, check=True,
    )
    assert got.stdout.strip() == "githooks-legacy"


def test_ci_flag_writes_workflow(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    code, out = run_setup(repo, "--ci")
    assert code == 0, out
    wf = repo / ".github" / "workflows" / "skill-lint.yml"
    assert wf.is_file()
    text = wf.read_text(encoding="utf-8")
    # opt-in default: manual trigger only, push/PR commented out
    assert "workflow_dispatch:" in text
    assert "\n  # push:" in text


def test_ci_workflow_not_overwritten_without_force(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    wf = repo / ".github" / "workflows" / "skill-lint.yml"
    wf.parent.mkdir(parents=True)
    wf.write_text("# custom\n", encoding="utf-8")
    code, out = run_setup(repo, "--ci")
    assert code == 0, out
    assert "different content" in out
    assert wf.read_text(encoding="utf-8") == "# custom\n"


def test_dry_run_writes_nothing(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    code, out = run_setup(repo, "--dry-run", "--ci")
    assert code == 0, out
    assert "would" in out
    assert not (repo / "schemas").exists()
    assert not (repo / ".githooks").exists()
    assert not (repo / ".github").exists()


def test_non_git_repo_warns_and_skips_hooks_config(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, git=False)
    code, out = run_setup(repo)
    assert code == 1, out
    assert "not a git repository" in out
    assert (repo / "schemas" / "skill.schema.json").is_file()


def test_existing_taskfile_snippet_reported_not_injected(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "Taskfile.yml").write_text(
        "version: '3'\ntasks:\n  lint:\n    cmds:\n      - echo hi\n",
        encoding="utf-8",
    )
    code, out = run_setup(repo)
    assert code == 0, out
    assert "lint:skills" in out
    text = (repo / "Taskfile.yml").read_text(encoding="utf-8")
    assert "lint:skills" not in text  # agent wires Taskfile edits, not the script


def test_conflicting_lint_skills_task_warns_instead_of_skipping(tmp_path: Path) -> None:
    # Finding 4: a lint:skills task that does NOT run the validator is a
    # silent-success trap - the installer must flag it, not report done.
    repo = make_repo(tmp_path)
    (repo / "Taskfile.yml").write_text(
        "version: '3'\ntasks:\n  lint:skills:\n    cmds:\n      - echo not-a-validator\n",
        encoding="utf-8",
    )
    code, out = run_setup(repo)
    assert code == 1, out
    assert "[WARN]" in out
    assert "does NOT run" in out
    assert "validate_skill_frontmatter" in out  # fix snippet included
    text = (repo / "Taskfile.yml").read_text(encoding="utf-8")
    assert "echo not-a-validator" in text  # never rewritten


def test_matching_lint_skills_task_skips_cleanly(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "Taskfile.yml").write_text(
        "version: '3'\ntasks:\n  lint:skills:\n"
        "    cmds:\n      - python3 scripts/validate_skill_frontmatter.py\n"
        "      - python3 scripts/check_skill_version_bump.py\n",
        encoding="utf-8",
    )
    code, out = run_setup(repo)
    assert code == 0, out
    assert "running both checks" in out


def test_validator_only_task_warns_as_half_wired(tmp_path: Path) -> None:
    # Regression: an older install wired only the validator. The version-bump
    # rule would be silently unchecked - the installer must say so (exit 1),
    # not report done.
    repo = make_repo(tmp_path)
    (repo / "Taskfile.yml").write_text(
        "version: '3'\ntasks:\n  lint:skills:\n"
        "    cmds:\n      - python3 scripts/validate_skill_frontmatter.py\n",
        encoding="utf-8",
    )
    code, out = run_setup(repo)
    assert code == 1, out
    assert "[WARN]" in out
    assert "NOT" in out and "check_skill_version_bump" in out
    assert "check_skill_version_bump.py" in out  # fix snippet included
    # never rewritten by the script
    text = (repo / "Taskfile.yml").read_text(encoding="utf-8")
    assert "check_skill_version_bump" not in text


def test_force_warns_when_replacing_foreign_pre_commit(tmp_path: Path) -> None:
    # Finding 5: --force must acknowledge destruction of foreign content.
    repo = make_repo(tmp_path)
    hook_dir = repo / ".githooks"
    hook_dir.mkdir()
    hook = hook_dir / "pre-commit"
    hook.write_text("#!/bin/sh\necho my-custom-hook\n", encoding="utf-8")
    code, out = run_setup(repo, "--force")
    assert code == 1, out
    assert "not authored by skill-lint-setup" in out
    assert "[WARN]" in out
    assert "skill-lint-setup pre-commit gate" in hook.read_text(encoding="utf-8")


def test_force_warns_when_replacing_modified_validator(tmp_path: Path) -> None:
    # Finding 5, second half: a locally edited validator is acknowledged too.
    repo = make_repo(tmp_path)
    dest = repo / "scripts" / "validate_skill_frontmatter.py"
    run_setup(repo)
    # Local edit that keeps the skill's marker line: must warn as 'differs'.
    dest.write_text(dest.read_text(encoding="utf-8") + "\n# my local tweak\n",
                    encoding="utf-8")
    code, out = run_setup(repo, "--force")
    assert code == 1, out
    assert "differs from the bundled copy" in out
    assert "installed by skill-lint-setup" in dest.read_text(encoding="utf-8")
    assert "# my local tweak" not in dest.read_text(encoding="utf-8")


def test_force_on_up_to_date_files_is_silent(tmp_path: Path) -> None:
    # Re-running --force on a pristine install must not cry wolf.
    repo = make_repo(tmp_path)
    run_setup(repo)
    code, out = run_setup(repo, "--force")
    assert code == 0, out
    assert "[WARN]" not in out


def test_installed_validator_blocks_real_commit(tmp_path: Path) -> None:
    # End-to-end: the installed gate must block a >1024-char description in a
    # real git commit, then pass once fixed (audit's core-promise probe).
    repo = make_repo(tmp_path)
    run_setup(repo)
    skill_dir = repo / "skills" / "demo-skill"
    skill_dir.mkdir(parents=True, exist_ok=True)
    bad = (
        "---\n"
        "name: demo-skill\n"
        f'description: {"x" * 1100}\n'
        "metadata:\n  version: 1.0.0\n"
        "---\n# demo-skill\n"
    )
    skill = skill_dir / "SKILL.md"
    skill.write_text(bad, encoding="utf-8")
    subprocess.run(
        ["git", "-C", str(repo), "add", "-A"], check=True, capture_output=True
    )
    commit = subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
         "commit", "-q", "-m", "bad"],
        capture_output=True, text=True,
    )
    assert commit.returncode == 1, commit.stdout + commit.stderr
    assert "max 1024" in commit.stdout + commit.stderr
    skill.write_text(bad.replace("x" * 1100, "x" * 200), encoding="utf-8")
    subprocess.run(
        ["git", "-C", str(repo), "add", "-A"], check=True, capture_output=True
    )
    commit2 = subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
         "commit", "-q", "-m", "good"],
        capture_output=True, text=True,
    )
    assert commit2.returncode == 0, commit2.stdout + commit2.stderr
