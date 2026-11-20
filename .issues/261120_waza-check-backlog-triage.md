---
date: 2026-11-20
type: Task
severity: Low
status: Open
---

# Task: triage the waza check advisory backlog

## Context

`waza check` is wired into the full gate as an **advisory** check: exit 2
(known pre-existing backlog) is reported as WARN and never blocks. As of the
2026-11-19 full gate run the backlog stood at roughly 108 findings. An advisory
report nobody trims risks becoming noise that agents learn to ignore, which
degrades the value of the whole check.

Policy constraints that apply to this work:

- Structural eval validation is `waza preflight` (already wired, blocking).
- `waza run` / `waza gate` execution gating stays deferred — do not wire it.

## Tasks

- [ ] Run `waza check` and categorize the findings (description length/routing,
      token budgets, spec compliance, other).
- [ ] Rank categories by finding count and pick the cheapest first win.
- [ ] Fix the top category and confirm the gate WARN count drops.
- [ ] Re-run after each skill batch; keep the backlog shrinking (ratchet
      discipline: WARN counts may not grow).
- [ ] Once the backlog is small enough, decide whether `waza check` should
      ratchet from WARN to FAIL for new findings only.

## References

- Policy and classification: `instructions/waza-eval.instructions.md`
- Gate wiring: `scripts/workspace/workspace-check.ps1` (`Invoke-WazaCheck`)
- Command reference: `skills/waza-cli/references/waza-commands.md`
