# Eval Report — `machina-authoring` (waza)

> Generated: 2026-09-08 (v3 fixture round) · Suite: `evals/machina-authoring/` (project mode, root-level) ·
> Engine: `copilot-sdk` (BYOK `opencode-go.local`, model `mimo-v2.5`) · Executor recon: `waza` 07-Sep-26 build.

## Status

waza is the **official eval approach** for this repo. The legacy dual-loop artifacts
(`skills/machina-authoring/evals/*.json`, `activation-matrix.md`) were removed; the suite now lives
at repo root `evals/machina-authoring/`. The fixture `machina-order.json` is a **genuine v3.0.0**
machine — declared `spec_version`, `tools` registry (with machine-relative `cmd`), `limits`,
per-state `checks[]`/`invariants[]`, per-transition `requires[]`/`ensures[]`/`else_target`,
scenario `inputs` — scoring **100.0 Excellent** on all 24 checks (22 weighted; `spec-version` and
`tools-exist` are weight-0 informational review checks). A deliberately legacy `legacy-order.json`
(score **67.2 Needs work**) drives the explain-low-score case. Both numbers reflect the v3 scorer
after `checkers-used` (weight 15) was added; earlier revisions of this report recorded 100.0/75.6
under the 23-check model.

## How to reproduce

```powershell
# wiring / fixture sanity (no model calls) — set config.executor: mock OR use a mock-flavored copy
waza run evals/machina-authoring/eval.yaml --context-dir evals/machina-authoring/fixtures -o evals/machina-authoring/results/mock-v3.json

# production (executor in eval.yaml is copilot-sdk)
$env:COPILOT_PROVIDER_BASE_URL="https://opencode-go.local/v1"; $env:COPILOT_PROVIDER_TYPE="openai"
$env:COPILOT_PROVIDER_API_KEY=$env:OPENCODE_API_KEY_WORK
waza run evals/machina-authoring/eval.yaml --context-dir evals/machina-authoring/fixtures --model mimo-v2.5 --parallel -o evals/machina-authoring/results/copilot-sdk-v3-final.json

# re-grade a saved run against current graders (no model calls)
waza grade evals/machina-authoring/eval.yaml --results results/copilot-sdk-retry.json -o results/copilot-sdk-retry.graded.json
```

## Final results (v3-surface round, 7/7 tasks, copilot-sdk)

| Task | Result | Note |
|---|---|---|
| case-01 generate machine | ✅ 1.00 | Fenced JSON, spec_version, scenarios, initial, compare/lt retry guard |
| case-02 explain low score | ✅ 1.00 | `legacy-order.json` (67.2), names actions-used/state-naming, auto vs review |
| case-03 validate/score workflow | ✅ 1.00 | Bundled script path, `validate`, `--text`, Excellent target, code block |
| case-04 add retry guard | ✅ 1.00 | compare/lt guard + context counter; emitted machine validates |
| case-05 fix validation errors | ✅ 1.00 | initial + dangling target fixed; machine validates structurally |
| case-06 negative (simulator UI) | ✅ 1.00 | All negative graders pass; stays on UI, no machina-authoring leak |
| case-07 author v3 features | ✅ 1.00 | Emits tools `/` limits `/` checks `/` requires-ensures `/` scenario inputs; validates |

**Summary (final):** **7/7 succeeded · aggregate score 1.00 · 0 skill failures** (duration ~10m
on the parallel run). One caveat: case-06 hit the known engine `session.idle` timeout at 600 s in
the same run (exit 2, empty output — a tool-heavy-session flake, not skill behavior); a targeted
re-run passed in 509 s. case-07 also failed its *first* attempt (agent burned turns globbing for
non-existent reference files in the isolated waza workspace — prompt was reference-file-dependent);
after making the prompt self-contained it passes (first-pass + retry both). Trigger accuracy:
77.8% (TP 8, FP 2, FN 2, TN 6) — consistent with the known 72–89% noise band; FP/FN sets vary
every run.

## Run 2026-09-22 (compliance-boundary round)

Environment: `waza` 0.38.7 · Copilot CLI 1.0.87 (`COPILOT_CLI_PATH` → WindowsApps exe) ·
`copilot-sdk` / `mimo-v2.5` (from `eval.yaml`) · sequential · duration **16m46s** · stdout-only
(no `-o` results file written).

