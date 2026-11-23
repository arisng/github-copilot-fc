# Coding Standards

Conventions observed across this tower and the repos it points at; extend it as patterns
firm up. Cross-repo vocabulary lives in [glossary.md](./glossary.md).

## Commits

- Conventional commits with a real scope: `type(scope): summary` (types in use include
  `chore`, `report`, `agent`, `docs`, `build`).
- Atomic: one reviewed intent per commit, in build-safe order, with the staged set verified
  before committing.
- Session hygiene: when the worktree carries unrelated dirty files, commit only files with
  evidence of belonging to the current session.

## CI and reports

- `scripts/local-ci.ps1`, run by the pre-commit hook, is the whole pipeline — there is no
  cloud CI. Its pwsh-missing skip must keep working so a plain clone is never bricked.
- A daily report commits only with a complete coverage receipt
  (`sessions/<yymmdd>/coverage.json`), and staged bytes must equal working-tree bytes for
  anything the validator read.

## Writing (docs, skills, agent-facing text)

- Plain, unambiguous English: a reader without human context must not be able to misparse it.
- Skill frontmatter contract: `name` (lowercase, matches the directory name) and
  `description` (at most 1024 characters, stating what the skill does **and** when to use it).
- Define cross-repo terms once in `docs/glossary.md` instead of re-explaining them per file.

## Secrets and machine state

- Never commit secrets; `.env` and similar files stay unread and untracked.
- Absolute machine paths belong in the gitignored daily-report manifest. The one documented
  exception is `AGENTS.md` pointers.

## Skills

- One-owner rule: every skill has exactly one source of truth — an updater or a git repo — and
  is never copied to a second location.
