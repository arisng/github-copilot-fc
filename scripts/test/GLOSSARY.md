# Test Harness Glossary (Repo-Level Tooling)

Canonical definitions for the vocabulary used by **repo-level** test tooling and this directory's
documentation. This file is for the harnesses that live in `scripts/test/` — it is **not** referenced
by any skill's `SKILL.md` (skills must be self-contained; a skill that documents harness vocabulary
keeps its own glossary inside the skill, e.g. `skills/copilot-cli-subsession/references/glossary.md`).

**Scope — repo-level harnesses:**

- `scripts/test/copilot-byok-feature-test.ps1` (the *byok* feature harness — drives `skills/copilot-byok/scripts/byok-profile.ps1`; the harness itself is repo tooling because it needs publish-script isolation helpers)

**Deprecated:** `scripts/test/ralph-v2-cli-smoke.ps1` (the *Ralph CLI smoke* harness) is **deprecated**
(user decision 2026-08-05). It originated the report/evidence conventions below and is referenced
historically for that reason, but it is **not** an active harness and must not be extended.

---

## Terms

| Term | Definition | Where used | Example |
| --- | --- | --- | --- |
| **Test case ID** | Unique identifier for one case. Format `<bucket-prefix><n>[-<sub>]`. The byok harness uses `t*`; the subsession harness (inside its skill) uses `s*`/`l*`. | All harnesses; report rows | `t4-7`, `l8-t1` |
| **Shim** | A fake `copilot.ps1` on the child `PATH` that intercepts the `copilot` invocation and logs the exact args + emitted provider env. Zero cost, no tokens. | byok `run` cases (reasoning stripping) | `t4.x` shim log |
| **Test double** | Generic term for a fake dependency; a shim is one kind. | All harnesses | shim above |
| **Hermetic mode** | Runs with no network/real-API calls; dependencies stubbed or sentineled. Deterministic and free. | byok `t*` cases (default) | fixture-driven run |
| **Live mode** | Opt-in real-CLI/real-key runs (tokens cost money); guarded by preconditions + a cost guardrail. | subsession harness `-Live` (inside its skill) | `tests:subsession-audit-live` |
| **Sentinel key** | Fake API-key value injected per child so key handling is asserted without real keys. | byok harness (`Get-SentinelChildEnv`) | `KEY=sentinel-opencode-work-key` |
| **Dojo / staging home** | Durable test `COPILOT_HOME` (`~/.copilot-staging`), pre-seeded from production. | byok `-StagingHome ~/.copilot-staging`; subsession harness | `-CopilotHome <dojo>` |
| **Isolation gate** | Before/after assertion that production/dojo were not mutated (SHA-256 hash). Violation → throw. | byok `t1.x`; subsession `s8-6` | production hash unchanged |
| **Spike gate** | First-run preflight proving harness machinery works before any case runs; failure → abort (exit 2). | both harnesses | `SHIM_NOT_WINNING` → abort |
| **PASS / FAIL / SKIP / KNOWN-GAP** | Case status taxonomy. KNOWN-GAP = documents known-imperfect current behavior as a PASS with a gap label (backlog for future fixes). | both harnesses | `t2-6` (wizard never prompts wireApi) |
| **Polarity-agnostic** | Case does not hard-code which outcome is correct; records whichever occurs (clean → PASS, known issue → KNOWN-GAP). Used when characterizing unknown behavior. | subsession `l8` (inside its skill) | cold-switch luna→flash |
| **Exit codes** | `0` all pass (known-gap counts as pass), `1` one or more failures, `2` harness/preflight error. | both harnesses | `tests:byok-features` → 0 |
| **Evidence / run artifacts** | Per-run bundle: `report.md`, `summary.json`, `test-cases.json`, `inputs.json`, `evidence/` (per-case stdout/stderr + shim logs). | both harnesses | under `scripts/test/.artifacts/<harness>/run-<ts>-<pid>/` |
