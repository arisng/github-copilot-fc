---
date: 2026-11-20
type: Bug
severity: Low
status: Open
---

# Bug: copilot-cli-subsession audit harness has 5 BYOK environment failures

## Symptom

The `copilot-cli-subsession` audit harness fails five scenarios on this machine:
`s4-5`, `s5-2`, `s5-3`, `s5-5`, and `s6-2`. The failures reproduce without any
dependency on paths deleted during the 2026-11-20 cleanup, and they were never
part of the workspace gate (`workspace-check.ps1` does not run the harness).

## Analysis so far

- Classified as environmental: the harness scenarios depend on BYOK provider
  environment (provider profile / API key state) that is not visible to — and
  not provisioned by — the audit run itself.
- Because they sit outside the gate, they do not block commits or pushes, which
  is why they stayed open rather than forcing a fix during the cleanup.

## Tasks

- [ ] Capture the failing output for one scenario (`s4-5`) with the BYOK
      environment printed (redacted for secrets) to confirm the provider-state
      hypothesis.
- [ ] Decide the contract: either the harness preflights BYOK availability and
      reports SKIP for provider-dependent scenarios, or the harness documents
      the required provider profile and fails loudly when it is absent.
- [ ] Implement the chosen contract and re-run the full audit harness to a
      zero-unexplained-failure state.
- [ ] Wire the harness run (or a smoke subset) into a `task` target so the next
      regression is visible without a manual dispatch.

## References

- Skill: `skills/copilot-cli-subsession/` (audit harness and scenario ids)
- Gate scope: `scripts/workspace/workspace-check.ps1` (harness intentionally not wired)
