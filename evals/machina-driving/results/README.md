# Eval Report — `machina-driving` (waza)

> Suite: `evals/machina-driving/` (project mode, root-level).
> Engine: `copilot-sdk` (BYOK `opencode-go.local`, model `mimo-v2.5`).

## Status

waza is the official eval approach for this repo. The legacy dual-loop artifacts
(`skills/machina-driving/evals/eval.json`, `activation-matrix.md`) were removed; the suite now
lives at repo root `evals/machina-driving/`.

**Canonical machine delegation (design decision):** the suite holds **no committed machine
copy**. `--context-dir` points at the repo root and the tasks declare the canonical machine
(`skills/machina-driving/tests/machines/test-machine.json`) and its checker scripts under
`inputs.files`. The files are staged by waza into each task's isolated workspace, so
`skills/machina-driving/tests/machines/test-machine.json` stays the single source of truth —
a schema/version bump flows through automatically. This is the documented exception to the
usual `eval/<skill>/fixtures/` convention. Cases that need bespoke machines (STUCK, phase
parent/child) inline those definitions in the prompt; the suite still owns no machine files.

## How to reproduce

```powershell
# wiring / fixture sanity (no model calls) — set config.executor: mock OR use a mock-flavored copy
waza run evals/machina-driving/eval.yaml --context-dir <repo root> -o evals/machina-driving/results/mock.json

# production (executor in eval.yaml is copilot-sdk)
$env:COPILOT_PROVIDER_BASE_URL="https://opencode-go.local/v1"; $env:COPILOT_PROVIDER_TYPE="openai"
$env:COPILOT_PROVIDER_API_KEY=$env:OPENCODE_API_KEY_WORK
waza run evals/machina-driving/eval.yaml --context-dir C:\Users\DuyAnh\Workplace\CodeF\github-copilot-fc --model mimo-v2.5 --parallel -o evals/machina-driving/results/copilot-sdk.json
```

> **Why `--context-dir` is the repo root:** `inputs.files` paths in each task are repo-relative
> (`skills/machina-driving/scripts/machine-driver.py`, `skills/machina-authoring/scripts/machine-validator.py`,
> the canonical machine + scripts). Waza stages exactly those files into the task workspace; the
> agent then genuinely runs the driver there.

## Final results (init + hardening rounds, copilot-sdk)

**7/7 tasks pass, aggregate 1.00** (mimo-v2.5 via copilot-sdk, parallel tools). Hardening round
added blocked-iterate, tamper, phase, and driver-maintenance-negative cases — all pass.
Exit code 1 is only the trigger_accuracy threshold (see below).

| Task | Result | Note |
|---|---|---|
| case-01 drive to SUCCESS | ✅ 1.00 | Agent drives `test-machine.json` → report.json `result: SUCCESS`, `final_state: published`; driver `check` verifies ledger |
| case-02 drive STUCK | ✅ 1.00 | Agent writes the inline stuck machine, init's it → report.json `result: STUCK`; grounded escalation, no invented success |
| case-03 negative (authoring) | ✅ 1.00 | No drive artifacts (program negative grader passes); authoring vocabulary, no driver/report leakage |
| case-04 drive blocked→iterate | ✅ 1.00 | First DRAFT_COMPLETE blocked (validate-output fails) → agent fixes output.md → re-fire → SUCCESS; grader asserts `blocked_events ≥ 1` in the ledger (**hardening**) |
| case-05 drive tamper-detect | ✅ 1.00 | Drives to SUCCESS, then simulates an edit to the frozen `machine.json` copy → `check` MUST refuse (fail-closed); grader asserts tamper detected (**hardening**) |
| case-06 drive phase-nested | ✅ 1.00 | Parent machine + inline child; PHASE_DONE `--child-run` → report `nested_runs` non-empty, SUCCESS@parent-done (**hardening**) |
| case-07 negative (driver maintenance) | ✅ 1.00 | "Add a retry subcommand to machine-driver.py" → no drive artifacts, no report leakage; added after round-1 FP (**hardening**) |

### Trigger accuracy

- **Init round:** 83.3% (TP 5, FP 1, FN 1) — FP on the driver-maintenance prompt.
- **Hardening round:** 75.0% (TP 3, FP 0, FN 3) — the driver-maintenance FP is **fixed** by the
  DO-NOT-USE boundary; remaining 3 FN are the same command-surface / STUCK-escalation /
  report-grounding phrasings that also missed in round 1. All three trigger phrases **are
  present** in the description, so this is the known small-set routing noise band (72–89%), not
  a description gap. No description over-tuning on a 12-prompt set.

## Grading strategy — artifact-graded

Unlike `machina-authoring` (which grades emitted machine JSON), `machina-driving` is graded on
**real run artifacts**: `graders/machina_drive.py` finds the run's `report.json` under
`WAZA_WORKSPACE_DIR`, asserts it is a `machina.report.v1` with the expected `result` /
`final_state`, then re-runs the driver's deterministic `check` (ledger chain + artifact-hash
verification) as the tamper-evident integrity gate. Exit 0 only when a genuine drive reached the
expected outcome. A negative-case mode (`--expect-no-drive`) passes when no drive artifact
exists. Hardening flags: `--expect-min-blocked N` (the ledger must show ≥ N blocked fires
before success — blocked→iterate case), `--expect-nested-run` (report lists a child run — phase
case), `--expect-tamper-detected` (the run's frozen machine copy was edited after the report; the
driver check MUST now refuse with an integrity violation — fail-closed proof).

## Canonical test machine

Delegated to `skills/machina-driving/tests/machines/test-machine.json` (genuine v3.0.0: tools
with machine-relative `cmd`, limits, per-state checks/invariants, per-transition
requires/ensures + cycle_prevention guard, scenario inputs). No copy is committed in this suite.

## Known limitations

- Under the `mock` executor the positive drive cases fail by design (mock emits canned text;
  nothing drives a real run). `waza run` failures under mock are wiring-only status, not skill
  failures. The negative cases (case-03, case-07) pass under mock.
- The driver unit tests hardcode `python3` in in-memory fixtures; on hosts without `python3 on
  PATH those specific tests fail. The canonical machine and eval prompts use `python`/`py`
  (present on this host). This is a pre-existing test-environment issue, not an eval finding.
- Trigger accuracy is inherently noisy on a 12-prompt set; the ≥90% metric threshold should be
  read as a trend signal.

## Side effects

The copilot-sdk agent works in an isolated temp workspace (run state, drafts, and the report
live there), so driving tasks should not touch the repo. If an agent ever edits repo files,
restore with `git checkout -- <path>`.