| Signal | Result |
|---|---|
| Tasks | ✅ **7/7 passed · aggregate 1.00 · stddev 0.0000** (all tasks avg=1.00) |
| Trigger accuracy | ⚠️ **88.9%** (TP 8, FP 0, FN 2, TN 8) — below the 90% threshold → exit 1 |
| `waza quality` | ✅ **4.6/5** — completeness/trigger_precision/scope_coverage 5; clarity/anti-patterns 4 (density, repetition of declaration-sound vs runtime-sound, limited error-recovery guidance) |
| `waza check` | ✅ spec 9/9 · token budget **3682/4000** after fixing `.waza.yaml` schema (`tokens.limits.max` is invalid in 0.38.7 → converted to `tokens.limits.defaults` glob map) |
| Unit tests | ✅ 57 passed (`python3 -m pytest skills/machina-authoring/tests/`) |
| Links | ⚠️ 4 "escape skill directory" warnings — all targets resolve; workspace-idiomatic cross-refs (1 pre-existing in SKILL.md, 3 from new `checker-scripts.md`), accepted |

Interpretation: behavioral results are unchanged from the prior round (7/7 · 1.00); trigger
accuracy **improved** from 77.8% → 88.9% (FP 0 this run) and stays inside the documented
72–89% noise band, so the exit-1 threshold trip is noise, not a regression. Quality feedback
flags the expanded SKILL.md density as the main cost of the compliance-boundary additions.

Mutation note (recurred): the case-06 agent again wrote into the **real repo** during the run —
`copilot-extensions/machina-simulator/simulator/app.html` + `simulator/docs/architecture.md`
(23:31) and the published `%USERPROFILE%\.copilot\extensions\machina-simulator\test\qa-handlers.mjs`
(23:37, v2→v3 test expectations). All three were restored after the run (repo via `git checkout --`,
live copy re-synced from the tracked repo file; hash-verified). Skill sources were untouched
(mtimes predate the run).

### Prior-run learnings (2026-09-08, pre-v3)

- **case-02** originally timed out under the stale scoring story; the grader also required the
  literal substring `auto gap`. Calibrated to the skill's own glossary (`auto`/`review` gap
  labels) → re-graded **1.00** via `waza grade` with no extra model spend.
- **case-06** repeatedly scored **1.00 on all negative graders**; failures (when any) were engine
  `session.idle` timeouts on tool-heavy sessions, not skill behavior. Squashed by raising
  `timeout_seconds` to 600.
- **case-05** once failed when the model asked the user to paste the machine instead of reading the
  attached fixture. The prompt now explicitly says the file is attached → passes.

## Fixture state (spec 3.0.0, genuine v3 surface)

