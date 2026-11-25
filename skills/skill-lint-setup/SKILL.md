---
name: skill-lint-setup
description: >-
  Standardize skill-frontmatter validation as local CI in any repo containing
  Copilot skills: install a JSON Schema (SKILL.md description 10-1024 chars,
  kebab name, metadata.version), a stdlib-only validator, a .githooks/pre-commit
  gate, and a Taskfile lint task; GitHub Actions stays opt-in and disabled by
  default, and Copilot hooks are never used. USE FOR: (1) bootstrapping the
  skill-lint gate into a fresh repo in one command; (2) wiring the same gate
  into an existing repo that already has .githooks, core.hooksPath, a pre-commit
  hook, or a Taskfile - chain what exists, never clobber it; (3) opting into the
  cloud workflow later with --ci. DO NOT USE FOR: authoring or improving skill
  content itself (use skill-creator), a one-off description length check (run
  scripts/validate_skill_frontmatter.py directly), or any Copilot hook/postToolUse
  automation (out of scope by design).
metadata:
  version: 0.1.0
  status: candidate
---

# Skill lint setup

Install one standard validation flow for `SKILL.md` frontmatter — local-first:
schema + validator + git hook + Taskfile task. Cloud CI is an opt-in extra,
never the default gate.

## What gets installed

| File | Role |
|---|---|
| `schemas/skill.schema.json` | Canonical rules: description 10–1024 chars, kebab `name` ≤64, required `metadata.version` |
| `scripts/validate_skill_frontmatter.py` | Stdlib-only validator (no PyYAML/jsonschema); exit 0 green, 1 violations, 2 config error |
| `.githooks/pre-commit` | Runs the validator on every commit |
| `core.hooksPath=.githooks` | Activates the hook (only when unset or already `.githooks`) |
| `Taskfile.yml` → `lint:skills` | Reported snippet for the agent to wire; the script never edits Taskfile.yml |
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
git config --get core.hooksPath                 # expect .githooks
```

Flags: `--dry-run` reports without writing; `--force` overwrites (and warns
first whenever the file being replaced was not authored by this skill or was
locally edited); `--ci` adds the opt-in workflow; exit code 1 means one or more
`[WARN]`/`[FAIL]` lines need attention.

## Wire an existing repo

The installer refuses to clobber existing wiring. When it exits 1, resolve each
warning yourself:

- **Existing `.githooks/pre-commit`**: insert one line **immediately after its
  shebang** (first check to run, so a fast fail beats slower existing checks,
  and no later `set -e`/`exit` can skip it) —
  `python3 scripts/validate_skill_frontmatter.py || exit 1`.
- **`core.hooksPath` set to another directory**: leave it; call the validator
  from a hook inside that directory.
- **`Taskfile.yml` already defines `lint:skills`** but it does not run the
  validator: the installer exits 1 with the snippet — reconcile by hand so the
  task cannot silently validate nothing.
- **No `.git`**: copy the files only; wire hooks when the repo is initialized.

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
- Validator and repo disagree on a rule — the schema is the source of truth;
  edit `schemas/skill.schema.json`, not the validator.
