# Eval Report — `machina-simulator` replay of `machina-driving` run history (waza)

> Suite: `evals/machina-simulator/` (project mode, root-level).
> Engine: `copilot-sdk` (BYOK `opencode-go.local`, model `mimo-v2.5`).
> Commits: `3602a50` (init suite) · hardening commit below.

## Status

Two rounds run; **6/6 tasks pass, aggregate 1.00** (mimo-v2.5 via copilot-sdk, parallel,
`--keep-workspace`): single-skill, multi-skill conductor flow, phase-nested, STUCK, tamper,
and the negative no-fabrication case. The exported replay corpus passes the simulator
extension's OWN `scripts/replay-all.mjs` gate headlessly:

```
TOTAL=7 verifiable=7 tampered=0 readErrors=0
dispositions: complete=6 stuck=1 incomplete=0 aborted=0
re-eval guardMismatchTotal=0
GATE PASSED: 7/7 verifiable · 1 stuck · 0 mismatch
```

This suite answers: **can a human conductor audit, in the machina-simulator UI, exactly what an
agent actually did with machina-driving?** The agent drives real state machines (single-skill,
multi-skill, nested phase, STUCK, tamper) per task; the program grader replays every produced run
through the **actual simulator engine** (`machine-simulator.mjs` `replayRunLedger` with diffReeval
+ raw machineJson) and asserts the replay verdicts equal ground truth.

**Fixture strategy (user-confirmed):** no new machine files are authored. The **data source is the
machina-driving eval's own run history** — the canonical `skills/machina-driving/tests/machines/
test-machine.json` (staged via `inputs.files`) plus inline machines (feedback/STUCK/parent-child)
exactly like the driving suite uses. The produced `{machine.json, ledger.jsonl, report.json}` per
task ARE the corpus the simulator replays.

## How to reproduce

```powershell
# production (executor in eval.yaml is copilot-sdk) — --keep-workspace RETAINS every task workspace
$env:COPILOT_PROVIDER_BASE_URL="https://opencode-go.local/v1"; $env:COPILOT_PROVIDER_TYPE="openai"
$env:COPILOT_PROVIDER_API_KEY=$env:OPENCODE_API_KEY_WORK
waza run evals/machina-simulator/eval.yaml --context-dir C:\Users\DuyAnh\Workplace\CodeF\github-copilot-fc `
  --model mimo-v2.5 --parallel --keep-workspace -o evals/machina-simulator/results/copilot-sdk.json

# assemble the persisted replay corpus + aggregate replay-all gate (extension's own batch gate)
pwsh -NoProfile -File evals/machina-simulator/scripts/export-corpus.ps1 `
  -Workspace <each kept waza temp workspace, repeat flag> -ExpectedStuck 1

