# Glossary — Copilot CLI Sub-Session Harness Vocabulary

Canonical, self-contained definitions for the terms used in this skill's `SKILL.md` and its
empirical argument-audit harness (`tests/Invoke-CopilotCliSubSession-args-audit.ps1`). This file is
part of the skill: it travels with the skill when published (personal folder, plugin bundle, staging),
so the skill never depends on files outside its own directory.

---

## Test cases

| Term | Definition | Example |
| --- | --- | --- |
| **Test case ID** | Unique identifier for one test case in the harness. Format is `<bucket-prefix><n>[-<sub>]`. | `s3-2`, `l8`, `l8-t1`, `s5-6a` |
| **Bucket-prefix** | Leading letter of the case ID that groups cases by *mode*: `s*` = shim (hermetic, zero cost, asserted against the fake `copilot`), `l*` = live (real CLI, real keys, opt-in, tokens). | `l5` = live case #5 |
| **Sub-case suffix** | `-t<n>` appended to a case ID for a sub-call inside a multi-call case (e.g. turn 1 / turn 2 of a chained session). | `l8-t1` (luna turn), `l8-t2` (resumed flash turn) |
| **Checkpoint** | One-sentence statement of what a case asserts, registered with the case and shown in the report. | `Add-TestCase -Checkpoint 'LIVE cold-switch resume luna→flash …'` |

## Modes and isolation

| Term | Definition | Example |
| --- | --- | --- |
| **Shim** | A fake stand-in for the real `copilot` binary. The harness (`New-CopilotShim`) writes a fake `copilot.ps1` that logs the exact argv (`ARGS\|`), emitted env (`ENV\|`), and cwd (`PWD\|`) it received, then echoes `SHIM_OK`. Used to assert *what the SUT would pass to the CLI* — deterministically, zero cost, no tokens. | Shim matrix run |
| **Test double** | The general term for a fake object substituting for a real dependency; a *shim* is one kind (a script-level stub). | shim above |
| **Hermetic mode** | Test runs with no network/real-API calls; every dependency is stubbed or sentineled. Deterministic and free. | All `s*` cases |
| **Live mode** | Opt-in test runs that invoke the real CLI with real API keys and real sessions (tokens cost money). Guarded by preconditions and a cost guardrail. | `-Live` → `l*` cases |
| **Sentinel key** | A fake API-key value (`sentinel-*`) injected into child processes so the harness can assert key handling without ever touching real keys. | `KEY=sentinel-opencode-work-key` |
| **Dojo / staging home** | The durable test `COPILOT_HOME` (`~/.copilot-staging`), pre-seeded from production profiles, used as the isolated home for tests that need real profile shapes. | `-CopilotHome <dojo>` |
| **Isolation gate** | A before/after assertion that production and the dojo were not mutated by a run (SHA-256 hash of `byok-profiles.json` / `mcp-config.json` unchanged). Violation → throw. | `s8-6`, spike-gate isolation line |
| **Spike gate** | A first-run preflight that proves the harness machinery works (shim wins over real `copilot`, `RETURN\|` protocol) before any real case runs; failure → abort (exit 2). | `SHIM_NOT_WINNING` → abort |
| **COST GUARDRAIL** | Hard check in live mode that refuses to spawn non-allowlisted (expensive/fragile) models/profiles before any call is made. | `gpt-5.6-luna` was added to the allowlist for `l8` |
| **Child-env scrub** | The harness removes stale `COPILOT_HOME` / `COPILOT_PROVIDER_*` / `COPILOT_MODEL` / `COPILOT_OFFLINE` from every child process so each case asserts exactly what the SUT emits for its profile — never leaked parent-terminal env. | `$script:scrubCopilotEnv` |

## Results

| Term | Definition | Example |
| --- | --- | --- |
| **PASS** | The case's assertions all held. | `s5-6 … passed` |
| **FAIL** | At least one assertion did not hold; the run exits non-zero. | `exit 1` |
| **SKIP** | The case was not runnable (precondition missing: live not enabled, dojo missing). Counted separately, not a failure. | `l8` when `-Live` is off |
| **KNOWN-GAP** | The case documents *current SUT behavior that is known-imperfect* and passes with a gap label so the harness stays green while recording the finding. Gaps are the backlog for future fixes. | `s4-3`, `s5-4`, `s9-4`, `s11-2`, `l2` |
| **Polarity-agnostic** | A case that does **not** hard-code which outcome is correct; it records whichever occurs and passes either way, labeling the result (clean → PASS, known issue → KNOWN-GAP). Used when *characterizing unknown behavior* rather than locking a regression. | `l8` is the worked example: clean cold-switch → PASS; 400 / `reasoning_content` replay → KNOWN-GAP with evidence snippet |
| **Polarity-fixed** | A case that hard-codes the expected sign of the outcome (e.g. the 400 *must not* happen). Reserved for regression locks after root cause is confirmed. | Not yet present |
| **Exit codes** | `0` all pass (known-gap rows count as pass), `1` one or more failures, `2` harness/preflight error. | `tests:subsession-audit` → 0 |
| **Evidence** | Per-case captured artifacts (child stdout/stderr, shim log, session events) saved under the run's `evidence/` dir and linked from the report. | `evidence/l8-t1.out.txt` |
| **Run artifacts** | The per-run output bundle: `report.md` (human checklist), `summary.json` (machine state), `test-cases.json` (checkpoint list), `inputs.json` (effective inputs), `evidence/`. | under `scripts/test/.artifacts/copilot-cli-subsession-args-audit/run-<ts>-<pid>/` when run from the repo |

## Model switching (live cases)

| Term | Definition | Example |
| --- | --- | --- |
| **Hot-switch** | Changing the model *mid-session without stopping* the interactive CLI process (TUI `/model` or a flag on a live session). Unreliable across thinking models — history with thinking-mode turns trips the `reasoning_content` rule. | `l4` (flash→pro, same family), `l5` (flash→kimi, different family) |
| **Cold-switch** | *Stopping* the session (exit / ctrl+c) then *resuming* the same `SessionId` with a different model profile. The SUT's two-process shape (each `Invoke-CopilotCliSubSession` call spawns a child that exits) approximates this. | `l8` (luna→flash, wire responses→completions) |
| **`reasoning_content` 400** | `400 Error from provider … The reasoning_content in the thinking mode must be passed back to the API.` Occurs when history contains thinking-mode assistant turns that get replayed onto a wire/model that does not replay `reasoning_content`. Per-conversation/stateful — cannot be reproduced statelessly. | `l8` is the cold-switch probe for this class |
| **`model.call_start`** | The per-call model evidence in the session's `events.jsonl` (JSONL output). The harness's ground truth for which model actually served a turn — never trust self-identification text. | `Get-CallStartModel` helper |
