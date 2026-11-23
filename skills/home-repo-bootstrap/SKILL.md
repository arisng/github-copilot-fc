---
name: home-repo-bootstrap
description: "Bootstrap and verify a personal home repo (the Home Repo pattern) on a new developer machine or teammate laptop — seed AGENTS.md repo pointers, shared docs, the daily-report tower manifest, scripts/local-ci.ps1 and the pre-commit gate, then prove the clone passes its own CI. USE FOR: 'bootstrap home repo', 'set up my home repo', 'new machine setup', 'onboard a teammate to home-repo', 'clone the tower from scratch', 'seed AGENTS.md pointers', 'verify my home repo', 'home repo isn't passing local CI'. DO NOT USE FOR: generating a daily report (use daily-report), promoting a repo-level skill into the shared factory (use join-copilot-fc), or general git worktree and commit work (use git-worktree-generic and git-atomic-commit)."
user-invocable: true
metadata:
  version: 0.1.0
  author: arisng
  status: candidate
---

# Home Repo Bootstrap

A **home repo** is one repository that holds shared steering, shared docs, and a pointer to
every other repo a developer works in; agent sessions start there. It is private and
per-developer. This skill creates that repository from nothing on a new machine, or repairs
one whose layout drifted, and then proves the result passes the repository's own gate.

The skill is the **only** distribution path for the home-repo skeleton. It never copies an
existing home repo between machines: every developer seeds their own, then owns the result.

## What gets seeded

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Steering: how to work from here, one pointer bullet per repo, skills rules |
| `docs/coding-standards.md` | Shared commit, CI, writing, and secrets conventions |
| `docs/glossary.md` | Standing cross-repo vocabulary |
| `reports/daily/` | The daily-report tower's output folder |
| `reports/daily/daily-report.manifest.json` | Per-machine watched-repo list (gitignored) |
| `scripts/local-ci.ps1` | The whole CI: pointer validation plus report validation |
| `.githooks/pre-commit` | Wires `local-ci.ps1 -Staged` into every commit |
| `.gitignore` | Keeps the manifest and exported transcripts out of git |

## Prerequisites

- `git` on PATH.
- PowerShell 7+ (`pwsh`) for the seeded CI and the verification script. The seeded
  pre-commit hook **skips cleanly** when `pwsh` is missing, so a machine without it is
  never bricked — it just has no gate until `pwsh` is installed.
- The `daily-report` shared skill, installed before the first report commit
  (`npx skills add arisng/github-copilot-fc -s daily-report -g -y`). Bootstrapping does not
  require it: the seeded CI resolves the report validator only when a report is staged.

## Procedure

Run **seed -> verify -> commit -> report**, and stop at the first failed step.

### 1. Seed

Ask only for what cannot be derived. Resolve the rest from the machine:

| Input | Default when omitted |
| --- | --- |
| Target folder | Ask. Never overwrite an unrelated directory. |
| Git user name for reports | `git config --global user.name`, else the OS user name |
| Pointer entries | One labelled placeholder bullet (the seed still passes CI) |
| Watched repos | None — the manifest stays in `single` mode |

```powershell
pwsh -NoProfile -File scripts/Initialize-HomeRepo.ps1 `
  -Path 'C:\Work\home-repo' `
  -Repo 'copilot-fc|C:\Work\Agents\github-copilot-fc|https://github.com/arisng/github-copilot-fc.git' `
  -WatchedRepo 'C:\Work\Agents\github-copilot-fc' `
  -RemoteUrl 'https://github.com/<you>/home-repo.git'
```

Rules the script enforces, and why:

- **Seed, never sync.** An existing file is left byte-intact and listed under `skipped`.
  `-Force` re-seeds deliberately. Do not reach for `-Force` to "update" a teammate's copy —
  after the first run the home repo owns every seeded file, and updates travel as ordinary
  commits or pull requests.
- **Pointer paths must be absolute and space-free.** `scripts/local-ci.ps1` extracts pointer
  paths as whitespace-terminated tokens, so a path with a space silently truncates.
- **Every pointer needs both halves** — an absolute path *and* a well-formed `Clone from`
  URL. Local CI fails a bullet missing either, because "clone if missing" needs the URL.
