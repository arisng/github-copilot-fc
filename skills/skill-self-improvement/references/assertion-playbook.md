# Assertion Playbook

Use this playbook to turn subjective quality requests into binary assertions that a loop can score reliably.

## Conversion procedure

1. Highlight every vague adjective or taste-based phrase in the request.
2. Ask what visible output trait would convince a reviewer that the goal was met.
3. Convert each trait into one pass/fail check.
4. Pair every compression rule with a completeness rule.
5. Remove any check that requires mind reading or taste.
6. Run a conflict sweep before adding the assertion to the suite.

## High-signal assertion categories

| Category | Good assertion patterns | Common failure mode |
|---|---|---|
| Structural | word count, paragraph count, heading order, required sections present | only limiting length and forgetting completeness |
| Formatting | forbidden punctuation, valid JSON, exact heading labels, no nested bullets | polishing the surface without improving usefulness |
| Readability | max sentence length, max paragraph length, one-sentence lead, short bullets | over-constraining every sentence |
| Domain-bound | required entities appear, forbidden terms absent, approved glossary used | no source of truth for the domain terms |
| Coverage | every required input or source is mentioned, each prompt dimension is addressed | pretending coverage alone proves quality |

## Rewrite patterns

| Subjective request | Do not write | Prefer these binary proxies |
|---|---|---|
| Make it punchy | "is engaging" | output begins with an action verb; first paragraph is one sentence; no sentence exceeds 18 words |
| Keep it concise | "feels brief" | total word count is under the agreed cap; output has no more than 3 paragraphs; no list has more than 5 items |
| Make it easy to scan | "is scannable" | output includes 2 to 4 headings; each heading is followed by no more than 3 sentences; bullets start with a verb or noun phrase consistently |
| Follow our format | "matches the template" | headings appear in exact order; required fields are all present; no extra top-level sections exist |
| Stay on brand | "sounds premium" | approved product names appear; forbidden phrases are absent; glossary terms from the reference file are used where required |

## Guard against gaming

A loop can optimize the wrong thing if the assertions are too easy to satisfy.

Countermeasures:

- Pair shortness limits with required-content checks.
- Pair format checks with evidence or coverage checks.
- Add a minimum-information rule when you add a maximum-length rule.
- Reject assertions that reward empty outputs.

Example:

- Weak: `word_count < 150`
- Stronger: `word_count < 150` and `mentions all required inputs` and `contains the requested final action`

## Remove bad assertions early

Delete assertions that are:

- compound: two or more behaviors hidden in one check
- contradictory: impossible to satisfy together
- redundant: already covered by another check
- taste-based: only a human can judge them
- unstable: hard to measure consistently

## Use human review intentionally

Keep a requirement in human review when:

- the requirement is mostly about tone or originality
- the only proxy is weak and easy to game
- semantic coherence matters more than structure
- the team cannot agree on a single pass/fail rule

When a human rejects a perfect-scoring output, log the failure and ask:

1. Is there a missing binary check?
2. Is the check possible but not yet instrumented?
3. Is this requirement inherently subjective and better left human-reviewed?

## Practical target size

Start with 10 to 25 high-signal assertions, not an exhaustive wall of rules.

Add a new assertion only after a real failure teaches you what the suite missed.
