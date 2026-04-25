---
date: 2026-04-25
type: Feature Plan
status: Proposed
severity: High
tags:
  - openspec
  - custom-profile
  - workflow-governance
  - maintainability
  - automation
---

# OpenSpec Custom Profile Evolution Baseline

## Executive Summary

This issue defines the baseline plan to evolve an existing custom OpenSpec workflow so it remains easy to update from upstream OpenSpec while preserving repository-specific operating rules.

The strategy is to adopt a layered model:

- keep OpenSpec-generated workflow assets regenerable
- centralize durable local policy in instruction overlays
- keep child workflow skills thin and phase-specific

The output of this issue is a practical migration and governance plan that can be iteratively refined and used for implementation tracking.

## Context

A separate workspace already contains customized OpenSpec child skills for:

- propose
- explore
- apply-change
- archive-change

Current customization depth provides strong local behavior but increases drift risk when upstream OpenSpec updates regenerate workflow artifacts.

## Path Registry (Authoritative Lookup Paths)

Use the following paths as the source of truth when analyzing, refining, or implementing this custom OpenSpec workflow.

### External target workspace

- Workspace root: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit
- OpenSpec repo config: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\openspec\config.yaml
- OpenSpec living specs root: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\openspec\specs
- OpenSpec active changes root: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\openspec\changes
- OpenSpec generated prompts root: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\prompts
- OpenSpec repo instructions root: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\instructions

### External target workspace custom child skills

- Explore skill: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\skills\openspec-explore\SKILL.md
- Propose skill: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\skills\openspec-propose\SKILL.md
- Apply skill: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\skills\openspec-apply-change\SKILL.md
- Archive skill: C:\Users\DuyAnh\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\skills\openspec-archive-change\SKILL.md

### Current planning workspace references

- Baseline issue file: C:\Users\DuyAnh\Workplace\CodeF\github-copilot-fc\.issues\260425_openspec-custom-profile-evolution-baseline.md
- OpenSpec SDD routing skill reference: C:\Users\DuyAnh\Workplace\CodeF\github-copilot-fc\skills\openspec-sdd\SKILL.md

## Goals

- Preserve local workflow behavior that is stable and valuable.
- Minimize merge effort when applying upstream OpenSpec updates.
- Make the profile reusable across multiple repositories.
- Keep delivery mode as both skills and prompts.
- Establish a repeatable maintainer runbook for update and reconciliation.

## Non-Goals

- Replacing OpenSpec-generated workflow files with fully hand-authored equivalents.
- Redesigning the OpenSpec lifecycle phases.
- Implementing repository-specific product behavior in this planning artifact.

## Proposed Architecture

### Layer 1: Generated Base

Regenerable assets produced by OpenSpec update:

- workflow child skills
- workflow slash prompts

These files are treated as generated scaffolding and should stay lightweight.

### Layer 2: Policy Overlay

Centralized repository instructions for durable local governance:

- shared skill resolution guardrails
- runtime orchestration and prerequisites
- evidence protocol and naming conventions
- archive and commit governance

This layer is the primary customization boundary.

### Layer 3: Local Exceptions

Narrow, explicitly documented exceptions that are tightly coupled to one repository or one workflow phase.

## Extraction Map

High-priority extraction targets from customized child skills:

1. Shared resolution rules used across all child workflows.
2. Repeated runtime startup and discovery conventions used in propose, apply, and archive.
3. Cross-phase evidence naming and storage contract.
4. Archive-time commit and scope-governance workflow.

Medium-priority extraction targets:

1. Test-coverage and TDD ordering constraints used across propose, apply, and archive.
2. Specialized discovery tasks that should be reusable but remain optional per repo.

## Migration Plan

### Phase 1: Baseline and Contract

- [ ] Inventory current custom rules by source and frequency.
- [ ] Classify each rule as generated-base, policy-overlay, or local-exception.
- [ ] Define custom profile contract:
  - scope reusable across repositories
  - delivery mode both
  - workflows explore, propose, apply, archive

### Phase 2: Thin-Skill Refactor

- [ ] Refactor child workflow skills to retain only phase-unique orchestration.
- [ ] Move repeated policy blocks into centralized instruction overlays.
- [ ] Ensure child skills reference overlays consistently.

### Phase 3: Update Compatibility

- [ ] Define update sequence:
  - regenerate
  - reconcile overlays
  - validate parity
- [ ] Document conflict-handling strategy for generated file changes.
- [ ] Add lightweight drift checks after regeneration.

### Phase 4: Pilot and Rollout

- [ ] Pilot in one repository using full lifecycle dry run.
- [ ] Capture lessons and adjust overlay boundaries.
- [ ] Publish reusable profile template for additional repositories.

## Verification Plan

- [ ] Confirm profile configuration and workflow list match intended contract.
- [ ] Regenerate assets and verify expected skill-prompt pairs are produced.
- [ ] Diff child skills and confirm thin-wrapper constraints hold.
- [ ] Validate instruction reference integrity from all child workflows.
- [ ] Run one complete explore-to-archive dry run and check behavior parity.
- [ ] Run OpenSpec validation across specs and changes.

## Risks and Mitigations

### Risk: Policy Leakage Back into Generated Assets

Mitigation:

- enforce thin-skill review checklist
- keep repeated rules only in overlays

### Risk: Over-Centralization Reduces Flexibility

Mitigation:

- keep local exception layer explicit and narrow
- document override boundaries per repository

### Risk: Upstream Workflow Changes Break References

Mitigation:

- maintain update runbook with parity checks
- run drift checks after each regeneration

## Acceptance Criteria

- [ ] A reusable custom profile contract is documented and approved.
- [ ] Child workflow skills are thin and regeneration-friendly.
- [ ] Shared policy is centralized in instruction overlays.
- [ ] Upstream OpenSpec update path is documented as a repeatable runbook.
- [ ] A pilot dry run demonstrates behavior parity after regeneration.
- [ ] This issue can be used as baseline for iterative refinement and completion monitoring.

## Open Questions

- Should reusable profile assets be distributed by copy, template bootstrap, or centralized package workflow?
- Which drift checks should become automated versus manual in the first iteration?
- What threshold of local exceptions triggers extraction into shared overlays?

## References

- Existing OpenSpec child workflow skills in the target repository
- Existing repository instruction set governing workflow behavior
- OpenSpec generated workflow update mechanism
