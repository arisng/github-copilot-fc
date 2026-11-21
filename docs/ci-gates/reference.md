# CI Gates Reference

Two lanes gate this repository: the **local** lane (git hooks and go-task on a
developer machine) and the **cloud** lane (GitHub Actions on GitHub). Both lanes
run the same implementation, `scripts/workspace/workspace-check.ps1`, in one of
three modes. The lane decides *when* a mode runs and *what its verdict costs*;
the mode decides *which checks run*.

## Overview

| | Local lane | Cloud lane |
|---|---|---|
| Entry points | `.githooks/pre-commit`, `.githooks/pre-push`, `task lint`, `task check` | `.github/workflows/ci.yml` (runs `task check`) |
| Runs on | developer machine | `ubuntu-latest` runner |
| Enforcement | blocks the commit/push via hook exit code | posts a check run on the push/PR; `main` is not branch-protected (verified 2026-11-21), so a red run does not block by itself |
| Availability | opt-in per clone (`task hooks:install`); each hook skips cleanly when `pwsh` is missing | every push to `main` and every pull request |

The boundary in one sentence: **pre-commit ⊂ pre-push ⊂ `task check` = CI** —
each gate is a strict superset of the one before it, and the cloud lane runs
the exact command (`task check`) that defines the full local gate.

## Modes of workspace-check.ps1

| Mode | Switch | Invoked by | Checks run |
|---|---|---|---|
| Quick | `-Quick` | `task lint`, `.githooks/pre-commit` | Markdown lint, Consistency |
| Push | `-SkipAdvisoryWaza` | `.githooks/pre-push` (prints a banner first, then runs) | full suite minus advisory `waza check` |
| Full | (none) | `task check` (and `task` with no args), CI | full suite |

## Boundary matrix

| Check | pre-commit (Quick) | pre-push (Push) | `task check` / CI (Full) |
|---|---|---|---|
| Markdown lint | yes | yes | yes |
| Consistency | yes | yes | yes |
| waza check (advisory) | — | — | yes |
| Supply chain | — | yes | yes |
| Eval preflight | — | yes | yes |
| Skill tests (pytest) | — | yes | yes |
| Skill tests (Pester) | — | yes | yes |

Each check's full description lives in the `.DESCRIPTION` header of
`scripts/workspace/workspace-check.ps1` — that header and this matrix must be
updated together when a check is added, moved between modes, or retired.

## Severity semantics

- **WARN** = ratchet-pending legacy backlog; never blocks in any gate, in either
  lane. A `waza check` exit 2 is always classified WARN.
- **FAIL** = a structural rule that is green today; blocks wherever the check
  runs. `workspace-check.ps1` exits 1 on any FAIL, and the hooks propagate that
  exit code to block the commit or push.
- A check that does not run in a mode cannot block that mode (the `—` cells
  above), regardless of its result elsewhere.

## Local gates

| Gate | Trigger | Mode | Blocks |
|---|---|---|---|
| `.githooks/pre-commit` | `git commit` | Quick | the commit |
| `.githooks/pre-push` | `git push` (banner prints first) | Push | the push |
| `task lint` | manual | Quick | nothing (exit code only) |
| `task check` | manual; default task | Full | nothing (exit code only); this is also the CI command |

Hooks are wired by `core.hooksPath=.githooks`, set once per clone via
`task hooks:install`. `core.hooksPath` is never repointed.

## Cloud gate

`.github/workflows/ci.yml` triggers on pushes to `main` and on pull requests,
then runs `task check` (Full mode) after installing the toolchain: go-task,
Go + waza (pinned `v0.40.1`), Python 3.12 with `jsonschema`, `PyYAML`, and
`pytest`, and Pester. Toolchain pins in effect across both lanes:

| Tool | Pinned by |
|---|---|
| markdownlint-cli2 `0.24.2` | `workspace-check.ps1` (same pin in both lanes) |
| waza `v0.40.1` | CI install step; the local lane uses whatever version is installed (0.39.0 on the 2026-11-21 machine) |

## Coverage constraints

Facts that bound what each lane guarantees:

- A clone that never ran `task hooks:install` has no local gates; CI is then
  the only lane, and only for pushes to `main` and PRs.
- `pwsh` missing from `PATH` makes each hook skip (exit 0) rather than block.
- `git commit --no-verify` / `git push --no-verify` bypasses the local lane.
- A direct push to a non-`main` branch with no PR, from an unwired clone, runs
  no gate at all.
- CI's verdict is advisory while `main` lacks branch protection: a red run
  records a failed check but does not reject a merge or a push.

## Not gated anywhere

Deliberately unwired, by standing policy:

- `waza run` / `waza gate` (LLM execution) — deferred since 2026-10-16; see
  `instructions/waza-eval.instructions.md`.
- `waza quality` (LLM judge) — requires model execution, never wired.
- `check-supply-chain.py --strict` — warn-first today; `--strict` is the future
  ratchet target.

## Observed durations

One Windows development machine, 2026-11-21, warm caches. Informational only —
not a contract:

| Mode | Wall clock |
|---|---|
| Quick | ~7 s |
| Push | ~79 s |
| Full | ~103 s (advisory `waza check` ~25 s, pytest ~47 s, Pester ~25 s) |

## Related references

- `scripts/workspace/workspace-check.ps1` — the implementation and its check
  catalogue (`.DESCRIPTION` header).
- `.github/workflows/ci.yml` — the cloud lane definition.
- `.github/copilot-instructions.md` (Guardrails & automation) — steering pointer.
- `instructions/waza-eval.instructions.md` — why eval execution gating is deferred.