- `fixtures/machina-order.json` — canonical, fully conformant v3.0.0, **genuinely exercising the v3
  schema surface**: declared `spec_version`; a `tools` registry with four machine-relative `cmd`s
  (`payment-gateway-check`, `inventory-hold`, `shipping-label-ready`, `refund-eligible`); `limits`
  (max_events 40 / max_steps 12 / timeout 1800s); per-state `checks[]` (payment-failed) and
  `invariants[]` (paid); per-transition `requires[]`/`ensures[]`/`else_target` on the retry and
  refund transitions; scenario `inputs`; plus kebab-case states, inline `compare` guard +
  `increment` action, `coverage`, and `cycle_prevention`. `validate` → OK; `score --spec 3.0.0` →
  **Score: 100.0 / Excellent**, no gaps (Tools & execution 25/25 — its `checks[]`/`requires[]`
  references resolve to the fixture's real scripts, so `checkers-used` passes).
- `fixtures/scripts/` — the four read-only checker scripts referenced by the fixture's `tools`
  registry (`check_payment.py`, `check_inventory.py`, `check_label.py`, `check_refund.py`), so the
  canonical fixture is honest: its declared `cmd`s genuinely resolve and the `tools-exist` check
  passes (scripts exit 0 on a valid arg / 2 on usage).
- `fixtures/legacy-order.json` — v2-era reduction (snake_case keys, no spec_version, no inline
  guard/action, no coverage/cycle_prevention, one state without description). `validate` → OK;
  `score --spec 3.0.0` → **67.2 / Needs work** with gaps: state-descriptions, actions-used,
  state-naming, cycle-guards, spec-version, coverage-present, checkers-used. Used by case-02.
- `fixtures/broken-machine.json` — structurally invalid (initial + dangling target) for case-05.
- `fixtures/unguarded-retry.json` — RETRY_PAY loop without guard for case-04.

## Validator vs tool scripts — the compliance boundary

| Layer | Runs at | What it verifies | Executes scripts? |
|---|---|---|---|
| **Compliance scorer / `machine-validator.py`** | Authoring time (static, deterministic) | The machine **declaration** is schema-sound: `tools` entries exist + have `cmd`; `checks[]`/`requires[]`/`ensures[]` reference registry names; `else_target` resolves; inputs/limits well-formed; **`checkers-used`** (weight 15) requires one usable checker declared in a driver-executed slot; **`tools-exist`** stats each tool's machine-relative `cmd` path (weight-0, informational). | **Never** |
| **Tool checker scripts (`fixtures/scripts/*.py`)** | Runtime (driving / simulation) | The **behavioral predicate** actually holds (payment authorized, inventory held, label ready, refund eligible). Exit code + optional stdout JSON gate transitions. | (they are the executable) |

Consequence: **"Score 100 / Excellent" = declaration-sound, not runtime-sound.** The scorer never
runs a declared tool. The **`checkers-used`** check (weight 15, `since 3.0.0`) is what weights
evidence: it requires one checker referenced from a driver-executed slot (`checks[]`/`requires[]`)
whose `cmd` names a script by path, expects exit 0, and — when the machine file is scored from disk —
resolves beside the machine. The **`tools-exist`** check (weight 0, `autofill: review`, `warn`) stays
the per-tool detail line: with a resolvable machine dir it stats each machine-relative `cmd` (string
or array form) and reports a review finding for missing files without lowering the score, skips
pathless commands, and passes trivially when no base dir is available (in-memory unit tests, waza
temp-workspace graded files, `machine-driver.py` calls). `machina-driving` documents the same boundary
(Dependency + Trust boundary sections) and gates only on
`run_compliance(...)["blocking"]`; runtime soundness is established by actually executing the
tools.

## Deterministic program grader (`graders/machina_check.py`)

Extracts a fenced `json` block (or bare JSON) from agent output and runs the skill's bundled
`machine-validator.py validate` (structural gate) + `score --text`; exit 0 only when structurally
valid (optional `--min-score` / `--require-golden ≥90`). **Hardened:** when `WAZA_WORKSPACE_DIR` is
unset (standalone runs), the machine is written to an OS temp file (previously it fell back to CWD
and could drop `graded-machine.json` into the repo root). The temp file is removed on exit.

## Findings & recommendations for the skill

1. **Core authoring behaviors are strong.** Generation, validate/score guidance, retry-guard
   hardening, validation repair, and the negative boundary all score 1.00; emitted machines pass the
   deterministic validator.
2. **Domain-boundary routing is good but trigger accuracy is noisy.** Measured activation ranges
   ~72–89% run-to-run. Revisit the `description` trigger phrases (esp. "score Excellent", guard
   syntax) only if routing becomes a problem; the static 18-prompt test set is small, so treat a
   single run's FP/FN set as indicative, not decisive.
3. **Eval-harness side effect (important):** during copilot-sdk runs, the simulator-UI negative case
   (case-06) agent can write into the **real repo** (it modified
   `copilot-extensions/machina-simulator/simulator/app.html` twice; one run also touched
   `machine-validator.py`). Restore those files after any eval run
   (`git checkout -- <path>`), or run waza from a clean clone/scratch checkout.

## Suite artifacts

- `eval.yaml` — `trigger_accuracy` ≥ 0.9 @ 30wt; executor `copilot-sdk`, model `mimo-v2.5`;
  `timeout_seconds: 600`; task glob `tasks/*.yaml`; `skill_directories: ../../skills/machina-authoring`.
- `tasks/case-01…case-07.yaml` — 6 positive + 1 negative content-boundary case (case-07:
  author-with-v3-features — tests the skill can produce tools/limits/checks/requires/ensures/
  scenario-inputs machines).
- `trigger_tests.yaml` — 10 positive + 8 negative prompts (ported from the removed `activation-matrix.md`).
- `graders/machina_check.py` — deterministic program grader (see above).
- Results — `mock-v3.json` (7-task wiring), `copilot-sdk-v3-final.json` (7/7, final), and the
  targeted flake retries `copilot-sdk-case06-retry.json` / `copilot-sdk-case07-retry.json` (both
  pass; archived as evidence of the engine-timeout / prompt-dependency fixes).
- Removed (legacy) — `skills/machina-authoring/evals/*.json`, `skills/machina-authoring/activation-matrix.md`.

## Known limitations

- Program grader gates on **structural validation** (validate exit code), not a ≥90 score gate —
  the Excellent target is an authoring goal, not a correctness gate for one-shot generated machines.
- **`tools-exist` is informational and `checkers-used` is declaration-level**: `checkers-used` (weight
  15) makes a v3 machine with no usable checker unable to reach Excellent, and it closes the
  "declared tool points at a missing file" false-positive for `machina-driving` — but neither check
  executes a script, so a present-but-broken script still only fails at runtime. Runtime soundness
  remains the driver's job by design.
- `waza run --executor` is not a flag in this binary; executor comes from `eval.yaml config.executor`.
  `--model` overrides the BYOK model at runtime. Mock runs require flipping `config.executor` to `mock`
  (this repo keeps the committed default `copilot-sdk`).
- Trigger accuracy is inherently noisy on an 18-prompt set; the 90% metric threshold should be read
  as a trend signal, not a strict gate.