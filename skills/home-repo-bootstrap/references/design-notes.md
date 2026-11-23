# Design notes

Why the bootstrap skeleton has this shape, and which trade-offs were deliberate. Read this
before changing a seeded file or the initializer's defaults.

## The three-layer split

| Layer | Owns | Lives in |
| --- | --- | --- |
| Steering | how to work from here, which repos exist, skills rules | `AGENTS.md` |
| Policy docs | commit, CI, writing, secrets conventions; vocabulary | `docs/` |
| Enforcement | the only gate: pointer validation plus report validation | `scripts/local-ci.ps1` + `.githooks/pre-commit` |

A rule stated in `AGENTS.md` prose without a matching check rots. The pointer rules
(absolute path plus clone URL) exist in both layers on purpose: the prose tells a human what
to write, and the gate refuses anything else, so the convention cannot drift.

## Seed, never sync

The initializer writes a file only when it is absent. An update path was rejected for three
reasons:

1. Teams edit the seeded files immediately — pointers, standards, glossary terms. A sync
   would either clobber those edits or need conflict resolution in a script.
2. Promoting a change to every teammate is already solved by git: commit it in one home repo
   and let people pull, or open a pull request against a shared home repo.
3. Silent rewrites are unrecoverable in the one place that matters: a run that "updates" a
   teammate's `AGENTS.md` destroys content no backup holds.

`-Force` exists for the narrow case where the developer deliberately wants a pristine copy
of one file, and it is documented as deliberate rather than routine.

## Why pointer paths may not contain spaces

`local-ci.ps1` extracts pointer paths with a whitespace-terminated regex
(`(?:[A-Za-z]:[\\/]|/)[^\s]+` — drive-letter or POSIX absolute), because the same parser must
handle wrapped bullets that prose wraps arbitrarily. Allowing spaces would require quoting
syntax the parser cannot infer. The initializer therefore rejects a spaced path at seed time —
a loud failure and an immediate explanation is better than a pointer that truncates silently
on the next machine.

The lookbehind in that pattern excludes `:` and `/`, so a clone URL's `//host/path` is never
read as a local pointer path. Both behaviours are pinned by tests.

## Why the validator resolves lazily

A fresh home repo has no reports. Requiring the `daily-report` skill at bootstrap would add a
network install to a step that otherwise needs only `git` and PowerShell. The gate therefore
resolves `Test-DailyReport.ps1` only after it finds a staged or tracked report; with no
targets it prints `PASS (no report or glossary changes)`.

The trade-off is that a missing skill is not caught at bootstrap. The verification script
covers that with its `skills` check, which warns (never fails) on a fresh machine, and the
missing-skill path inside the gate itself fails loudly when a report *is* staged, so a report
can never be committed unvalidated.

## Why `core.hooksPath` is set by the initializer

The upstream home repo wires hooks with a manual one-time `git config`. That step is
forgotten on exactly the machines this skill targets. Setting it during seed makes the gate
live from the first commit; the verification script reports `core.hooksPath is ''` as a
failure because a seeded-but-unwired hook is dead weight.

## Why the fallback pointer exists

Local CI fails a repository with zero pointer bullets, because a home repo with no pointers
is not doing its job. A brand-new machine often has no cloned repos yet. The placeholder
bullet keeps the first commit green while remaining obviously unfinished: it is labelled
`Placeholder repo (replace with your own pointer)` and the verification output repeats that
instruction in `nextSteps`.

## Powershell-portability constraints the seeded scripts honour

The seeded CI is copied into every home repo, so it must satisfy the factory's own
PowerShell lint and the portability rules it enforces:

- `pwsh` PowerShell 7+ only; no Windows PowerShell 5.1 features.
- No command-position `.exe` invocations (`git`, not `git.exe`) so Linux and macOS hosts work.
- `$env:TEMP` never appears; nothing depends on a Windows-only temp variable.
- The pre-commit hook is `/bin/sh` and skips cleanly when `pwsh` is missing, so a clone on a
  machine without PowerShell is never bricked.
- The seeded script resolves its repository from `$PSScriptRoot` rather than the caller's
  working directory. Earlier drafts used `git rev-parse` from the current directory and
  validated the wrong repository whenever the gate was run from elsewhere; the Pester suite
  now covers that regression.

## Adding a new seeded file

1. Put the content in `assets/` (templates end in `.template` when they carry `{{TOKEN}}`
   placeholders).
2. Add it to the `required` asset list and the `Write-Seed` calls in
   `scripts/Initialize-HomeRepo.ps1`.
3. Add the path to the `required` layout list in `scripts/Test-HomeRepoBootstrap.ps1`.
4. Extend `tests/Initialize-HomeRepo.Tests.ps1` so the new file is asserted, and add a
   go-through case in `tests/Test-HomeRepoBootstrap.Tests.ps1`.

Both scripts are the contract; a seeded file that no script knows about drifts immediately.
