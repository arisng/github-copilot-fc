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

## Machine-parseable assertion syntax

The `Invoke-EvalSuite.ps1` script evaluates `passes_when` expressions using a whitelist-based dispatcher. **`Invoke-Expression` is never used.** Expressions must match one of the patterns below to be evaluated.

### Supported expression patterns

| Pattern | Example | What it checks |
|---------|---------|---------------|
| `word_count < N` | `word_count < 150` | Whitespace-delimited word count |
| `word_count > N` | `word_count > 50` | Whitespace-delimited word count |
| `word_count == N` | `word_count == 100` | Exact word count |
| `paragraph_count <= N` | `paragraph_count <= 3` | Double-newline-separated blocks |
| `heading_count >= N` | `heading_count >= 2` | Lines matching `^#{1,6}\s` |
| `sentence_count <= N` | `sentence_count <= 10` | Approximate split on `[.!?]+\s` |
| `no_sentence_exceeds(N)` | `no_sentence_exceeds(18)` | Max word count per sentence |
| `paragraph_1_sentence_count == N` | `paragraph_1_sentence_count == 1` | Sentences in first paragraph |
| `contains("text")` | `contains("required section")` | Case-insensitive substring |
| `not_contains("text")` | `not_contains("forbidden phrase")` | Inverse of contains |
| `matches_regex("pattern")` | `matches_regex("^#\s+\w+")` | Full-string regex match |
| `section_present("heading")` | `section_present("Installation")` | Case-insensitive heading match |
| `json_valid == true` | `json_valid == true` | Output parses as valid JSON |
| `heading_order("H1","H2")` | `heading_order("Installation","Usage")` | Headings appear in order |

### Grammar rules

- Format: `<metric><op><value>` or `<function>(<args>)` or `<metric> == <value>`
- Operators: `<`, `>`, `<=`, `>=`, `==`
- String arguments: double-quoted, matched greedily between first `("` and last `")`
- No nesting or boolean combinators (`AND`/`OR`) in v1 — keep assertions atomic
- Unparseable expressions → status `skipped` with `reason: "unparseable_expression"` (not a failure)

### Limitations

- Sentence splitting is approximate (splits on `.!?` + whitespace; abbreviations like "e.g." may cause false splits)
- Evaluators are designed for prose/documentation output; code-generation skills would need additional evaluators
- Use `evals/samples/<case-id>.md` files for output samples that assertions evaluate against
