---
name: skill-lint-setup
description: >-
  Standardize skill-frontmatter validation as local CI in any repo containing
  Copilot skills: install a JSON Schema (SKILL.md description 10-1024 chars,
  kebab name, metadata.version), a stdlib-only validator, a version-bump gate
  (skill changes must move metadata.version), a .githooks/pre-commit gate, and
  a Taskfile lint task; GitHub Actions stays opt-in and disabled by default,
  and Copilot hooks are never used. USE FOR: (1) bootstrapping the skill-lint
  gate into a fresh repo in one command; (2) wiring the same gate into an
  existing repo that already has .githooks, core.hooksPath, a pre-commit hook,
  or a Taskfile - chain what exists, never clobber it; (3) enforcing a
  metadata.version bump when files under skills/<name>/ change; (4) opting into
  the cloud workflow with --ci. DO NOT USE FOR: authoring or improving skill
  content itself (use skill-creator), a one-off description length check (run
  scripts/validate_skill_frontmatter.py directly), or any Copilot hook/postToolUse
  automation (out of scope by design).
metadata:
  version: 0.2.0
  status: candidate
---

# Skill lint setup

Install one standard validation flow for `SKILL.md` frontmatter — local-first:
schema + validator + version-bump gate + git hook + Taskfile task. Cloud CI is
an opt-in extra, never the default gate.

## What gets installed

| File | Role |
|---|---|
| `schemas/skill.schema.json` | Canonical rules: description 10–1024 chars, kebab `name` ≤64, required `metadata.version` |
| `scripts/validate_skill_frontmatter.py` | Stdlib-only validator (no PyYAML/jsonschema); exit 0 green, 1 violations, 2 config error |
| `scripts/check_skill_version_bump.py` | Stdlib+git bump gate; exit 0 green/skipped, 1 forgot-to-bump, 2 config error |
| `.githooks/pre-commit` | Runs the validator, then the bump gate, on every commit |
| `core.hooksPath=.githooks` | Activates the hook (only when unset or already `.githooks`) |
| `Taskfile.yml` → `lint:skills` | Reported snippet running both checks; the script never edits Taskfile.yml |
| `.github/workflows/skill-lint.yml` | **Only with `--ci`**: `workflow_dispatch` trigger; push/PR triggers shipped commented out |

## Bootstrap a fresh repo

Run the installer once from this skill:

```bash
python3 scripts/setup_skill_lint.py --repo /path/to/repo
```

Then verify the gate fires:

```bash
cd /path/to/repo
python3 scripts/validate_skill_frontmatter.py   # expect green
python3 scripts/check_skill_version_bump.py     # expect green
git config --get core.hooksPath                 # expect .githooks
```

Flags: `--dry-run` reports without writing; `--force` overwrites (and warns
first whenever the file being replaced was not authored by this skill or was
locally edited); `--ci` adds the opt-in workflow; exit code 1 means one or more
`[WARN]`/`[FAIL]` lines need attention.

## Version-bump enforcement

`scripts/check_skill_version_bump.py` fails any change under `skills/<name>/`
whose `metadata.version` did not move since the comparison ref. It reuses the
validator's frontmatter parser (no second YAML reader) and is stdlib + git
only. Three modes, each wired into one layer of the local flow:

| Mode | Compares | Wired into |
|---|---|---|
| `--staged` | git index vs HEAD (exactly what the commit records) | `.githooks/pre-commit` |
| (default) | working tree vs HEAD, incl. untracked files | `task lint:skills` |
| `--base REF` | HEAD vs merge-base(REF, HEAD) | opt-in cloud workflow, PR/push events |

Rules: new skill (no baseline) passes - the schema governs its version;
removed `SKILL.md` passes - nothing to bump; a rename reads as remove + add
(bump manually if you track continuity); a downgrade fails ("versions must
increase"); a changed build-metadata suffix (`1.0.0+a` -> `1.0.0+b`) counts
as changed. Non-semver baselines compare by string inequality (format is the
validator's job). Baselines without `metadata.version` (pre-adoption history)
are skipped with an explicit line until the first enforced bump.

The staged mode also detects the partial-stage trap: if the working tree
already carries the bump but the index does not, the failure message says
`stage it: git add <path>`.

## Wire an existing repo

The installer refuses to clobber existing wiring. When it exits 1, resolve each
warning yourself:

- **Existing `.githooks/pre-commit`**: insert two lines **immediately after its
  shebang** (first checks to run, so a fast fail beats slower existing checks,
  and no later `set -e`/`exit` can skip them) —
  `python3 scripts/validate_skill_frontmatter.py || exit 1` and
  `python3 scripts/check_skill_version_bump.py --staged || exit 1`.
- **`core.hooksPath` set to another directory**: leave it; call both checks
  from a hook inside that directory.
- **`Taskfile.yml` already defines `lint:skills`** but it does not run both
  checks: the installer exits 1 with the snippet — reconcile by hand so the
  task cannot silently validate nothing or leave the bump rule unchecked.
- **Hook or task wired to the validator only** (an older install of this
  standard): the installer exits 1 — review the wiring, then re-run with
  `--force` to upgrade it to both checks.
- **No `.git`**: copy the files only; wire hooks when the repo is initialized.
  The bump gate is inert without git and says so on an explicit `[SKIP]` line.

## Opt into cloud CI

Cloud CI is disabled by default — local hooks are the primary gate. When the
team wants a runner too:

```bash
python3 scripts/setup_skill_lint.py --repo /path/to/repo --ci
```

Then uncomment `push:` / `pull_request:` in
`.github/workflows/skill-lint.yml` to enforce on every change; leaving them
commented keeps it manual (`workflow_dispatch` only).

## Validate without committing

```bash
python3 scripts/validate_skill_frontmatter.py --root /path/to/repo
python3 scripts/check_skill_version_bump.py --root /path/to/repo   # vs HEAD
# or, once wired: task lint:skills
```

## Troubleshooting

- `gate is inert until a skill exists` (exit 0) — no `skills/*/SKILL.md`
  found. Intentional for the bootstrap repo shape, but note this diverges from
  the canonical github-copilot-fc gate, which FAILs an empty `skills/`; if the
  target repo renamed `skills/`, fix the path or re-run the installer.
- `schema not found` (exit 2) — re-run the installer; `schemas/skill.schema.json`
  was deleted or never installed.
- Hook never fires — check `git config --get core.hooksPath` and that
  `.githooks/pre-commit` is executable (`chmod +x`).
- `python3/python not found` at commit time — install Python 3, or bypass once
  with `git commit --no-verify` (never as the default workflow).
- `files changed but metadata.version is still X` — bump `metadata.version` in
  that skill's `SKILL.md` and stage it; if the message says `stage it: git add`,
  the bump exists only in the working tree. Amending a skill change that was
  committed without a bump counts as a change too: bump, then re-stage.
- `--base REF is not a resolvable commit` (exit 2) — the ref is misspelled or
  the checkout lacks history; the opt-in workflow sets `fetch-depth: 0` for
  exactly this reason.
- `version-bump check inert` (`[SKIP]`, exit 0) — no git repository or no
  commits yet; expected during bootstrap, and the frontmatter gate still runs.
- Validator and repo disagree on a rule — the schema is the source of truth;
  edit `schemas/skill.schema.json`, not the validator.
