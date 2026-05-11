---
name: grill-me
description: "Stress-test plans and designs through a one-question-at-a-time interview. Use when the user asks to 'grill me', pressure-test a repository strategy, module architecture, feature design, OpenSpec namespace spec, or proposed change. Walk each decision branch, surface dependencies, and recommend an answer for every question."
argument-hint: "Scope + target, for example: repository onboarding plan, Session module auth design, Lifeline feature rollout, OpenSpec platform namespace spec, or openspec change xyz"
---

# Grill Me

Relentlessly interview the user until there is shared understanding across all important decision branches.

## Supported Scopes

Use this workflow for any of these targets:
- Repository or project level strategy
- Module level architecture
- Feature design inside a module
- OpenSpec living spec namespace or a specific module capability inside a namespace
- OpenSpec proposed change

## Core Rules

- Ask exactly one question at a time.
- For each question, provide your recommended answer before waiting for user confirmation.
- If a question can be answered from the codebase or docs, investigate first and present evidence-backed findings instead of asking blindly.
- Keep drilling until each branch is resolved, explicitly deferred, or marked out of scope.
- Do not move to implementation advice until the decision tree is stable.

## Procedure

1. Frame the scope and objective.
- Confirm what is being stress-tested (repository, module, feature, namespace/capability, or change).
- Define the target outcome (approved design, implementable plan, review checklist, or decision record).

2. Build the initial decision tree.
- Identify major branches relevant to the scope:
  - Goals and success criteria
  - Functional behavior and scenarios
  - Boundaries, ownership, and interfaces
  - Data and state concerns
  - Security, permissions, and compliance
  - Performance, reliability, and failure handling
  - Testing and verification strategy
  - Rollout, migration, and rollback
  - Open risks, assumptions, and unknowns
- Order branches by risk and dependency so upstream decisions are resolved first.

3. Run the interview loop.
- Ask one high-impact question.
- Include:
  - Why the question matters
  - Recommended answer
  - Impact of accepting that recommendation
- Wait for the user answer before proceeding.

4. Branch resolution logic.
- If the user agrees: lock the decision and move to the next dependent branch.
- If the user disagrees: capture the alternative, test consequences, and ask the next narrowing question.
- If unknown: investigate code/spec/docs; if still unknown, mark as explicit risk with owner and trigger.
- If blocked by external dependency: record defer condition and continue with independent branches.

5. Evidence-first behavior.
- Prefer codebase exploration when facts are discoverable.
- Cite concrete artifacts (files, endpoints, contracts, specs, tasks) before escalating to user questions.
- Convert discovered facts into sharper follow-up questions.

6. Finish with a closure packet.
- Provide:
  - Final decision map (resolved branches)
  - Open questions and blockers
  - Assumptions to validate later
  - Recommended next action sequence
- Stop only when shared understanding is explicit.

## Quality Bar

A successful grilling session produces:
- No unresolved high-risk branch without an explicit defer reason
- Clear rationale for each major decision
- Traceable dependencies between decisions
- A practical next-step plan that can be executed or reviewed immediately

## Prompts You Can Use

- "Grill me on this repository refactor plan."
- "Grill me on the Session module permission model."
- "Grill me on this feature design in Lifeline."
- "Grill me on this OpenSpec platform namespace capability spec."
- "Grill me on openspec change zoom-admin-dashboard-oauth-ui."