- **`core.hooksPath` is set to `.githooks`.** A seeded hook that is never wired is dead
  weight. Never repoint it to another directory.
- **The manifest is per machine and gitignored.** It is the one file allowed to hold
  absolute paths. `-WatchedRepo` switches it to `multi` mode (the tower mode of the
  `daily-report` skill); without it the repo reports on itself only.

### 2. Verify

```powershell
pwsh -NoProfile -File scripts/Test-HomeRepoBootstrap.ps1 -Path 'C:\Work\home-repo'
```

It emits JSON with `passed`, `checks[]`, and `warnings[]`, and exits non-zero when a check
fails. The checks are layout, git wiring, manifest shape, pointer shape, the local CI run,
and shared-skill presence. Only `skills` may report `warn` on a fresh machine — install the
named skill and re-run rather than treating it as a bootstrap failure.

`-SkipGate` omits the CI run when `pwsh` is unavailable, but then the hook cannot run
either; say so instead of claiming the gate is green.

### 3. Commit

The seeded gate is the acceptance test. Stage everything the initializer reported under
`created`, then commit with the home repo's conventional-commit style:

```bash
git -C <path> add -A
git -C <path> commit -m "chore(workspace): bootstrap home repo"
```

A pre-commit failure names the file and the rule. Fix the file — do not bypass the hook with
`--no-verify`; the same rule would fail on the next machine.

### 4. Report and hand off

Tell the developer, in one short block:

- the path seeded, and which files were created versus skipped;
- the manifest mode (`single` or `multi`) and the watched repos;
- the remaining manual step when a placeholder pointer was written — replace it with real
  `name: path. Clone from url if missing.` bullets and re-run the gate;
- the shared skills to install (`npx skills add arisng/github-copilot-fc -s <name> -g -y`).

Never claim success from the initializer's output alone. Success means
`Test-HomeRepoBootstrap.ps1` returned `passed: true`.

## Adding a repo pointer later

Append one bullet under `## Other Repos` in `AGENTS.md`:

```text
- <name>: <absolute path>. Clone from <clone-url> if missing.
```

Keep wrapped bullets indented; local CI joins continuation lines before parsing. Add the new
path to the manifest `repos` list (and set `mode` to `multi`) when the tower should report on
it. Re-run both scripts; the pointer check warns, but does not fail, for a path absent on
this machine.

## Teammate onboarding

The same three commands work on every machine, and each run is independent:

```powershell
npx skills add arisng/github-copilot-fc -g -y                     # shared skills, incl. this one
pwsh -NoProfile -File scripts/Initialize-HomeRepo.ps1 -Path <target>
pwsh -NoProfile -File scripts/Test-HomeRepoBootstrap.ps1 -Path <target>
```

Pointers are the only machine-specific content in a committed file, and CI tolerates a
missing path, so one shared `AGENTS.md` stays valid across machines. Machine-specific paths
belong in the gitignored manifest.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `pointer bullet has no local path` | The bullet lacks an absolute Windows path; local CI matches a drive-letter path only. |
| `pointer bullet has no 'Clone from' URL` | Add `Clone from <url> if missing.` to the same bullet. |
| `malformed clone URL` | Use `https://`, `git@`, `ssh://`, or `git://`. |
| `pointer paths absent on this machine` (WARN) | Expected on another machine; clone the repo if the work needs it. |
| `core.hooksPath is ''` | Run `git config core.hooksPath .githooks`; `/verify` reports this as a failure. |
| `daily-report skill is missing` | A report is staged but the validator is absent: install the skill or set `DAILY_REPORT_SKILL_DIR`. |
| `pwsh not found` | Install PowerShell 7+. The hook skips rather than failing, so the gate is simply inactive. |

## Files

- `scripts/Initialize-HomeRepo.ps1` — seeds a home repo, wires hooks, writes the manifest.
- `scripts/Test-HomeRepoBootstrap.ps1` — the acceptance check; prints JSON, exits non-zero on failure.
- `assets/` — the seeded content: `AGENTS.md.template`, `coding-standards.md`,
  `glossary.md`, `local-ci.ps1`, `pre-commit.template`, `gitignore.template`.
- `references/design-notes.md` — why the skeleton has this shape, and how it evolved.
- `tests/` — Pester suites for both scripts.