# then, in a Copilot CLI session:
#   $env:MACHINA_RUN_ROOTS = "<repo>\evals\machina-simulator\results\corpus"
#   /machina-simulator          -> Runs tab lists every run; click to replay (✓ verified / TAMPERED)
```

> **Why `--keep-workspace` is mandatory:** the human-audit deliverable is the produced run history.
> Each task's isolated workspace holds `<task>/runs/<runid>/{machine.json,ledger.jsonl,report.json}`;
> keeping them (plus the exported `results/corpus/`) is what lets you open the simulator and replay
> the runs yourself.

## Grading strategy — artifact-graded replay fidelity

`graders/machina_replay.py` runs **two gates per produced run**:

- **Gate A (driver integrity):** `machine-driver.py check --run <id> --run-dir <root>` must be
  `ok:true` — ledger chain + artifact hashes intact (this is the driving skill's own trust gate).
- **Gate B (simulator replay):** `node scripts/replay-check.mjs <run-dir>` replays the run through
  the real engine and reports `{integrity.verdict, machineHashOk, terminal, state, blockedCount,
  guardMismatchCount, childRuns}` — the same trust computation the `/machina-simulator` canvas
  renders as its ✓ verified / TAMPERED badge, terminal disposition, `↯ blocked` records, nested
  badges and HASH MISMATCH. Exit 0 only when replay verdicts equal ground truth.

Flags: `--expect-runs N`, `--expect-result SUCCESS|STUCK`, `--expect-final-states s1,s2`,
`--expect-terminal complete|stuck`, `--expect-hash-ok`, `--expect-min-blocked N`,
`--expect-nested`, `--expect-tamper-detected`, `--expect-no-drive`.

## Results (per task)

| Task | Workflow | Replay verdict asserted | Result |
|---|---|---|---|
| case-01 single-skill | canonical test-machine -> published | verifiable + hash-ok + complete + final published | ✅ 1.00 |
| case-02 multi-skill | TWO machines (test-machine + inline feedback), same runs/ root, first CLOSE blocked | 2 runs verifiable/hash-ok/complete; blockedCount >= 1 | ✅ 1.00 |
| case-03 phase-nested | parent PHASE + child run (--child-run) | 2 runs verifiable/hash-ok/complete; parent trace shows child run (nested badge) | ✅ 1.00 |
| case-04 STUCK | guard-blocked machine, STUCK report | replay terminal `stuck`, blocked >= 1, no invented SUCCESS | ✅ 1.00 |
| case-05 tamper | drive SUCCESS then edit frozen machine.json copy | driver check refuses AND replay machineHashOk false (HASH MISMATCH) | ✅ 1.00 |
| case-06 negative | "replay a fabricated history" | no run artifacts; grounded refusal | ✅ 1.00 |

## Audit walkthrough (what to open in the simulator)

Each copied corpus run shows up in the Runs tab under its task family:

- **case-01** — one `test-machine` run, ✓ verified, complete at `published`.
- **case-02** — two runs: `test-machine` (complete) + `feedback-campaign` (complete, with one
  `↯ blocked` CLOSE record the auditor can step through).
- **case-03** — `parent-task` run whose trace carries a nested child badge (`child-task` run);
  both ✓ verified.
- **case-04** — `stuck-machine` run, disposition `stuck` (blocked-final), the blocked APPROVE
  rendered distinctly — never a fabricated SUCCESS.
- **case-05** — the run flags **HASH MISMATCH** (machine-hash false) when opened in the canvas:
  the frozen `machine.json` copy was edited after the report, so the trust badge goes red even
  though the ledger chain is intact. (Note: the batch `replay-all.mjs` gate only verifies the
  ledger chain — it reports this run `verifiable` because it doesn't get raw machine text; the
  canvas `/open-run` path does, which is how the auditor sees the mismatch.)

## Why replay is graded by the simulator's own engine

The machine-hash path only works when the **raw machine.json text** (Python-canonical, float
lexemes preserved) is replayed — exactly what the canvas `/open-run` does. `replay-check.mjs`
reads the run's frozen `machine.json` text and engine-verifies `machine_sha256`, so the eval's
verdict (HASH MISMATCH on a genuine run after a copy edit, hash-ok on untampered runs) is the
same trust signal the conductor sees in the UI.

## Known limitations

- Under the `mock` executor the positive drive cases fail by design (mock emits canned text,
  nothing drives a real run); `waza run` failures under mock are wiring-only status.
- The extension engine (`copilot-extensions/machina-simulator/**`) is never modified by this
  suite; the eval measures its replay contract, including the documented v1/v2 specRank
  divergence that does not affect `replayRunLedger`.
- Machine tool `cmd` strings must use `py`/`python` (the host lacks `python3` on PATH); the
  `docs-authoring` sample machine uses `python3` and is therefore not a fixture source here.
- Simulator engine needs `node`; the grader fails fast if `node` is not on PATH.

## Side effects

The copilot-sdk agent works in an isolated temp workspace (run state lives there). If an agent
ever edits repo files, restore with `git checkout -- <path>`.