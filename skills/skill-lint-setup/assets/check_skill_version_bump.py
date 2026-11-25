#!/usr/bin/env python3
"""Enforce a metadata.version bump whenever files under skills/<name>/ change.

Stateless sibling of validate_frontmatter.py; both are installed into
scripts/. Standardized local gate installed by skill-lint-setup: the
validator checks what a skill SAYS; this gate checks that a changed skill's
version MOVED. Stdlib + git only; version extraction reuses the sibling
validator's frontmatter parser so the repo keeps exactly one YAML reader for
SKILL.md.

Modes:
  (default)   working tree vs HEAD: staged + unstaged + untracked changes.
              Wired into `task lint:skills` for feedback before the commit.
  --staged    git index vs HEAD: exactly what the next commit records.
              Wired into .githooks/pre-commit.
  --base REF  HEAD vs merge-base(REF, HEAD): a committed range.
              Wired into the opt-in cloud workflow (PR base / push before).

Rules (baseline = the comparison ref's skills/<name>/SKILL.md):
  - any changed path under skills/<name>/ counts as a skill change; only
    first-level children of skills/ are skills, so skills/README.md and
    skills/.archived/** never require a bump (same skill set the validator
    globs: skills/*/SKILL.md)
  - new skill (no baseline SKILL.md): green - the schema governs its version
  - removed SKILL.md: green - nothing left to version
  - a renamed directory is remove + add (old green, new green); bump manually
    if you track version continuity across renames
  - otherwise metadata.version must differ from the baseline and, when both
    sides parse as semver, must not be LOWER (downgrades fail; a changed
    build-metadata suffix still counts as changed)

Exit codes: 0 green or skipped (non-git, no baseline commit, no skill
changes), 1 violations, 2 config error (bad --base ref, missing sibling
validator).
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path

SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$"
)


def _sibling_validator():
    """Load the bundled frontmatter parser sitting next to this script."""
    here = Path(__file__).resolve().parent
    for name in ("validate_skill_frontmatter", "validate_frontmatter"):
        path = here / f"{name}.py"
        if not path.is_file():
            continue
        spec = importlib.util.spec_from_file_location(f"_{name}_for_bump", path)
        if spec is None or spec.loader is None:
            continue
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        if hasattr(mod, "split_frontmatter") and hasattr(mod, "parse_frontmatter"):
            return mod
    return None


def _version_of(mod, text: str) -> tuple[str | None, str | None]:
    """Extract metadata.version from SKILL.md text.

    Returns (version, None) on success, (None, reason) when unreadable.
    Falls back to the legacy top-level `version` key so baselines written
    before metadata.version was required still order against current files.
    """
    try:
        fm = mod.split_frontmatter(text)
        if fm is None:
            return None, "missing or unterminated YAML frontmatter"
        data = mod.parse_frontmatter(fm)
    except Exception as exc:  # parser raises FrontmatterError(ValueError)
        return None, str(exc)
    if not isinstance(data, dict):
        return None, "frontmatter is not a mapping"
    meta = data.get("metadata")
    if isinstance(meta, dict) and isinstance(meta.get("version"), str):
        return meta["version"], None
    if isinstance(data.get("version"), str):
        return data["version"], None
    return None, "metadata.version missing"


def _semver_cmp(new: str, old: str) -> int | None:
    """Semver precedence of new vs old: 1 greater, -1 lower, 0 equal.

    Build metadata is ignored; prereleases order below their release.
    Returns None when either side is not semver (caller falls back to
    string inequality - format validity itself belongs to the validator).
    """
    mn, mo = SEMVER_RE.match(new), SEMVER_RE.match(old)
    if mn is None or mo is None:
        return None
    cn = tuple(int(mn.group(i)) for i in (1, 2, 3))
    co = tuple(int(mo.group(i)) for i in (1, 2, 3))
    if cn != co:
        return 1 if cn > co else -1
    pn, po = mn.group(4), mo.group(4)
    if pn is None and po is None:
        return 0
    if pn is None:
        return 1  # release outranks any of its prereleases
    if po is None:
        return -1
    in_, io = pn.split("."), po.split(".")
    for a, b in zip(in_, io):
        if a == b:
            continue
        an, bn = a.isdigit(), b.isdigit()
        if an and bn:
            return 1 if int(a) > int(b) else -1
        if an != bn:
            return -1 if an else 1  # numeric identifiers order below alpha
        return 1 if a > b else -1
    if len(in_) != len(io):
        return 1 if len(in_) > len(io) else -1  # more fields outrank a prefix
    return 0


def _suggest(old: str) -> str | None:
    """Concrete next version (patch+1) for the failure message, when parseable."""
    m = SEMVER_RE.match(old)
    if m is None:
        return None
    return f"{m.group(1)}.{m.group(2)}.{int(m.group(3)) + 1}"


def _git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parents[1]),
        help="directory to look for a git repository in "
        "(default: parent of scripts/)",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--staged", action="store_true",
        help="compare the git index against HEAD (pre-commit)",
    )
    group.add_argument(
        "--base", metavar="REF",
        help="compare HEAD against merge-base(REF, HEAD) (CI range)",
    )
    args = parser.parse_args(argv)

    mod = _sibling_validator()
    if mod is None:
        print(
            "[FAIL] sibling validator not found next to this script "
            "(re-run scripts/setup_skill_lint.py)"
        )
        return 2

    root = Path(args.root).resolve()
    if shutil.which("git") is None:
        print("[SKIP] git not found - version-bump check inert "
              "(frontmatter gate still applies)")
        return 0
    top_r = _git(root, "rev-parse", "--show-toplevel")
    if top_r.returncode != 0:
        print(f"[SKIP] {root} is not a git repository - version-bump check inert")
        return 0
    top = Path(top_r.stdout.strip())

    head = _git(top, "rev-parse", "--verify", "--quiet", "HEAD")
    old_ref: str | None = "HEAD"
    if args.base:
        if head.returncode != 0:
            print(f"[FAIL] --base {args.base} needs an existing HEAD commit")
            return 2
        if _git(top, "rev-parse", "--verify", "--quiet",
                f"{args.base}^{{commit}}").returncode != 0:
            print(f"[FAIL] --base {args.base} is not a resolvable commit")
            return 2
        mb_r = _git(top, "merge-base", args.base, "HEAD")
        if mb_r.returncode != 0:
            print(f"[FAIL] --base {args.base}: merge-base failed: "
                  f"{mb_r.stderr.strip()}")
            return 2
        old_ref = mb_r.stdout.strip()
    elif head.returncode != 0:
        print("[SKIP] no baseline commit yet - the first commit needs no bump")
        return 0

    if args.staged:
        label = "staged vs HEAD"
        diff_r = _git(top, "diff", "--cached", "--name-only", "--no-renames")
        paths = diff_r.stdout.splitlines() if diff_r.returncode == 0 else None
    elif args.base:
        label = f"HEAD vs {args.base}"
        diff_r = _git(top, "diff", "--name-only", "--no-renames",
                      old_ref, "HEAD")
        paths = diff_r.stdout.splitlines() if diff_r.returncode == 0 else None
    else:
        label = "working tree vs HEAD"
        diff_r = _git(top, "diff", "--name-only", "--no-renames", "HEAD")
        if diff_r.returncode != 0:
            paths = None
        else:
            paths = diff_r.stdout.splitlines()
            paths += _git(
                top, "ls-files", "--others", "--exclude-standard"
            ).stdout.splitlines()
    if paths is None:
        print(f"[FAIL] git diff failed: {diff_r.stderr.strip()}")
        return 2

    skills: dict[str, None] = {}
    for path in paths:
        parts = path.split("/")
        if len(parts) >= 3 and parts[0] == "skills":
            skills.setdefault(parts[1], None)
    if not skills:
        print(f"[SKIP] no skill files changed ({label})")
        print("check_skill_version_bump: green")
        return 0

    def blob(revspec: str) -> str | None:
        r = _git(top, "show", revspec)
        # utf-8-sig parity with the validator's read_text(encoding="utf-8-sig"):
        # a BOM'd SKILL.md must parse identically from git as from disk.
        return r.stdout.lstrip("\ufeff") if r.returncode == 0 else None

    def read_disk(rel: str) -> str | None:
        try:
            return (top / rel).read_text(encoding="utf-8-sig")
        except OSError:
            return None

    if args.staged:
        get_new = lambda rel: blob(f":{rel}")  # noqa: E731 - index content
    elif args.base:
        get_new = lambda rel: blob(f"HEAD:{rel}")  # noqa: E731
    else:
        get_new = read_disk

    failures = 0
    examined = 0
    for name in skills:
        sk = f"skills/{name}/SKILL.md"
        old_txt = blob(f"{old_ref}:{sk}")
        new_txt = get_new(sk)
        if old_txt is None and new_txt is None:
            continue  # container/non-skill dir: no SKILL.md, like the validator's glob
        examined += 1  # a real skill row (live or being removed)
        if new_txt is None:
            print(f"[SKIP] {sk}: removed - nothing to bump")
            continue
        new_v, new_err = _version_of(mod, new_txt)
        if new_v is None:
            print(
                f"[FAIL] {sk}: cannot read metadata.version in the current "
                f"file ({new_err}) - run "
                "scripts/validate_skill_frontmatter.py for the frontmatter error"
            )
            failures += 1
            continue
        if old_txt is None:
            print(f"[PASS] {sk}: new skill (version {new_v})")
            continue
        old_v, _ = _version_of(mod, old_txt)
        if old_v is None:
            print(
                f"[SKIP] {sk}: baseline has no metadata.version "
                "(pre-adoption history) - bump not enforced yet"
            )
            continue
        if new_v != old_v:
            cmp = _semver_cmp(new_v, old_v)
            if cmp is not None and cmp < 0:
                print(
                    f"[FAIL] {sk}: metadata.version went backwards "
                    f"({old_v} -> {new_v}) - versions must increase"
                )
                failures += 1
            else:
                print(f"[PASS] {sk}: {old_v} -> {new_v}")
            continue
        # Changed skill, identical version: the forgotten bump.
        msg = (
            f"[FAIL] {sk}: files changed but metadata.version is still "
            f"{old_v} ({label}) - bump metadata.version in {sk}"
        )
        hint = _suggest(old_v)
        if hint:
            msg += f" (e.g. {hint})"
        if args.staged:
            disk_txt = read_disk(sk)
            if disk_txt is not None:
                disk_v, _ = _version_of(mod, disk_txt)
                if disk_v and disk_v != new_v:
                    msg += (f"; working tree already has {disk_v} - "
                            f"stage it: git add {sk}")
        print(msg)
        failures += 1

    if failures:
        print(
            f"check_skill_version_bump: {failures} bump violation(s) "
            f"across {examined} changed skill(s) ({label})"
        )
        return 1
    if examined == 0:
        # Candidates existed (skills/.archived/**, skills/<container>/) but no
        # live skills/*/SKILL.md changed - same green as no candidates at all.
        print(f"[SKIP] no skill files changed ({label})")
        print("check_skill_version_bump: green")
        return 0
    print(
        f"check_skill_version_bump: {examined} changed skill(s) green "
        f"({label})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
