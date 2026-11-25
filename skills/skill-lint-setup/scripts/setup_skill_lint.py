#!/usr/bin/env python3
"""Install the skill-lint standard into a target repository (idempotent).

What gets installed:
  schemas/skill.schema.json             - canonical frontmatter schema (10-1024 desc)
  scripts/validate_skill_frontmatter.py - stdlib-only validator
  scripts/check_skill_version_bump.py   - stdlib+git gate: changed skill must bump metadata.version
  .githooks/pre-commit                  - local gate running both checks
  .github/workflows/skill-lint.yml      - ONLY with --ci (opt-in; manual trigger)

Behavior:
  - Skips any file that already exists (prints SKIP); --force overwrites.
  - Never clobbers a foreign pre-commit hook: reports it so the agent can chain.
  - A hook/task wired to the validator only is reported: the version-bump line
    is part of the standard, and a half-wired gate must not read as done.
  - Sets core.hooksPath=.githooks only when unset or already .githooks; a
    different existing value is reported, never changed.
  - Cloud CI is opt-in: without --ci nothing under .github/workflows is touched.

Usage:
  python3 scripts/setup_skill_lint.py [--repo PATH] [--ci] [--force] [--dry-run]
Exit codes: 0 success, 1 completed with warnings needing agent attention
 (including [FAIL] on bad arguments).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
ASSETS = SKILL_DIR / "assets"
HOOK_MARKER = "skill-lint-setup pre-commit gate"
TASK_SNIPPET = """  # >>> skill-lint-setup >>>
  lint:skills:
    desc: Validate skills/*/SKILL.md frontmatter (10-1024 chars) and version bumps
    cmds:
      - python3 scripts/validate_skill_frontmatter.py
      - python3 scripts/check_skill_version_bump.py
  # <<< skill-lint-setup <<<
"""

warnings: list[str] = []


def note(msg: str) -> None:
    print(f"[OK]   {msg}")


def skip(msg: str) -> None:
    print(f"[SKIP] {msg}")


def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"[WARN] {msg}")


def install_file(
    src: Path, dest: Path, *, force: bool, dry_run: bool, marker: str | None = None
) -> None:
    rel = dest.name
    if dest.exists():
        same = dest.read_bytes() == src.read_bytes()
        if not force:
            if same:
                skip(f"{rel} already up to date")
            else:
                skip(f"{rel} exists with different content (use --force to overwrite)")
            return
        if not same:
            # --force must acknowledge what it destroys, never silently.
            text = dest.read_text(encoding="utf-8", errors="replace")
            if marker is not None and marker not in text:
                warn(
                    f"{rel} exists but was not authored by skill-lint-setup; "
                    f"--force is replacing it"
                )
            else:
                warn(
                    f"{rel} differs from the bundled copy (local edits or an "
                    f"older bundle); --force is replacing it"
                )
    if dry_run:
        note(f"would write {dest}")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    note(f"wrote {dest}")


def wire_pre_commit(repo: Path, *, force: bool, dry_run: bool) -> None:
    hook = repo / ".githooks" / "pre-commit"
    if hook.exists() and not force:
        text = hook.read_text(encoding="utf-8", errors="replace")
        if HOOK_MARKER in text:
            if "check_skill_version_bump" in text:
                skip(".githooks/pre-commit already wired")
            else:
                warn(
                    ".githooks/pre-commit runs the validator but not "
                    "scripts/check_skill_version_bump.py - half-wired gate. "
                    "Review it, then re-run with --force to upgrade it (or "
                    "append: exec python3 scripts/check_skill_version_bump.py "
                    "--staged)"
                )
            return
        warn(
            f".githooks/pre-commit exists but is not from this skill; chain it "
            f"manually: call `python3 scripts/validate_skill_frontmatter.py` "
            f"then `python3 scripts/check_skill_version_bump.py --staged` from "
            f"that hook (see SKILL.md, 'Wire an existing repo')."
        )
        return
    install_file(
        ASSETS / "pre-commit", hook,
        force=force, dry_run=dry_run, marker=HOOK_MARKER,
    )
    if not dry_run and hook.exists():
        hook.chmod(0o755)


def wire_hooks_path(repo: Path, *, dry_run: bool) -> None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "config", "--get", "core.hooksPath"],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        warn("git not found on PATH; set core.hooksPath=.githooks manually")
        return
    current = result.stdout.strip()
    if result.returncode != 0 or not current:
        if dry_run:
            note("would run: git config core.hooksPath .githooks")
            return
        subprocess.run(
            ["git", "-C", str(repo), "config", "core.hooksPath", ".githooks"],
            check=True,
        )
        note("core.hooksPath -> .githooks")
    elif current == ".githooks":
        skip("core.hooksPath already .githooks")
    else:
        warn(
            f"core.hooksPath is {current!r}; not changed. Point the existing hook "
            f"directory at scripts/validate_skill_frontmatter.py and "
            f"scripts/check_skill_version_bump.py instead "
            f"(see SKILL.md, 'Wire an existing repo')."
        )


def wire_taskfile(repo: Path) -> None:
    taskfile = repo / "Taskfile.yml"
    if not taskfile.exists():
        skip("no Taskfile.yml; run the validator directly or add a task later")
        return
    text = taskfile.read_text(encoding="utf-8", errors="replace")
    if "lint:skills" in text:
        has_validator = "validate_skill_frontmatter" in text
        has_bump = "check_skill_version_bump" in text
        if has_validator and has_bump:
            skip("Taskfile.yml already defines lint:skills running both checks")
            return
        if has_validator and not has_bump:
            warn(
                "Taskfile.yml defines lint:skills running the validator but NOT "
                "scripts/check_skill_version_bump.py - the version-bump rule is "
                "unchecked. Reconcile it manually with this snippet:\n"
                + TASK_SNIPPET
            )
            return
        warn(
            "Taskfile.yml defines lint:skills but it does NOT run "
            "scripts/validate_skill_frontmatter.py - the gate task is a "
            "no-op. Reconcile it manually with this snippet:\n" + TASK_SNIPPET
        )
        return
    print(
        "[INFO] Add this task under `tasks:` in Taskfile.yml "
        "(agent: wire it if the repo keeps its lint entry points there):\n"
        + TASK_SNIPPET
    )


def wire_ci(repo: Path, *, ci: bool, force: bool, dry_run: bool) -> None:
    if not ci:
        skip("cloud CI not requested (opt-in; rerun with --ci to add the workflow)")
        return
    install_file(
        ASSETS / "github-skill-lint.yml",
        repo / ".github" / "workflows" / "skill-lint.yml",
        force=force, dry_run=dry_run,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo", default=".",
        help="target repository root (default: current directory)",
    )
    parser.add_argument(
        "--ci", action="store_true",
        help="also write .github/workflows/skill-lint.yml (opt-in; manual trigger)",
    )
    parser.add_argument("--force", action="store_true", help="overwrite existing files")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    args = parser.parse_args(argv)

    repo = Path(args.repo).resolve()
    if not repo.is_dir():
        print(f"[FAIL] --repo {repo} is not a directory")
        return 1
    is_git = (repo / ".git").exists()
    if not is_git:
        warn(f"{repo} is not a git repository; hooks wiring will be skipped")

    print(f"Installing skill-lint standard into {repo}"
          + (" (dry run)" if args.dry_run else ""))
    install_file(ASSETS / "skill.schema.json",
                 repo / "schemas" / "skill.schema.json",
                 force=args.force, dry_run=args.dry_run,
                 marker="github-copilot-fc/schemas/skill.schema.json")
    install_file(ASSETS / "validate_frontmatter.py",
                 repo / "scripts" / "validate_skill_frontmatter.py",
                 force=args.force, dry_run=args.dry_run,
                 marker="installed by skill-lint-setup")
    install_file(ASSETS / "check_skill_version_bump.py",
                 repo / "scripts" / "check_skill_version_bump.py",
                 force=args.force, dry_run=args.dry_run,
                 marker="installed by skill-lint-setup")
    wire_pre_commit(repo, force=args.force, dry_run=args.dry_run)
    if is_git:
        wire_hooks_path(repo, dry_run=args.dry_run)
    wire_taskfile(repo)
    wire_ci(repo, ci=args.ci, force=args.force, dry_run=args.dry_run)

    if warnings:
        print(f"\nsetup_skill_lint: done with {len(warnings)} warning(s) - "
              "resolve each [WARN] above")
        return 1
    print("\nsetup_skill_lint: done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
