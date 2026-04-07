---
name: skill-self-improvement
description: Optimize existing AI agent skills with a dual-loop workflow for activation tuning and execution quality. Use when improving a skill after initial creation, diagnosing false triggers or missed triggers, converting subjective output goals into binary assertions, building or refining eval.json test suites, or iteratively refining SKILL.md rules against repeatable checks with a final human review pass.
metadata: 
  author: arisng
  version: 0.1.0
---

# AI Skill Self-Improvement

Optimize an existing skill by separating two problems:

1. **Activation**: the skill fires on the right prompts.
2. **Execution**: the skill produces the right output after it fires.

Use `skill-creator` for first drafts. Use this skill to improve a skill that already exists.

## Decide the loop

1. If the problem is **when the skill fires**, run the activation loop.
2. If the problem is **what the skill produces**, run the execution loop.
3. If both are wrong, fix **activation first**, then execution.
4. Never optimize both layers in the same iteration.

## Load only the minimum working set

Read only:

- the target `SKILL.md`
- any references that materially affect output
- a small prompt set that should trigger
- a small prompt set that should not trigger
- a few representative success and failure outputs

Load these references only when needed:

- `references/assertion-playbook.md` to turn vague quality goals into binary checks
- `references/dual-loop-workflow.md` for the full sequence, guardrails, and loop diagram

Copy these assets into the target skill project when you need a starting point:

- `assets/activation-matrix-template.md`
- `assets/eval-template.json`
- `assets/continuous-eval-log-template.md`

## Run the activation loop

Keep the body fixed and change only the frontmatter `description`.

1. Copy `assets/activation-matrix-template.md` into the target skill project.
2. Add positive prompts that should trigger.
3. Add negative prompts that should not trigger.
4. Measure false positives and false negatives with the runtime's native trigger behavior or the best available prompt-set test.
5. Tighten or broaden the description based on the observed failures.
6. Keep the new description only if trigger accuracy improves.

### Activation rules

- Name concrete actions, artifacts, and situations instead of broad domains.
- Include nearby trigger phrases that should activate the skill.
- Mention confusing neighbor tasks when disambiguation matters.
- Prefer explicit verbs and file or workflow names over abstract labels.
- Keep execution rules out of the description.

## Run the execution loop

Keep the description fixed and change only execution guidance.

1. Copy `assets/eval-template.json` into `evals/eval.json` in the target skill project.
2. Convert output requirements into binary assertions only.
3. Move subjective quality checks into a human review section instead of pretending they are objective.
4. Change one rule at a time in `SKILL.md` or a referenced file.
5. Run the eval suite.
6. Keep the change if the score improves.
7. Revert the change if the score drops or creates conflicting assertions.
8. If a human rejects a perfect-scoring output, log it and derive a new assertion candidate.

### Execution rules

- Prefer structural, formatting, and readability checks first.
- Pair upper-bound assertions with completeness checks so the loop cannot win by saying less.
- Keep the assertion set small and high-signal before expanding it.
- Stop adding checks when two assertions start fighting each other.
- Treat score plateaus as a sign to simplify the rule set or escalate to human review.

## Use binary assertions correctly

A good assertion is:

- observable from the output alone
- pass or fail without debate
- tied to one behavior
- difficult to game accidentally
- cheap to rerun

Bad assertions:

- "is engaging"
- "feels premium"
- "sounds smart"

Rewrite vague goals into measurable proxies. Use `references/assertion-playbook.md`.

## Keep a human review backstop

Run human review when:

- outputs pass structure checks but feel incoherent
- the loop starts gaming the assertions
- tone, originality, or semantic quality matters
- two assertions conflict and the tradeoff is product-specific

Copy `assets/continuous-eval-log-template.md` into the target project and record every rejected "perfect" output. Each rejected entry is a candidate for a new assertion or for moving a requirement back into human review.

## Default deliverables

When asked to set up this framework for a target skill, produce:

1. an activation prompt matrix
2. an `evals/eval.json` draft with binary checks
3. the single next rule change to try
4. a short note naming what remains subjective

## Guardrails

- Optimize one layer at a time.
- Change one rule at a time.
- Keep the eval suite smaller than the temptation to overfit it.
- Treat "perfect score, bad result" as missing instrumentation, not success.
- If coherence degrades, add semantic sanity checks or restore human review instead of stacking more structural rules.
