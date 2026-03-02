---
category: reference
source_session: 260302-142754
source_iteration: 1
source_artifacts:
  - "Iteration 1 plan"
  - "Iteration 1 review"
  - "Iteration 1 session review report (cycle 1)"
  - "Iteration 1 task-14 report (validation run)"
extracted_at: 2026-03-02T20:11:56+07:00
promoted: true
promoted_at: 2026-03-02T20:22:26+07:00
---

# OpenSpec Ralph-v2 Domain Map

Quick-reference for the Ralph-v2 multi-agent orchestration specification suite authored in OpenSpec SDD format.

## Spec Root

All domain specs live under `openspec/specs/ralph-v2-orchestration/<domain>/spec.md`.

## Domain Summary

| Domain | Prefix | Requirements | Scenarios | Key Concerns |
|--------|--------|-------------|-----------|--------------|
| Session | SES | 25 | 17 | Identity, lifecycle, iteration model, vocabulary table, artifact ownership |
| Signals | SIG | 23 | 12 | Live intervention protocol, 4 signal types, targeting, polling |
| Orchestration | ORCH | 35 | 22 | 10-state machine, routing, transitions, messenger protocol |
| Planning | PLAN | 41 | 24 | 9 planning modes, task structure, waves, grounding requirements |
| Discovery | DISC | 36 | 18 | 3 modes (brainstorm, research, feedback), question categories |
| Execution | EXEC | 33 | 19 | Single-task model, progress tracking, rework lifecycle |
| Review | REV | 57 | 35 | 4 modes, 3 quality dimensions, verdicts, commit persistence |
| Knowledge | KNOW | 59 | 59 | 4-stage pipeline, Diátaxis classification, merge algorithm |
| **Total** | — | **309** | **206** | — |

## Cross-Reference Statistics

- **Defined requirement IDs**: 309 across 8 domain prefixes
- **Total cross-domain references**: 1,135+
- **Dangling references**: 0 (validated by `validate-cross-refs.ps1`)

## Domain Dependency Order

The specs were authored in dependency order reflecting cross-reference flow:

1. **Session** — defines abstract vocabulary table (16+ terms) used by all other specs
2. **Signals** — defines polling protocol referenced by all role specs
3. **Orchestration** — defines 10-state machine that drives role invocations
4. **Planning, Discovery, Execution, Review, Knowledge** — role specs, independent of each other but all reference (1)–(3)

## Validation Suite

Three custom scripts supplement `openspec validate --all`:

| Script | Purpose | Pass Criteria |
|--------|---------|---------------|
| `scripts/openspec/validate-runtime-leaks.ps1` | Scan for runtime-specific terminology | 0 blocklist violations |
| `scripts/openspec/validate-cross-refs.ps1` | Verify cross-domain ID references resolve | 0 dangling references |
| `scripts/openspec/validate-rfc2119.ps1` | Audit RFC 2119 keywords and scenario coverage | 0 missing keywords |

## Known Limitations

- **OpenSpec CLI SHOULD/MAY**: The CLI only recognizes MUST/SHALL as requirement keywords. Specs using SHOULD/MAY produce 86 ERROR-level issues that are cosmetic — no behavioral impact.
