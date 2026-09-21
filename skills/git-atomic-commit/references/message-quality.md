# Commit Message Quality Standards

Detailed guidance for writing commit messages. Read when generating commit messages (Workflow step 7).

## Why Detail Matters

Provide sufficient detail for accurate changelog generation and knowledge graph tracking. Vague messages lead to misleading summaries.

## Quality Requirements

- **Deletions:** List specific items removed (files, features, agents, etc.)
- **Bulk changes:** Specify each major component affected
- **Refactors:** Detail what was restructured and why
- **Additions:** Describe new capabilities or features clearly

**Good Example (Specific):**

```text
copilot(custom-agent): remove unused agents - conductor, context7, implementation, microsoft-docs

Removes four specialized agents that were redundant.
Streamlines agent portfolio and reduces maintenance overhead.
```

**Bad Example (Vague):**

```text
refactor: update agent definitions
```

## Plain English, in the Repository's Own Words

Specific is necessary but not sufficient. A message must be readable by someone
who was not in the session — and it must use the words the repository already
uses for the thing being described.

- **Write plain English.** No session-only shorthand, no plan labels
  ("pass 2", "ship 1", "phase 3 step 4"), no undefined acronyms. A reader who
  opens the repository tomorrow must be able to resolve every noun without the
  session that produced it.
- **Prefer the repository's established vocabulary.** Before naming a domain
  concept, check what this repository already calls it. Many repositories keep a
  `CONTEXT.md` (and often a `CONTEXT-MAP.md`) per bounded context; read the
  owning one and use its terms. Heed any `_Avoid_:` list — those are the synonyms
  that are specifically wrong.
- **Prefer durable references over session references.** Point at other
  issue/PR numbers, committed file paths, and committed docs — not at
  registers, notes, or artifacts that only exist in the session.

> **Repository conformance:** if the repository defines a terminology rule (for
> example an instructions file under `.github/instructions/`, a style guide, or
> an audit script), that rule wins over this guidance and is the source of truth
> for which terms are banned and which are encouraged. This section is the
> portable craft; the repository owns the specifics.

## Example: Session-Scoped → Plain English

```text
# ❌ leans on session vocabulary that the repository cannot resolve
feat(session): finish pass 2 spoke work for the brainstorm flow

# ✅ same change, resolved from the repository alone
feat(session): add grounded hierarchy checks to the brainstorm flow

The third-level hierarchy cap was not exercised end to end, so a recursive
child could be created below the documented limit. Adds coverage in
src/Tests/Integration.Tests/Session/PmBrainstormHierarchyGroundingTests.cs.
```